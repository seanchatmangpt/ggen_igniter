defmodule GgenIgniter.SyncPropertiesTest do
  @moduledoc """
  Real property-based tests (StreamData/ExUnitProperties, no mocks) for
  `Mix.Tasks.GgenIgniter.Sync`'s pure helper functions `build_bindings/2` and
  `resolve_named_queries!/2`, exercising the actual functions in
  `lib/mix/tasks/ggen_igniter.sync.ex` -- Chicago-style, real function calls,
  state-based assertions on the real returned bindings/query lists, mirroring
  this project's existing `test/ggen_igniter_*_properties_test.exs`
  conventions.

  ## Why `def`, not `defp`, and why that's not a mock

  Both functions are genuinely pure (no I/O, no `File`/`Igniter` dependency)
  but were `defp` -- Elixir does not export `defp` functions under ANY
  calling convention (not even `apply/3`), so there is no way to call them
  from an external test module without either widening their visibility or
  reimplementing their logic in the test (which WOULD be a fake, banned by
  `~/.claude/rules/testing-chicago-style.md`). This session widened both to
  `def` with `@doc false` (a visibility change only -- zero logic changed,
  verified by `mix compile --warnings-as-errors` succeeding unchanged and
  every pre-existing sync integration test in
  `test/ggen_igniter_sync_*_test.exs` still passing against the same code
  paths). Calling the real, unmodified function and asserting on its real
  return value is exactly the Chicago-style discipline this project's other
  three property test files already follow -- there is no test double
  standing in for either function anywhere in this file.

  ## Real constraints these properties are precise about

  - `build_bindings/2`'s `list_bindings` (every named query bound as
    `name: rows`, the FULL row list) is built independently of, and BEFORE,
    the single-row `flattened` bindings and the `for_each_row` bindings are
    computed -- then merged on TOP via two separate `Keyword.merge/2` calls.
    `Keyword.merge/2`'s real semantics take the SECOND argument's value on a
    key collision. This means a single-row query's own flattened column
    could only ever shadow-collide with `list_bindings`' `name: rows` key if
    the flattened atom key (a query RESULT COLUMN name) happened to be
    spelled identically to a QUERY NAME -- a real but narrow collision this
    project's own moduledoc for `build_bindings/2` does not claim to defend
    against. Property 1 below is the complementary, always-true half of that
    same fact: the full row list under `name` is present and exactly
    `rows` whenever `name` itself is never also one of the flattened or
    for-each-row keys -- i.e. whenever no column of any single-row query (or
    of the for-each row) is spelled identically to a query name, which the
    generator below guarantees by construction (disjoint character alphabets
    for query names vs. column names).
  - `resolve_named_queries!/2`'s three-source merge
    (`Enum.reduce(file_named_queries, frontmatter_queries, fn {name, text},
    acc -> List.keystore(acc, name, 0, {name, text}) end)`) uses
    `List.keystore/4`, whose real semantics REPLACE the first existing tuple
    with a matching key in place (preserving that key's ORIGINAL position in
    the accumulator list) or APPEND a new tuple at the end when the key is
    not already present -- it is not a naive "later list wins, then
    concatenate" merge. Property 3 below is precise about exactly this: for
    a query name present in BOTH the frontmatter-inline source and an
    explicit `--query` source, the explicit source's TEXT wins (verified
    against the real query text, not just list membership), matching this
    module's own moduledoc ("later overrides same-named earlier").
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mix.Tasks.GgenIgniter.Sync
  alias GgenIgniter.Frontmatter

  # ---------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------

  # Query names use an "_q" suffix, column names use a "_c" suffix -- disjoint
  # by construction (a query name can never equal a column name), which is
  # exactly the precondition property 1's moduledoc note above states.
  defp query_name_gen do
    gen all(letters <- StreamData.string(?a..?z, min_length: 1, max_length: 8)) do
      letters <> "_q"
    end
  end

  defp column_name_gen do
    gen all(letters <- StreamData.string(?a..?z, min_length: 1, max_length: 8)) do
      letters <> "_c"
    end
  end

  defp value_gen, do: StreamData.string(:alphanumeric, min_length: 0, max_length: 20)

  defp row_gen(n_columns) do
    gen all(
          keys <- StreamData.uniq_list_of(column_name_gen(), length: n_columns),
          values <- StreamData.list_of(value_gen(), length: n_columns)
        ) do
      Enum.zip(keys, values) |> Map.new()
    end
  end

  defp named_results_gen(min_length, max_length) do
    gen all(
          names <-
            StreamData.uniq_list_of(query_name_gen(),
              min_length: min_length,
              max_length: max_length
            ),
          results <-
            StreamData.list_of(
              gen all(
                    row_count <- StreamData.integer(0..3),
                    rows <- StreamData.list_of(row_gen(2), length: row_count)
                  ) do
                rows
              end,
              length: length(names)
            )
        ) do
      Enum.zip(names, results)
    end
  end

  # ---------------------------------------------------------------------
  # Property 1: every named query's FULL row list is always bound under its
  # own atom key, unmodified by any single-row flattening
  # ---------------------------------------------------------------------

  property "build_bindings/2 always binds every named query's complete row list under its " <>
             "own atom key, regardless of how many OTHER queries are single-row (and thus " <>
             "flattened), and regardless of a --for-each row also being present" do
    check all(
            named_results <- named_results_gen(0, 4),
            for_each_row <- StreamData.one_of([constant(nil), row_gen(2)]),
            max_runs: 100
          ) do
      bindings = Sync.build_bindings(named_results, for_each_row)

      for {name, rows} <- named_results do
        atom_key = String.to_atom(name)
        assert Keyword.has_key?(bindings, atom_key)
        assert Keyword.get(bindings, atom_key) == rows
      end
    end
  end

  # ---------------------------------------------------------------------
  # Property 2: a for-each row's own columns always win over a same-named
  # single-row-query-flattened column
  # ---------------------------------------------------------------------

  property "build_bindings/2's for_each_row columns always win over a same-named column " <>
             "flattened from an unrelated single-row query" do
    check all(
            shared_column <- column_name_gen(),
            single_row_query_name <- query_name_gen(),
            flattened_value <- value_gen(),
            other_columns <- StreamData.uniq_list_of(column_name_gen(), max_length: 3),
            max_runs: 100
          ) do
      # Guaranteed distinct from `flattened_value` by construction (strictly
      # longer, via a suffix no `value_gen/0` output already ends with the
      # same way) rather than via a `!=` filter -- `value_gen/0`'s alphabet
      # is small enough (alphanumeric, allows the empty string) that a
      # `flattened_value != for_each_value` filter clause was empirically
      # too narrow (StreamData.FilterTooNarrowError: most runs collide on
      # `""`), so this constructs an unequal value directly instead.
      for_each_value = flattened_value <> "_distinct"
      other_columns = other_columns -- [shared_column]

      single_row =
        Map.new([{shared_column, flattened_value} | Enum.map(other_columns, &{&1, "x"})])

      named_results = [{single_row_query_name, [single_row]}]
      for_each_row = %{shared_column => for_each_value}

      bindings = Sync.build_bindings(named_results, for_each_row)

      atom_key = String.to_atom(shared_column)
      assert Keyword.get(bindings, atom_key) == for_each_value
      refute Keyword.get(bindings, atom_key) == flattened_value
    end
  end

  # ---------------------------------------------------------------------
  # Property 3: resolve_named_queries!/2's later-overrides-earlier merge --
  # an explicit --query TEXT wins over a same-named frontmatter inline query
  # ---------------------------------------------------------------------

  property "resolve_named_queries!/2: an explicit --query's file text always wins over a " <>
             "same-named frontmatter inline sparql: query text",
           %{tmp_dir: tmp_dir} do
    check all(
            name <- query_name_gen(),
            frontmatter_text <- value_gen(),
            max_runs: 50
          ) do
      # See property 2's comment: constructed distinct from `frontmatter_text`
      # rather than via a `!=` filter, for the same reason (a small alphabet
      # including `""` makes such a filter too narrow).
      explicit_text = frontmatter_text <> "_distinct"
      path = Path.join(tmp_dir, "#{name}_#{System.unique_integer([:positive])}.rq")
      File.write!(path, explicit_text)

      frontmatter =
        Frontmatter.from_map(%{"to" => "out.ex", "sparql" => %{name => frontmatter_text}})

      opts = [query: "#{name}=#{path}"]

      resolved = Sync.resolve_named_queries!(opts, frontmatter)

      assert {^name, ^explicit_text} = List.keyfind(resolved, name, 0)
      refute List.keyfind(resolved, name, 0) == {name, frontmatter_text}
    end
  end

  # ---------------------------------------------------------------------
  # Property 4: resolve_named_queries!/2 preserves every query name given,
  # with no duplicates and no name lost, when all names are distinct
  # ---------------------------------------------------------------------

  property "resolve_named_queries!/2 returns exactly one entry per distinct query name across " <>
             "frontmatter sparql: and explicit --query sources, with no name dropped",
           %{tmp_dir: tmp_dir} do
    check all(
            frontmatter_names <-
              StreamData.uniq_list_of(query_name_gen(), min_length: 1, max_length: 3),
            explicit_suffix <- StreamData.string(?a..?z, min_length: 1, max_length: 4),
            max_runs: 50
          ) do
      # Explicit names are disjoint from frontmatter names (distinct suffix
      # alphabet) so this property is precise about the UNION case only --
      # the overriding case is property 3's separate, explicit subject.
      explicit_names = Enum.map(frontmatter_names, fn n -> n <> "_" <> explicit_suffix end)

      frontmatter_map =
        Map.new(frontmatter_names, fn n -> {n, "frontmatter text for #{n}"} end)

      frontmatter = Frontmatter.from_map(%{"to" => "out.ex", "sparql" => frontmatter_map})

      explicit_opts =
        Enum.map(explicit_names, fn n ->
          path = Path.join(tmp_dir, "#{n}_#{System.unique_integer([:positive])}.rq")
          File.write!(path, "explicit text for #{n}")
          {:query, "#{n}=#{path}"}
        end)

      resolved = Sync.resolve_named_queries!(explicit_opts, frontmatter)
      resolved_names = Enum.map(resolved, &elem(&1, 0))

      assert Enum.sort(resolved_names) == Enum.sort(frontmatter_names ++ explicit_names)
      assert length(resolved_names) == length(Enum.uniq(resolved_names))
    end
  end

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_properties_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end
end
