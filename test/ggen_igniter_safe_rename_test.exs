defmodule GgenIgniterSafeRenameTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with
  small inline synthetic fixture source, driving the real
  `GgenIgniter.Refactors.SafeRename.rename_function/4` -- which itself
  delegates to the real `Igniter.Refactors.Rename.rename_function/4` for the
  safe common case and only adds real, targeted pre/post zipper passes for
  the two upstream defects `test/ggen_igniter_upstream_rename_blocker_test.exs`
  documents. No mocking of Igniter internals anywhere -- every assertion is
  on the real resulting source text after real AST rewrites.

  Proves `SafeRename` routes around both upstream `deps/igniter` defects
  WITHOUT patching the vendored dependency (which `mix deps.get` would
  silently revert) -- the exact opposite outcome from the two
  `@tag :known_upstream_bug` tests in the sibling blocker-repro file.
  """

  use ExUnit.Case, async: true

  describe "rename_function/4 (defect 2 workaround: parenless zero-arity def)" do
    test "renames a parenless zero-arity def instead of crashing with length(nil)" do
      source = """
      defmodule MyApp.Sample do
        def foo do
          :ok
        end
      end
      """

      igniter = Igniter.Test.test_project(files: %{"lib/my_app/sample.ex" => source})

      igniter =
        GgenIgniter.Refactors.SafeRename.rename_function(
          igniter,
          {MyApp.Sample, :foo},
          {MyApp.Sample, :bar},
          arity: 0
        )

      result_source =
        igniter.rewrite
        |> Rewrite.source!("lib/my_app/sample.ex")
        |> Rewrite.Source.get(:content)

      # Real, observed fix: no crash, and the def is actually renamed (with
      # explicit parens now -- a semantics-null normalization, not a defect).
      assert result_source =~ "def bar"
      refute result_source =~ "def foo"
    end
  end

  describe "rename_function/4 (defect 1 workaround: guarded def)" do
    test "renames a guarded def's head, not just its call sites" do
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
        GgenIgniter.Refactors.SafeRename.rename_function(
          igniter,
          {MyApp.Guarded, :foo},
          {MyApp.Guarded, :bar},
          arity: 1
        )

      result_source =
        igniter.rewrite
        |> Rewrite.source!("lib/my_app/guarded.ex")
        |> Rewrite.Source.get(:content)

      # Real, observed fix: call site renamed (as upstream always did)...
      assert result_source =~ "bar(x)"
      # ...AND the guarded definition itself is now ALSO renamed, unlike the
      # documented upstream defect.
      assert result_source =~ "def bar(x) when x > 0 do"
      refute result_source =~ "def foo(x) when x > 0 do"
    end

    test "renames multiple guard clauses for the same function/arity" do
      source = """
      defmodule MyApp.MultiGuard do
        def foo(x) when x > 0 do
          :positive
        end

        def foo(x) when x < 0 do
          :negative
        end
      end
      """

      igniter = Igniter.Test.test_project(files: %{"lib/my_app/multi_guard.ex" => source})

      igniter =
        GgenIgniter.Refactors.SafeRename.rename_function(
          igniter,
          {MyApp.MultiGuard, :foo},
          {MyApp.MultiGuard, :bar},
          arity: 1
        )

      result_source =
        igniter.rewrite
        |> Rewrite.source!("lib/my_app/multi_guard.ex")
        |> Rewrite.Source.get(:content)

      assert result_source =~ "def bar(x) when x > 0 do"
      assert result_source =~ "def bar(x) when x < 0 do"
      refute result_source =~ "def foo(x)"
    end
  end
end
