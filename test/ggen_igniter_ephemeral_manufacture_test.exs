defmodule GgenIgniter.EphemeralManufactureTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{Digest, EphemeralManufacture, EphemeralProjection, Receipt}

  @a "sha256:" <> String.duplicate("a", 64)
  @b "sha256:" <> String.duplicate("b", 64)
  @c "sha256:" <> String.duplicate("c", 64)

  defp provenance_opts do
    [
      generator_digest: @a,
      environment_digest: @b,
      dependency_digest: @c,
      builder_id: "https://github.com/seanchatmangpt/ggen_igniter",
      invocation_id: "run-ephemeral-1",
      resolved_dependencies: []
    ]
  end

  test "attests exact bytes from an existing alive receipt without adding actuation" <>
         " (bytes proven against the receipt's post_run_hash)" do
    dir = Path.join(System.tmp_dir!(), "ggen-ephemeral-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "generated.ex")
    bytes = "defmodule Generated do\nend\n"
    File.write!(path, bytes)

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [path],
        post_run_hash: Receipt.hash_files([path]),
        metadata: %{"graph_hash" => @a}
      })

    assert {:ok, result} = EphemeralManufacture.attest_receipt(receipt, provenance_opts())
    assert [projection] = result.projections
    assert projection.status == :verified
    assert projection.artifact_digest == Digest.sha256(bytes)
    assert projection.verification_receipt_hash == receipt.receipt_hash

    assert [statement] = result.provenance

    assert statement["predicate"]["runDetails"]["metadata"]["verificationReceiptHash"] ==
             receipt.receipt_hash

    assert [retirement] = result.retirement_intents
    assert retirement.operation == :retire_projection
    assert retirement.authority == :none
  end

  # GGEN-2601's exact falsifier: a real :alive receipt, one receipted output
  # mutated after the fact, then attestation -- must REFUSE with the digest
  # mismatch named, never verify post-receipt-modified bytes against the
  # pre-receipt receipt. Real tmp files, real on-disk mutation.
  test "refuses to verify when a receipted output was mutated after the receipt (TOCTOU falsifier)" do
    dir =
      Path.join(System.tmp_dir!(), "ggen-ephemeral-tamper-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "generated.ex")
    File.write!(path, "defmodule Generated do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [path],
        post_run_hash: Receipt.hash_files([path]),
        metadata: %{"graph_hash" => @a}
      })

    # t1: mutate the receipted output AFTER the receipt (t0) exists.
    File.write!(path, "defmodule Tampered do\n  # post-receipt mutation\nend\n")

    # t2: attest must refuse, naming both digests.
    assert {:error, %{receipt: ^receipt, reason: reason}} =
             EphemeralManufacture.attest_receipt(receipt, provenance_opts())

    assert {:refused_ephemeral_attestation, :post_run_hash_mismatch,
            %{expected: expected, observed: observed}} = reason

    assert expected == receipt.post_run_hash
    assert observed == Receipt.hash_files([path])
    assert observed != expected
  end

  test "refuses to verify when ANY one file of a multi-file receipted set was mutated" do
    dir =
      Path.join(System.tmp_dir!(), "ggen-ephemeral-multi-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    first = Path.join(dir, "first.ex")
    second = Path.join(dir, "second.ex")
    File.write!(first, "defmodule First do\nend\n")
    File.write!(second, "defmodule Second do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [first, second],
        post_run_hash: Receipt.hash_files([first, second]),
        metadata: %{"graph_hash" => @a}
      })

    File.write!(second, "defmodule Second do\n  # only this one changed\nend\n")

    assert {:error, %{reason: {:refused_ephemeral_attestation, :post_run_hash_mismatch, _}}} =
             EphemeralManufacture.attest_receipt(receipt, provenance_opts())
  end

  test "refuses an alive receipt that carries no post_run_hash at all (nothing to bind)" do
    dir =
      Path.join(System.tmp_dir!(), "ggen-ephemeral-nohash-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "generated.ex")
    File.write!(path, "defmodule Generated do\nend\n")

    receipt =
      Receipt.new(%{
        standing: :alive,
        files: [path],
        metadata: %{"graph_hash" => @a}
      })

    assert {:error, %{reason: {:refused_ephemeral_attestation, :post_run_hash_missing, nil}}} =
             EphemeralManufacture.attest_receipt(receipt, provenance_opts())
  end

  test "refuses attestation for non-alive reconciliation standings" do
    receipt = Receipt.new(%{standing: :refused, metadata: %{"graph_hash" => @a}})

    assert {:error, %{receipt: ^receipt, reason: reason}} =
             EphemeralManufacture.attest_receipt(receipt, provenance_opts())

    assert reason == {:refused_ephemeral_attestation, :standing, :refused}
  end

  test "shared provenance admission fails closed before reconciliation" do
    opts = Keyword.delete(provenance_opts(), :generator_digest)

    assert {:error, {:refused_ephemeral_projection, :missing_option, :generator_digest}} =
             EphemeralProjection.admit_provenance_opts(opts)
  end
end
