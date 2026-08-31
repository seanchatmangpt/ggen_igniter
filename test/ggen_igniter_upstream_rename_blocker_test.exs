defmodule GgenIgniterUpstreamRenameBlockerTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with
  small inline synthetic fixture source, driving the real
  `Igniter.Refactors.Rename.rename_function/4` codemod (no mocking of
  Igniter internals — the bug is *in* the real codemod, so the only honest
  reproduction is to actually call it).

  Documents two real, currently-failing, upstream-blocked defects found by
  scout review of `deps/igniter/lib/igniter/refactors/rename.ex`. Both are
  disclosed blockers on "upgrade codemods for ontology evolution" — NOT
  shipped features of this repo. Neither defect is fixable here: the buggy
  code lives in the vendored `igniter` dependency, not in `ggen_igniter`.

  ## Defect 1 — guard-clause blind spot (silent skip, no crash, no warning)

  `deps/igniter/lib/igniter/refactors/rename.ex:325-326` (inside
  `update_refs/7`, called from `rename_function/4`) and the identical
  pattern at `rename.ex:168-169` (inside `remap_function_definition/5`'s
  `subsume_module_attrs` match) both match a function definition to rename
  via:

      {%{node: {:def, _, [{^old_function, _, args}, _body]}}, _} ->
        arity == :any || length(args) == arity

  A guarded function head's real AST is `{:when, _, [{:foo, meta, [x]},
  guard_expr]}`, not `{:foo, meta, [x]}` directly — so `{^old_function, _,
  args}` structurally cannot match a guarded def's head. The def falls
  through to the `_other -> false` branch and is silently left un-renamed,
  with no warning emitted, while call sites of the same function ARE
  renamed (the call-site match, `{^old_function, meta, args}` at
  rename.ex:692/849, is not guard-shaped and does match plain call AST) —
  producing a broken program: calls point at a name whose only guarded
  definition clause was never renamed.

  ## Defect 2 — `length(nil)` crash on parenless zero-arity defs

  The same two match sites call `length(args) == arity` (or
  `length(args) in List.wrap(arity)` at line 169) directly on the def's
  argument list. For a parenless zero-arity definition (`def foo do ... end`,
  as opposed to `def foo() do ... end`), Elixir's AST represents the
  arguments as `args = nil`, not `args = []` — `length(nil)` raises
  `ArgumentError` (BEAM `length/1` requires a proper list), so calling
  `Igniter.Refactors.Rename.rename_function/4` against any module
  containing a parenless zero-arity def matching `old_function`'s name
  crashes the whole codemod rather than skipping or renaming it.
  """

  use ExUnit.Case, async: true

  @tag :known_upstream_bug
  test "defect 2: rename_function/4 crashes with length(nil) on a parenless zero-arity def" do
    source = """
    defmodule MyApp.Sample do
      def foo do
        :ok
      end
    end
    """

    igniter = Igniter.Test.test_project(files: %{"lib/my_app/sample.ex" => source})

    # Real crash: length(nil) inside Igniter.Refactors.Rename's own match
    # clauses (rename.ex:168-169 / rename.ex:325-326), not something this
    # repo raises deliberately. Whichever concrete exception class the BEAM
    # surfaces for `length(nil)` (ArgumentError today), the call must not
    # return normally.
    assert_raise ArgumentError, fn ->
      Igniter.Refactors.Rename.rename_function(
        igniter,
        {MyApp.Sample, :foo},
        {MyApp.Sample, :bar},
        arity: 0
      )
    end
  end

  @tag :known_upstream_bug
  test "defect 1: rename_function/4 silently skips a guarded def while renaming its call sites" do
    source = """
    defmodule MyApp.Guarded do
      def foo(x) when x > 0 do
        x
      end

      def caller(x) do
        foo(x)
      end
    end
    """

    igniter = Igniter.Test.test_project(files: %{"lib/my_app/guarded.ex" => source})

    igniter =
      Igniter.Refactors.Rename.rename_function(
        igniter,
        {MyApp.Guarded, :foo},
        {MyApp.Guarded, :bar},
        arity: 1
      )

    result_source =
      igniter.rewrite
      |> Rewrite.source!("lib/my_app/guarded.ex")
      |> Rewrite.Source.get(:content)

    # Real, observed bug: the call site IS renamed (call-site AST is not
    # guard-shaped, so it matches the codemod's rename pattern)...
    assert result_source =~ "bar(x)"

    # ...but the guarded definition itself is left untouched, because
    # `{^old_function, _, args}` cannot match the `{:when, _, [...]}`
    # wrapper around a guarded def's head. This produces a broken program:
    # `bar/1` is called but never defined, while `foo/1` (still guarded)
    # remains defined and now unused/unreachable under its old name.
    assert result_source =~ "def foo(x) when x > 0 do"
    refute result_source =~ "def bar(x) when x > 0 do"
  end
end
