defmodule GgenIgniter.EphemeralProjectionTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{Digest, EphemeralProjection}

  @sha "sha256:" <> String.duplicate("a", 64)

  defp opts(overrides \\ []) do
    Keyword.merge(
      [
        name: "lib/generated/runtime.ex",
        graph_digest: @sha,
        generator_digest: @sha,
        environment_digest: @sha,
        dependency_digest: @sha,
        builder_id: "https://github.com/seanchatmangpt/ggen_igniter",
        invocation_id: "run-42",
        resolved_dependencies: [
          %{"uri" => "pkg:hex/rdf@3.0.0", "digest" => %{"sha256" => String.duplicate("b", 64)}}
        ]
      ],
      overrides
    )
  end

  test "manufactures an admitted disposable projection from exact bytes" do
    bytes = "machine native projection"

    assert {:ok, projection} = EphemeralProjection.manufacture(bytes, opts())
    assert projection.artifact_digest == Digest.sha256(bytes)
    assert projection.status == :manufactured
    assert projection.disposition == :ephemeral
    assert projection.authority_ceiling == :construct
  end

  test "refuses DO authority rather than interpreting autonomy as permission" do
    assert {:error, {:refused_epoch_invariant, mismatches}} =
             EphemeralProjection.manufacture("bytes", opts(authority_ceiling: :do))

    assert mismatches.generator_authority_ceiling == %{expected: :construct, observed: :do}
  end

  test "verification is evidence and retirement remains an authority-free intent" do
    verification = "sha256:" <> String.duplicate("c", 64)

    assert {:ok, projection} = EphemeralProjection.manufacture("bytes", opts())
    assert {:ok, verified} = EphemeralProjection.verify(projection, verification)
    assert verified.status == :verified

    assert {:ok, intent} = EphemeralProjection.retirement_intent(verified)
    assert intent.operation == :retire_projection
    assert intent.authority == :none
    assert intent.verification_receipt_hash == verification
  end

  test "unverified projections cannot be retired" do
    assert {:ok, projection} = EphemeralProjection.manufacture("bytes", opts())

    assert {:error, {:refused_ephemeral_projection, :unverified_retirement, :manufactured}} =
             EphemeralProjection.retirement_intent(projection)
  end

  test "emits in-toto statement with SLSA provenance predicate shape" do
    assert {:ok, projection} = EphemeralProjection.manufacture("bytes", opts())
    statement = EphemeralProjection.provenance_statement(projection)

    assert statement["_type"] == "https://in-toto.io/Statement/v1"
    assert statement["predicateType"] == "https://slsa.dev/provenance/v1"
    assert [%{"digest" => %{"sha256" => digest}}] = statement["subject"]
    assert digest == Digest.hex("bytes")

    definition = statement["predicate"]["buildDefinition"]
    assert definition["externalParameters"]["semanticGraphDigest"] == @sha
    assert definition["externalParameters"]["authorityCeiling"] == "construct"
    assert length(definition["resolvedDependencies"]) == 1
  end
end
