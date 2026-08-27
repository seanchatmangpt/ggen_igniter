defmodule GgenIgniter.RenderPropertiesTest do
  @moduledoc """
  Real property-based tests (StreamData/ExUnitProperties, no mocks) for
  `GgenIgniter.Render.render/2`, exercising the actual `EEx.eval_string/2`
  wiring in `lib/ggen_igniter/render.ex` against many randomly generated
  templates/bindings per run -- Chicago-style, real EEx evaluation, no
  stubbed renderer.

  ## Real constraints these properties are precise about

  - `render/2`'s only real logic (besides the direct `EEx.eval_string/2`
    delegation) is `bindings = if is_map(bindings), do: Map.to_list(bindings),
    else: bindings` -- a map is converted to a keyword list before being
    handed to EEx, a keyword list is passed straight through. Property 3
    below tests exactly this branch with REAL multi-variable substitution
    (not just the trivial no-tags case property 1 covers): map-form and
    keyword-form bindings for the same logical data must render the exact
    same real substituted output.
  - The literal-passthrough property (property 1) generates template bodies
    filtered to exclude the substring `"<%"` -- EEx tags always open with
    that two-character sequence (`<%`, `<%=`, `<%-`, `<%%`, ...), so
    filtering it out is both necessary and sufficient to guarantee the
    generated string contains no EEx tag for `EEx.eval_string/2` to
    interpret; a lone `"%>"` with no preceding `"<%"` is inert plain text to
    EEx and does not need filtering.
  - Property 2 (single-variable substitution) binds a generated string value
    under the fixed atom key `:x` and renders the fixed template `"<%= x %>"`
    -- the *value* varies per run, never the template text itself, so no
    part of the generated string is ever parsed as Elixir source; EEx's
    `<%= expr %>` tag appends `to_string(expr)` to the output, and
    `to_string/1` on a binary is the identity function, so the expected
    output is the generated string itself, verbatim.
  - Property 3's binding keys are generated as `<lowercase letters>_g`
    (always letter-first, always containing an underscore, never pure
    alphabetic) specifically so a generated key can never collide with an
    Elixir reserved word (`do`, `end`, `fn`, `true`, `when`, ...) -- every
    reserved word is pure lowercase ASCII letters with no underscore, so
    this generator's output set and the reserved-word set are disjoint by
    construction, which is what makes it safe to splice each generated key
    directly into `"<%= \#{key} %>"` as a bare Elixir variable reference.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Render

  # ---------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------

  # Any printable string with no EEx tag-opening sequence -- see moduledoc
  # for why filtering "<%" alone is both necessary and sufficient.
  defp literal_template_gen do
    string(:printable, max_length: 200)
    |> filter(fn s -> not String.contains?(s, "<%") end)
  end

  defp value_string_gen, do: string(:printable, max_length: 100)

  # Arbitrary string keys, unconstrained -- fine for property 1, which never
  # evaluates any binding as an EEx variable reference (the template has no
  # tags at all).
  defp untyped_bindings_gen do
    map_of(
      string(:alphanumeric, min_length: 1, max_length: 10),
      value_string_gen(),
      max_length: 5
    )
  end

  # Real, always-valid, never-a-reserved-word Elixir variable names -- see
  # moduledoc for why the "_g" suffix guarantees disjointness from every
  # reserved word.
  defp var_key_gen do
    gen all(letters <- string(?a..?z, min_length: 1, max_length: 8)) do
      letters <> "_g"
    end
  end

  defp var_bindings_gen do
    map_of(var_key_gen(), value_string_gen(), min_length: 0, max_length: 5)
  end

  # ---------------------------------------------------------------------
  # Property 1: literal-only template -> output identical to input,
  # regardless of what bindings are in scope
  # ---------------------------------------------------------------------

  property "render/2 returns a template containing no EEx tags byte-identical to the input, " <>
             "for any bindings (map or keyword list)" do
    check all(
            template <- literal_template_gen(),
            bindings_map <- untyped_bindings_gen(),
            as_map? <- boolean(),
            max_runs: 100
          ) do
      atom_bindings = for {k, v} <- bindings_map, into: [], do: {String.to_atom(k), v}
      bindings = if as_map?, do: Map.new(atom_bindings), else: atom_bindings

      assert Render.render(template, bindings) == template
    end
  end

  # ---------------------------------------------------------------------
  # Property 2: single-variable substitution renders the exact bound value
  # ---------------------------------------------------------------------

  property "render/2 on the fixed template \"<%= x %>\" returns the bound string value " <>
             "verbatim, for any string value, whether bound via keyword list or map" do
    check all(value <- value_string_gen(), max_runs: 100) do
      assert Render.render("<%= x %>", x: value) == value
      assert Render.render("<%= x %>", %{x: value}) == value
    end
  end

  # ---------------------------------------------------------------------
  # Property 3: map bindings and the equivalent keyword-list bindings
  # substitute identically -- real multi-variable EEx evaluation, not just
  # the tag-free case
  # ---------------------------------------------------------------------

  property "render/2 substitutes N real bound variables identically whether bindings are " <>
             "given as a map or as the equivalent keyword list, and the result is the exact " <>
             "comma-joined concatenation of their values" do
    check all(bindings_map <- var_bindings_gen(), max_runs: 100) do
      pairs = Map.to_list(bindings_map)
      atom_bindings = Enum.map(pairs, fn {k, v} -> {String.to_atom(k), v} end)
      template = Enum.map_join(pairs, ",", fn {k, _v} -> "<%= #{k} %>" end)
      expected = Enum.map_join(pairs, ",", fn {_k, v} -> v end)

      via_keyword = Render.render(template, atom_bindings)
      via_map = Render.render(template, Map.new(atom_bindings))

      assert via_keyword == expected
      assert via_map == expected
      assert via_keyword == via_map
    end
  end
end
