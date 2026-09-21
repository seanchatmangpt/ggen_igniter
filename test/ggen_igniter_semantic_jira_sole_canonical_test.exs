defmodule GgenIgniter.SemanticJiraSoleCanonicalTest do
  @moduledoc """
  ONE-CANONICAL tripwire (wave-9 sole-source fold; absorbs the PR #19 / #23
  disposition).

  `priv/ggen/semantic-jira-pack/` is the ONLY Semantic Jira work-order
  ontology and manufacturer surface permitted in this repository. PR #19
  (head `0d87dfe`) introduced a second surface — `priv/ggen/
  gall-semantic-work-pack/` with its own `gall:` ontology, checkpoint gate,
  descriptor/ticket templates — and PR #23 (head `d92a230`) extended it.
  Both are SUPERSEDED by PR #20: their descriptor law is carried by
  `GgenIgniter.Crown.descriptor/3` and their shape courts are absorbed in
  `test/ggen_igniter_crown_descriptor_court_test.exs`.

  This file makes that disposition a repo-side enforcement anchor (延):
  the fold survives the loss of the session that performed it because any
  reappearance of a second work-order manufacturer surface fails these
  tests.
  """

  use ExUnit.Case, async: true

  @gall_ns "https://semantic-a2a.dev/gall#"
  @superseded_pack "priv/ggen/gall-semantic-work-pack"
  @canonical_pack "priv/ggen/semantic-jira-pack"
  @source_roots ~w(priv lib test config)

  defp source_files do
    @source_roots
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,exs,ttl,rq,eex,toml,md,yml}")))
  end

  test "no second semantic work-order pack directory exists (PR #19/#23 superseded by PR #20)" do
    refute File.dir?(@superseded_pack),
           "#{@superseded_pack} reappeared — it was superseded by #{@canonical_pack} " <>
             "(PR #20); fold any new fact into the canonical pack instead"
  end

  test "no second work-order ontology namespace is referenced anywhere in repo sources" do
    # This tripwire file itself is the one lawful exception: it must name the
    # superseded namespace to guard it (the enforcement anchor records what
    # it forbids).
    hits =
      @gall_ns
      |> then(
        &Enum.filter(source_files(), fn path ->
          path != "test/ggen_igniter_semantic_jira_sole_canonical_test.exs" and
            String.contains?(File.read!(path), &1)
        end)
      )

    assert hits == [],
           "the superseded gall work-order ontology namespace reappeared in: #{inspect(hits)}"
  end

  test "exactly one pack ontology declares work-order subjects: the canonical pack" do
    declaring =
      "priv/ggen/*/ontology.ttl"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        Regex.match?(~r/a\s+(sj:WorkOrder|oslc_cm:ChangeRequest)\b/, File.read!(path))
      end)

    assert declaring == [Path.join(@canonical_pack, "ontology.ttl")],
           "more than one work-order manufacturer surface: #{inspect(declaring)}"
  end

  test "the canonical pack is present and self-declared in pack.toml" do
    pack_toml = Path.join(@canonical_pack, "pack.toml")
    assert File.regular?(pack_toml)
    assert File.read!(pack_toml) =~ ~s(name = "semantic-jira-pack")

    assert File.read!(pack_toml) =~ "ONE-CANONICAL",
           "the pack.toml sole-canonical assertion is missing"
  end
end
