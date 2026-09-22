defmodule GgenIgniter.Gall.Receipt002Court do
  @moduledoc false

  alias GgenIgniter.{EphemeralManufacture, Pack, Receipt}
  alias GgenIgniter.Gall.ProjectManufacturer

  def run(gall001_path, out_path) do
    source = gall001_path |> File.read!() |> Jason.decode!()
    source_digest = sha_file(gall001_path)
    graph_digest = normalize_sha256(get_in(source, ["graph", "canonical_digest"]))
    work_order_digest = normalize_sha256(get_in(source, ["work_order", "canonical_digest"]))

    root = Path.join(System.tmp_dir!(), "gall-002-#{System.unique_integer([:positive, :monotonic])}")
    projection_path = Path.join(root, "lib/generated/gall002.ex")
    File.mkdir_p!(Path.dirname(projection_path))

    bytes =
      [
        "defmodule GgenIgniter.Gall.Generated002 do\n",
        "  @gall001_receipt ",
        inspect(source_digest),
        "\n",
        "  def upstream_receipt, do: @gall001_receipt\n",
        "end\n"
      ]
      |> IO.iodata_to_binary()

    File.write!(projection_path, bytes)
    first_projection = Receipt.hash_files([projection_path])
    File.rm!(projection_path)
    File.write!(projection_path, bytes)
    second_projection = Receipt.hash_files([projection_path])

    if first_projection != second_projection do
      raise "GALL-002 deterministic regeneration mismatch"
    end

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [projection_path],
        post_run_hash: second_projection,
        metadata: %{"graph_hash" => graph_digest}
      })

    manifest = %Pack.Manifest{
      name: get_in(source, ["subject", "pack"]) || "gall-pack",
      version: get_in(source, ["subject", "version"]) || "UNKNOWN",
      description: "GALL-002 exact upstream receipt projection"
    }

    repo_sha = git_head!()
    mix_lock_digest = sha_file("mix.lock")
    toolchain = %{
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> to_string(),
      igniter: app_version(:igniter)
    }

    opts = [
      repo_sha: repo_sha,
      profile: "Core1",
      generator_tasks: ["GgenIgniter.Gall.ProjectManufacturer"],
      mix_lock_digest: mix_lock_digest,
      toolchain: toolchain
    ]

    {:ok, manufacturer} =
      ProjectManufacturer.from_receipt(graph_digest, manifest, receipt, opts)

    provenance_opts = [
      generator_digest: sha_file("scripts/gall_checkpoint_002_receipt.exs"),
      environment_digest: ProjectManufacturer.digest(toolchain),
      dependency_digest: source_digest,
      builder_id: "https://github.com/seanchatmangpt/ggen_igniter",
      invocation_id: "GALL-002",
      resolved_dependencies: [
        %{
          "uri" => "urn:sa2a:gall:001:replay-receipt",
          "digest" => %{"sha256" => String.replace_prefix(source_digest, "sha256:", "")}
        }
      ]
    ]

    {:ok, attestation} = EphemeralManufacture.attest_receipt(receipt, provenance_opts)

    payload = %{
      "schema" => "ggen_igniter.gall.project-manufacturer/v26.9.18",
      "standing" => "ALIVE",
      "repo_sha" => repo_sha,
      "gall_001_receipt_digest" => source_digest,
      "graph_digest" => graph_digest,
      "work_order_digest" => work_order_digest,
      "manifest_identity" => %{
        "name" => manifest.name,
        "version" => manifest.version,
        "description" => manifest.description
      },
      "profile" => "Core1",
      "manufacturer_digest" => manufacturer.manufacturer_digest,
      "generator_tasks" => manufacturer.generator_tasks,
      "mix_lock_digest" => manufacturer.mix_lock_digest,
      "toolchain" => manufacturer.toolchain,
      "projection_digest" => manufacturer.projection_digest,
      "post_run_hash" => receipt.post_run_hash,
      "attestation_digest" =>
        ProjectManufacturer.digest(%{
          provenance: attestation.provenance,
          receipt_hash: receipt.receipt_hash
        }),
      "generated_files" => [
        %{"path" => "lib/generated/gall002.ex", "digest" => manufacturer.projection_digest}
      ],
      "regeneration" => "PASS"
    }

    File.mkdir_p!(Path.dirname(out_path))
    File.write!(out_path, Jason.encode!(payload, pretty: true) <> "\n")
    File.rm_rf!(root)
    payload
  end

  def self_test(out_path) do
    root = Path.join(System.tmp_dir!(), "gall-002-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    source_path = Path.join(root, "gall-001.json")

    source = %{
      "subject" => %{"pack" => "gall-pack", "version" => "1.0.0"},
      "graph" => %{"canonical_digest" => sha("graph")},
      "work_order" => %{"canonical_digest" => sha("work-order")}
    }

    File.write!(source_path, Jason.encode!(source))
    payload = run(source_path, out_path)
    File.rm_rf!(root)

    true = payload["regeneration"] == "PASS"
    true = payload["projection_digest"] == payload["post_run_hash"]
    true = payload["standing"] == "ALIVE"
    payload
  end

  defp app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> "unavailable"
      value -> to_string(value)
    end
  end

  defp git_head! do
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true)
    String.trim(sha)
  end

  defp normalize_sha256("sha256:" <> _ = digest), do: digest
  defp normalize_sha256(hex) when is_binary(hex) and byte_size(hex) == 64, do: "sha256:" <> hex
  defp normalize_sha256(other), do: raise("GALL-002 requires SHA-256 identity, got: #{inspect(other)}")

  defp sha_file(path) do
    "sha256:" <> (:crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower))
  end

  defp sha(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end

case System.argv() do
  ["--self-test", out_path] ->
    payload = GgenIgniter.Gall.Receipt002Court.self_test(out_path)
    IO.puts(Jason.encode!(payload))

  [gall001_path, out_path] ->
    payload = GgenIgniter.Gall.Receipt002Court.run(gall001_path, out_path)
    IO.puts(Jason.encode!(payload))

  _ ->
    IO.puts(:stderr, "usage: mix run scripts/gall_checkpoint_002_receipt.exs -- --self-test OUT.json")
    IO.puts(:stderr, "   or: mix run scripts/gall_checkpoint_002_receipt.exs -- GALL001.json OUT.json")
    System.halt(2)
end
