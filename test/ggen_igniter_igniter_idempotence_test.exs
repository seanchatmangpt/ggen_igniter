defmodule GgenIgniterIgniterIdempotenceTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project/1` sources, the real
  `Mix.Tasks.GgenIgniter.Install` and `Mix.Tasks.GgenIgniter.Rename` tasks and the
  real `GgenIgniter.Refactors.SafeRename` codemod, driven in-memory through
  `GgenIgniter.Test.IgniterIdempotence` (apply -> simulated write -> apply again ->
  `assert_unchanged`). Assertions are on real resulting source text/issues.

  A mutation falsifier at the bottom proves the harness itself FAILS on a
  deliberately non-idempotent codemod (a real function appending a comment each run),
  so a green suite here is not a vacuous pass.

  `GgenIgniter.DoctorFixes` is intentionally absent: every fix there takes a
  `project_dir` and reads/writes files on disk (`run_rule/3`), not an igniter or
  zipper, so it cannot be driven in-memory by this harness.
  """
  use ExUnit.Case, async: true

  import GgenIgniter.Test.IgniterIdempotence

  @mix_exs """
  defmodule Sample.MixProject do
    use Mix.Project

    def project do
      [app: :sample, version: "0.1.0", deps: deps()]
    end

    def application do
      [mod: {Sample.Application, []}]
    end

    defp deps do
      []
    end
  end
  """

  @app_ex """
  defmodule Sample.Application do
    use Application

    def start(_type, _args) do
      children = []
      Supervisor.start_link(children, strategy: :one_for_one)
    end
  end
  """

  @inline_app_ex """
  defmodule Sample.Application do
    use Application

    def start(_type, _args) do
      Supervisor.start_link([], strategy: :one_for_one)
    end
  end
  """

  @inline_deps_mix_exs """
  defmodule Sample.MixProject do
    use Mix.Project

    def project do
      [app: :sample, version: "0.1.0", deps: []]
    end
  end
  """

  defp src(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  describe "install task" do
    test "thin default: formatter import_deps codemod is idempotent" do
      mix_exs = String.replace(@mix_exs, "defp deps do\n    []", "defp deps do\n    [{:ggen_igniter, \"~> 26.9\"}]")

      igniter =
        assert_idempotent("ggen_igniter.install", ["--yes"],
          files: %{
            "mix.exs" => mix_exs,
            ".formatter.exs" => "[\n  inputs: [\"{mix,.formatter}.exs\"]\n]\n"
          }
        )

      assert src(igniter, ".formatter.exs") =~ ":ggen_igniter"
      refute src(igniter, "mix.exs") =~ ":ash"
    end

    test "Deps + Config + Application codemods are idempotent (children binding present)" do
      igniter =
        assert_idempotent(
          "ggen_igniter.install",
          ["--with-ash-domain", "--domain", "Sample.Ash.Domain", "--yes"],
          files: %{"mix.exs" => @mix_exs, "lib/sample/application.ex" => @app_ex}
        )

      assert src(igniter, "mix.exs") =~ ":ash"
      assert src(igniter, "config/config.exs") =~ "ash_domains"
      assert src(igniter, "lib/sample/application.ex") =~ "Sample.Ash.Domain"
      # exactly one registration, never duplicated by the second run
      assert length(Regex.scan(~r/Sample\.Ash\.Domain/, src(igniter, "lib/sample/application.ex"))) ==
               1
    end

    test "inline Supervisor.start_link([]) is rewritten once, then stable" do
      igniter =
        assert_idempotent(
          "ggen_igniter.install",
          ["--with-ash-domain", "--domain", "Sample.Ash.Domain", "--yes"],
          files: %{"mix.exs" => @mix_exs, "lib/sample/application.ex" => @inline_app_ex}
        )

      assert src(igniter, "lib/sample/application.ex") =~ "children ="
    end

    test "inline deps: [...] in project/0 is refused fail-closed, nothing written" do
      igniter =
        [files: %{"mix.exs" => @inline_deps_mix_exs}]
        |> Igniter.Test.test_project()
        |> Igniter.compose_task("ggen_igniter.install", ["--with-ash-domain", "--domain", "Sample.Ash.Domain", "--yes"])
        |> assert_refused("declares deps inline")

      refute Igniter.changed?(igniter, "mix.exs")
    end
  end

  describe "SafeRename" do
    test "unguarded def rename is idempotent" do
      source = """
      defmodule MyApp.Sample do
        def foo(x), do: x
        def caller(x), do: MyApp.Sample.foo(x)
      end
      """

      igniter =
        assert_idempotent(
          fn i ->
            GgenIgniter.Refactors.SafeRename.rename_function(
              i,
              {MyApp.Sample, :foo},
              {MyApp.Sample, :bar},
              arity: 1
            )
          end,
          [],
          files: %{"lib/my_app/sample.ex" => source}
        )

      assert src(igniter, "lib/my_app/sample.ex") =~ "def bar"
      refute src(igniter, "lib/my_app/sample.ex") =~ "foo"
    end

    test "guarded and parenless zero-arity renames are idempotent" do
      source = """
      defmodule MyApp.Guarded do
        def foo(x) when x > 0, do: x
        def zero do
          :ok
        end
      end
      """

      igniter =
        assert_idempotent(
          fn i ->
            i
            |> GgenIgniter.Refactors.SafeRename.rename_function(
              {MyApp.Guarded, :foo},
              {MyApp.Guarded, :bar},
              arity: 1
            )
            |> GgenIgniter.Refactors.SafeRename.rename_function(
              {MyApp.Guarded, :zero},
              {MyApp.Guarded, :nada},
              arity: 0
            )
          end,
          [],
          files: %{"lib/my_app/guarded.ex" => source}
        )

      content = src(igniter, "lib/my_app/guarded.ex")
      assert content =~ "def bar"
      assert content =~ "nada"
      refute content =~ "def foo"
    end
  end

  describe "rename task" do
    test "--from/--to rename is idempotent" do
      source = """
      defmodule MyApp.Sample do
        def foo(x), do: x
      end
      """

      igniter =
        assert_idempotent(
          "ggen_igniter.rename",
          ["--from", "MyApp.Sample.foo", "--to", "MyApp.Sample.bar", "--arity", "1", "--yes"],
          files: %{"lib/my_app/sample.ex" => source}
        )

      assert src(igniter, "lib/my_app/sample.ex") =~ "def bar"
    end
  end

  describe "mutation falsifier: the harness can fail" do
    defp append_comment(igniter) do
      Igniter.update_file(igniter, "lib/x.ex", fn source ->
        Rewrite.Source.update(
          source,
          :content,
          Rewrite.Source.get(source, :content) <> "# touched\n"
        )
      end)
    end

    test "a non-idempotent codemod makes assert_idempotent raise ExUnit.AssertionError" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_idempotent(&append_comment/1, [], files: %{"lib/x.ex" => "defmodule X do\nend\n"})
      end
    end

    test "a codemod that changes nothing is rejected as vacuous" do
      assert_raise ExUnit.AssertionError, ~r/vacuous/, fn ->
        assert_idempotent(& &1, [], files: %{"lib/x.ex" => "defmodule X do\nend\n"})
      end
    end

    test "assert_refused raises when no matching issue exists" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_refused(Igniter.Test.test_project(), "nope")
      end
    end
  end
end
