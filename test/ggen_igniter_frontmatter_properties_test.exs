defmodule GgenIgniter.FrontmatterPropertiesTest do
  @moduledoc """
  Real property-based tests (StreamData/ExUnitProperties, no mocks) for
  `GgenIgniter.Frontmatter` and `GgenIgniter.Frontmatter.MatchRule`, exercising
  the actual structs and functions in `lib/ggen_igniter/frontmatter.ex` --
  `Frontmatter.from_map/1,2`, `Frontmatter.split_template/1`, and
  `MatchRule.from_map/1` -- against many randomly generated inputs per run,
  Chicago-style (real collaborators, state-based assertions on the real
  returned structs).

  ## Real constraints these properties are precise about

  - `Frontmatter.from_map/1` (`require_to: true` by default) only raises when
    `Map.get(map, "to")` is `nil`. A present-but-empty string `""` does NOT
    raise -- only `nil` does. The property below still generates a
    *non-empty* `"to"` string (per the task spec), which is a strict subset
    of the non-raising domain, not the full domain.
  - `"mode"` is not a field `Frontmatter.from_map/1` itself inspects at all --
    only `split_template/1`'s private `parse_header!/1` reads a `"mode"` key,
    and only from the map produced by parsing the YAML block, not from an
    arbitrary caller-supplied map passed straight to `from_map/1`. The
    round-trip property below still gates its assertions on
    `map["mode"] == "file"` per the task's literal spec, even though that
    gate is inert for `from_map/1` specifically -- documented here so the
    guard isn't mistaken for evidence that `from_map/1` branches on mode.
  - `split_template/1`'s fence matching is `String.split(rest, "\\n---\\n",
    parts: 2)` -- it locates only the FIRST occurrence of the literal
    `"\\n---\\n"` sequence in `rest` (the text after the opening `"---\\n"`
    line) and treats everything after that first occurrence as the body,
    unchanged, even if the body itself contains further `"\\n---\\n"`
    sequences (verified empirically: `String.split("to: 1\\n---\\nabc\\n---\\ndef",
    "\\n---\\n", parts: 2)` returns `["to: 1", "abc\\n---\\ndef"]`, not three
    parts). Since this test's synthesized YAML block is a single, fixed,
    newline-free line, the literal fence we insert is guaranteed to be the
    first occurrence in `rest` regardless of body content. Per the task's
    instruction to be precise and either filter or escape, the property
    below still filters bodies containing `"\\n---\\n"` -- a strictly
    narrower domain than what was empirically shown to be safe, kept
    narrower deliberately to match the literal task spec and avoid relying
    on an edge case (multi-occurrence bodies) that isn't this property's
    subject.
  - `MatchRule.from_map/1` converts `matcher`/`scope`/`occurrence` strings via
    `String.to_existing_atom/1` -- it raises `ArgumentError` for any string
    that isn't already a loaded atom. Verified empirically that
    `:contains`/`:exact`/`:regex`, `:auto`/`:line`/`:file`, and
    `:first`/`:last`/`:unique`/`:nth` all already exist once
    `GgenIgniter.Frontmatter.MatchRule` is compiled (they appear as literal
    atoms in its `@type` attributes and its `defstruct` defaults), so the
    property below only ever passes strings from those three literal sets --
    it does not claim `from_map/1` accepts arbitrary matcher/scope/occurrence
    strings.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Frontmatter
  alias GgenIgniter.Frontmatter.MatchRule

  # ---------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------

  defp non_empty_string_gen do
    string(:printable, min_length: 1, max_length: 40)
  end

  defp sparql_map_gen do
    map_of(
      string(:alphanumeric, min_length: 1, max_length: 12),
      string(:printable, max_length: 20),
      max_length: 5
    )
  end

  defp frontmatter_map_gen do
    gen all(
          to <- non_empty_string_gen(),
          sparql <- sparql_map_gen(),
          unless_exists <- boolean(),
          force <- boolean(),
          backup <- boolean(),
          skip_empty <- boolean(),
          inject <- boolean(),
          mode <- member_of(["file", "eval"])
        ) do
      %{
        "to" => to,
        "sparql" => sparql,
        "unless_exists" => unless_exists,
        "force" => force,
        "backup" => backup,
        "skip_empty" => skip_empty,
        "inject" => inject,
        "mode" => mode
      }
    end
  end

  # A single, fixed, newline-free YAML line -- see moduledoc for why this
  # guarantees the inserted "\n---\n" fence is the first occurrence in `rest`
  # regardless of what the generated body contains.
  @yaml_block ~s(to: "template.txt")

  defp body_gen do
    string(:printable, max_length: 200)
    |> filter(fn body -> not String.contains?(body, "\n---\n") end)
  end

  defp match_kind_gen, do: member_of(["contains", "exact", "regex"])
  defp match_scope_gen, do: member_of(["auto", "line", "file"])
  defp match_occurrence_gen, do: member_of(["first", "last", "unique", "nth"])

  defp match_rule_map_gen do
    gen all(
          pattern <- non_empty_string_gen(),
          matcher <- match_kind_gen(),
          scope <- match_scope_gen(),
          occurrence <- match_occurrence_gen(),
          index <- integer(0..1000),
          case_sensitive <- boolean(),
          trim <- boolean()
        ) do
      %{
        "pattern" => pattern,
        "matcher" => matcher,
        "scope" => scope,
        "occurrence" => occurrence,
        "index" => index,
        "case_sensitive" => case_sensitive,
        "trim" => trim
      }
    end
  end

  # ---------------------------------------------------------------------
  # Frontmatter.from_map/1 -- no-raise + exact round-trip
  # ---------------------------------------------------------------------

  property "from_map/1 never raises for a non-empty \"to\" string when mode is \"file\", and every supplied field round-trips exactly with untouched fields left at their documented defaults" do
    check all(map <- frontmatter_map_gen()) do
      if map["mode"] == "file" do
        fm = Frontmatter.from_map(map)

        assert %Frontmatter{} = fm

        # Round-trip: every field the map actually supplied comes back
        # byte-for-byte / value-for-value identical -- no corruption.
        assert fm.to == map["to"]
        assert fm.sparql == map["sparql"]
        assert fm.unless_exists == map["unless_exists"]
        assert fm.force == map["force"]
        assert fm.backup == map["backup"]
        assert fm.skip_empty == map["skip_empty"]
        assert fm.inject == map["inject"]

        # No-corruption, the other half: fields the map never mentioned stay
        # at exactly their documented defaults (defstruct/moduledoc above) --
        # from_map/1 doesn't leak values across fields or invent defaults.
        assert fm.for_each == nil
        assert fm.construct == nil
        assert fm.before == nil
        assert fm.after == nil
        assert fm.at_line == nil
        assert fm.skip_if == nil
        assert fm.unattended_write_eligible == false
        assert fm.when == nil
        assert fm.from == nil
        assert fm.sh_before == nil
        assert fm.sh_after == nil
        assert fm.shape == []
        assert fm.determinism == nil
        assert fm.freeze_policy == nil
        assert fm.freeze_slots_dir == nil
        assert fm.rdf == []
        assert fm.rdf_inline == []
        assert fm.prefixes == %{}
        assert fm.base == nil
      end
    end
  end

  # ---------------------------------------------------------------------
  # Frontmatter.split_template/1 -- body identity
  # ---------------------------------------------------------------------

  property "split_template/1 returns a body byte-identical to the generated body, for any body not containing the literal \"\\n---\\n\" fence sequence" do
    check all(body <- body_gen()) do
      template = "---\n" <> @yaml_block <> "\n---\n" <> body

      {frontmatter, mode, returned_body} = Frontmatter.split_template(template)

      assert %Frontmatter{to: "template.txt"} = frontmatter
      assert mode == :file
      assert returned_body == body
    end
  end

  # ---------------------------------------------------------------------
  # MatchRule.from_map/1 -- exact round-trip
  # ---------------------------------------------------------------------

  property "MatchRule.from_map/1 round-trips a non-empty pattern and valid matcher/scope/occurrence atoms exactly" do
    check all(map <- match_rule_map_gen()) do
      rule = MatchRule.from_map(map)

      assert %MatchRule{} = rule
      assert rule.pattern == map["pattern"]
      assert rule.matcher == String.to_existing_atom(map["matcher"])
      assert rule.scope == String.to_existing_atom(map["scope"])
      assert rule.occurrence == String.to_existing_atom(map["occurrence"])
      assert rule.index == map["index"]
      assert rule.case_sensitive == map["case_sensitive"]
      assert rule.trim == map["trim"]
    end
  end
end
