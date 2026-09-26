defmodule GgenIgniter.SemanticJiraAuthorityIndexHardeningTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Authority

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @pinned @sj <> "objective-code-work-authority"
  @forged "sha256:" <> String.duplicate("f", 64)

  defp canonical do
    RDF.Turtle.read_file!(Authority.canonical_path())
  end

  test "index binds admitted/refused maps to the exact source graph digest" do
    graph = canonical()
    index = Authority.index(graph)

    assert index.source_graph == graph
    assert index.source_digest == Authority.graph_digest(graph)
    assert {:ok, _pinned} = Authority.index_from(authority: index)

    tampered = put_in(index, [:admitted, @pinned], @forged)

    assert {:error,
            {:authority_index_unavailable, nil, :precomputed_authority_index_mismatch}} =
             Authority.index_from(authority: tampered)
  end

  test "source digest tampering refuses before trust-root pinning" do
    index = Authority.index(canonical())
    tampered = %{index | source_digest: @forged}

    assert {:error,
            {:authority_index_unavailable, nil,
             :precomputed_authority_source_digest_mismatch}} =
             Authority.index_from(authority: tampered)
  end

  test "bare precomputed indexes are refusal carriers, never admission sources" do
    bare = %{admitted: %{@pinned => @forged}, refused: %{}}

    assert {:ok, pinned} = Authority.index_from(authority: bare)
    assert pinned.admitted == %{}

    assert {:error, {:refused_origin, {:authority_not_pinned, @pinned}}} =
             Authority.resolve(pinned, @pinned)
  end

  test "pin makes admitted and refused sets disjoint by refusing overlap" do
    {:ok, pins} = Authority.trust_roots()
    index = Authority.index(canonical())

    conflicted =
      put_in(
        index,
        [:refused, @pinned],
        {:authority_not_admitted, @pinned}
      )

    pinned = Authority.pin(conflicted, pins)

    refute Map.has_key?(pinned.admitted, @pinned)
    assert pinned.refused[@pinned] == {:authority_index_conflict, @pinned}
  end

  test "malformed admitted digest is a typed refusal instead of a silent drop" do
    {:ok, pins} = Authority.trust_roots()
    index = Authority.index(canonical())
    malformed = put_in(index, [:admitted, @pinned], "sha256:BAD")

    pinned = Authority.pin(malformed, pins)

    refute Map.has_key?(pinned.admitted, @pinned)
    assert pinned.refused[@pinned] == {:authority_digest_invalid, @pinned}
  end

  test "typed refusal receipt is deterministic and authority inert" do
    {:ok, pins} = Authority.trust_roots()
    index = Authority.index(canonical())
    malformed = put_in(index, [:admitted, @pinned], "sha256:BAD")
    pinned = Authority.pin(malformed, pins)

    first = Authority.index_receipt(pinned)
    second = Authority.index_receipt(pinned)

    assert first == second
    assert first["schema"] == "semantic-jira/authority-index-receipt/v1"
    assert first["authority"] == "NONE"
    assert first["grants_do_authority"] == false
    assert String.starts_with?(first["receipt_digest"], "sha256:")

    assert %{
             "iri" => @pinned,
             "refusal" => ["authority_digest_invalid", @pinned]
           } in first["refused"]
  end
end
