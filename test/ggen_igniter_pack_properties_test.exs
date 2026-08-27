defmodule GgenIgniter.PackPropertiesTest do
  @moduledoc """
  Real property-based tests (StreamData/ExUnitProperties, no mocks) for
  `GgenIgniter.Pack`'s pure file-discovery helpers, exercised against REAL
  temp directories and REAL files on disk -- Chicago-style, no faking of the
  filesystem, per this project's testing convention
  (`~/.claude/rules/testing-chicago-style.md`), mirroring the existing
  `test/ggen_igniter_actuate_properties_test.exs` and
  `test/ggen_igniter_frontmatter_properties_test.exs` conventions.

  ## What's under test, and why via `discover_queries/1` rather than directly

  `GgenIgniter.Pack`'s digit-prefix-stripping logic lives in a *private*
  `defp query_name(path)` (`lib/ggen_igniter/pack.ex`) -- there is no way to
  call a private function from an external test module (Elixir does not
  export `defp` functions under any calling convention, `apply/3` included),
  so this file exercises that exact logic through its only real public
  entry point, `discover_queries/1`, which maps each discovered `*.rq` path
  through `query_name/1` and returns `{name, path}` pairs. Every property
  below is still a property of the real stripping logic itself (one file
  per generator run keeps the mapping unambiguous: exactly one `{name,
  path}` pair comes back, and `name` is exactly what `query_name/1` returned
  for that file).

  ## Real constraints these properties are precise about

  - `query_name/1` is `Path.basename(path, ".rq") |> String.replace(~r/^\\d+_/, "")`.
    The regex is anchored at the START of the string only (`^`), so it can
    match at most once regardless of `String.replace/3`'s default
    (replace-all) behavior -- there is no second anchor-start position after
    the first character has been consumed. This means a stem that itself
    begins with digits *after* the first stripped prefix is never further
    stripped -- verified empirically: `query_name.("010_2fast.rq")` strips
    only the leading `"010_"`, returning `"2fast"` unchanged (not `"fast"`).
  - The "no digit prefix -> unchanged" property below generates stems whose
    first character is a letter (`?a..?z`), which is sufficient (not just
    convenient) to guarantee non-match against `~r/^\\d+_/`: that pattern
    requires the very first character to be an ASCII digit, so any
    letter-first stem can never match it, regardless of what characters
    follow.
  - `discover_template/1`'s three-way outcome (`{:error, :none}` /
    `{:ok, path}` / `{:error, {:ambiguous, paths}}`) is driven purely by
    `length(paths)` after globbing `templates/*.eex` and `templates/*.tmpl`
    and sorting lexically -- verified empirically that the `:ambiguous`
    paths list is exactly the sorted full set of generated template files
    (both extensions pooled together, not per-extension).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Pack

  # ---------------------------------------------------------------------
  # Fixtures: a fresh, never-yet-touched pack dir per generator run
  # ---------------------------------------------------------------------

  setup do
    tmp_root =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pack_properties_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_root)
    on_exit(fn -> File.rm_rf!(tmp_root) end)
    {:ok, tmp_root: tmp_root}
  end

  defp fresh_pack_dir(tmp_root) do
    n = System.unique_integer([:positive])
    dir = Path.join(tmp_root, "pack_#{n}")
    File.mkdir_p!(Path.join(dir, "gates"))
    File.mkdir_p!(Path.join(dir, "templates"))
    dir
  end

  # Alphanumeric-only, letter-first stems -- safe as single filesystem path
  # segments on every platform and, per the moduledoc above, guaranteed to
  # never match the leading `~r/^\d+_/` digit-prefix pattern.
  defp stem_gen do
    gen all(
          first <- StreamData.string(?a..?z, length: 1),
          rest <- StreamData.string(:alphanumeric, min_length: 0, max_length: 15)
        ) do
      first <> rest
    end
  end

  defp digits_gen, do: StreamData.string(?0..?9, min_length: 1, max_length: 4)

  # ---------------------------------------------------------------------
  # Property 1: digit-prefixed filename -> prefix always stripped
  # ---------------------------------------------------------------------

  property "discover_queries/1 strips a leading digit-underscore prefix: the returned name " <>
             "never starts with a digit, for any real \\d+_ -prefixed *.rq file",
           %{tmp_root: tmp_root} do
    check all(digits <- digits_gen(), stem <- stem_gen(), max_runs: 50) do
      pack_dir = fresh_pack_dir(tmp_root)
      filename = "#{digits}_#{stem}.rq"
      path = Path.join([pack_dir, "gates", filename])
      File.write!(path, "SELECT * WHERE { ?s ?p ?o }")

      assert [{name, ^path}] = Pack.discover_queries(pack_dir)

      refute Regex.match?(~r/^\d+_/, name)
      assert name == stem
    end
  end

  # ---------------------------------------------------------------------
  # Property 2: non-digit-prefixed filename -> name returned unchanged
  # ---------------------------------------------------------------------

  property "discover_queries/1 returns the stem UNCHANGED for any *.rq file whose name does " <>
             "not start with a digit prefix",
           %{tmp_root: tmp_root} do
    check all(stem <- stem_gen(), max_runs: 50) do
      pack_dir = fresh_pack_dir(tmp_root)
      path = Path.join([pack_dir, "gates", "#{stem}.rq"])
      File.write!(path, "SELECT * WHERE { ?s ?p ?o }")

      assert [{name, ^path}] = Pack.discover_queries(pack_dir)
      assert name == stem
    end
  end

  # ---------------------------------------------------------------------
  # Property 3: discover_template/1's none/single/ambiguous trichotomy
  # ---------------------------------------------------------------------

  defp distinct_stems_gen(min_length, max_length) do
    gen all(
          stems <-
            StreamData.uniq_list_of(stem_gen(), min_length: min_length, max_length: max_length)
        ) do
      stems
    end
  end

  property "discover_template/1's outcome is exactly determined by how many *.eex/*.tmpl " <>
             "files exist: :none for zero, {:ok, path} naming the sole file for exactly one, " <>
             "{:error, {:ambiguous, paths}} listing every one (sorted) for more than one",
           %{tmp_root: tmp_root} do
    check all(
            stems <- distinct_stems_gen(0, 5),
            extensions <-
              StreamData.list_of(StreamData.member_of(["eex", "tmpl"]), length: length(stems)),
            max_runs: 50
          ) do
      pack_dir = fresh_pack_dir(tmp_root)

      paths =
        stems
        |> Enum.zip(extensions)
        |> Enum.map(fn {stem, ext} ->
          path = Path.join([pack_dir, "templates", "#{stem}.#{ext}"])
          File.write!(path, "<%= 1 %>")
          path
        end)
        |> Enum.sort()

      result = Pack.discover_template(pack_dir)

      case paths do
        [] ->
          assert result == {:error, :none}

        [single] ->
          assert result == {:ok, single}

        many ->
          assert {:error, {:ambiguous, ambiguous_paths}} = result
          assert Enum.sort(ambiguous_paths) == many
      end
    end
  end
end
