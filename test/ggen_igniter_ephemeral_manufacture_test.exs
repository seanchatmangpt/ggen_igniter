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

  test "attests exact bytes from an existing alive receipt without adding actuation" do
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
