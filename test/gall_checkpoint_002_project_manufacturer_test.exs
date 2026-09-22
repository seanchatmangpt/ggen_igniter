defmodule GgenIgniter.Gall.ProjectManufacturerTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{EphemeralManufacture, Pack, Receipt}
  alias GgenIgniter.Gall.ProjectManufacturer

  @graph "sha256:" <> String.duplicate("a", 64)
  @mix_lock "sha256:" <> String.duplicate("b", 64)
  @generator "sha256:" <> String.duplicate("c", 64)
  @environment "sha256:" <> String.duplicate("d", 64)
  @dependency "sha256:" <> String.duplicate("e", 64)

  defp manifest do
    %Pack.Manifest{name: "gall-pack", version: "26.9.18", description: "GALL-002 fixture"}
  end

  defp subject_opts(projection_digest) do
    [
      repo_sha: "deadbeef",
      profile: "Core1",
      generator_tasks: ["ash.gen.resource", "ash.gen.domain"],
      mix_lock_digest: @mix_lock,
      projection_digest: projection_digest,
      toolchain: %{elixir: "1.17", otp: "27", igniter: "pinned"}
    ]
  end

  defp provenance_opts do
    [
      generator_digest: @generator,
      environment_digest: @environment,
      dependency_digest: @dependency,
      builder_id: "https://github.com/seanchatmangpt/ggen_igniter",
      invocation_id: "gall-002",
      resolved_dependencies: []
    ]
  end

  test "manufacturer identity is deterministic and generator-order independent" do
    projection = "sha256:" <> String.duplicate("f", 64)

    assert {:ok, left} = ProjectManufacturer.build(@graph, manifest(), subject_opts(projection))

    reordered =
      subject_opts(projection)
      |> Keyword.put(:generator_tasks, ["ash.gen.domain", "ash.gen.resource"])

    assert {:ok, right} = ProjectManufacturer.build(@graph, manifest(), reordered)
    assert left.manufacturer_digest == right.manufacturer_digest

    changed =
      subject_opts(projection)
      |> Keyword.put(:generator_tasks, ["ash.gen.resource", "ash.gen.domain", "ash.gen.migration"])

    assert {:ok, changed_subject} = ProjectManufacturer.build(@graph, manifest(), changed)
    refute changed_subject.manufacturer_digest == left.manufacturer_digest
  end

  test "from_receipt binds the manufacturer to current receipted projection bytes" do
    dir = Path.join(System.tmp_dir!(), "gall-002-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "generated.ex")
    File.write!(path, "defmodule Generated do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [path],
        post_run_hash: Receipt.hash_files([path]),
        metadata: %{"graph_hash" => @graph}
      })

    assert {:ok, subject} =
             ProjectManufacturer.from_receipt(
               @graph,
               manifest(),
               receipt,
               Keyword.delete(subject_opts(receipt.post_run_hash), :projection_digest)
             )

    assert subject.projection_digest == receipt.post_run_hash
  end

  test "post-receipt projection drift is refused by both manufacturer and attestation" do
    dir = Path.join(System.tmp_dir!(), "gall-002-drift-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "generated.ex")
    File.write!(path, "defmodule Generated do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [path],
        post_run_hash: Receipt.hash_files([path]),
        metadata: %{"graph_hash" => @graph}
      })

    File.write!(path, "defmodule Drifted do\nend\n")

    assert {:error, {:refused_project_manufacturer, {:projection_drift, _}}} =
             ProjectManufacturer.from_receipt(
               @graph,
               manifest(),
               receipt,
               Keyword.delete(subject_opts(receipt.post_run_hash), :projection_digest)
             )

    assert {:error, %{reason: {:refused_ephemeral_attestation, :post_run_hash_mismatch, _}}} =
             EphemeralManufacture.attest_receipt(receipt, provenance_opts())
  end

  test "missing post-run hash refuses instead of inventing projection identity" do
    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [],
        metadata: %{"graph_hash" => @graph}
      })

    assert {:error, {:refused_project_manufacturer, :post_run_hash_missing}} =
             ProjectManufacturer.from_receipt(
               @graph,
               manifest(),
               receipt,
               Keyword.delete(subject_opts(@graph), :projection_digest)
             )
  end
end
