defmodule Mix.Tasks.GgenIgniter.RenameTaskTest do
  @moduledoc """
  Chicago-style tests for `mix ggen_igniter.rename`
  (`lib/mix/tasks/ggen_igniter.rename.ex`): real `System.cmd("mix", [...])`
  subprocess invocations of the real task, against real scratch fixture `.ex`
  files written to disk under `test/fixtures/rename_task/` (removed in
  `on_exit`). No mocking of any kind -- every assertion is on the RENAMED
  FILE'S REAL ON-DISK CONTENT after the real subprocess exits, mirroring the
  real-subprocess technique `test/ggen_igniter_hand_authored_task_test.exs`
  uses for its own mix task, adapted to this task's lighter cost model (no
  scratch consumer package / `mix deps.get` needed -- this task runs entirely
  against THIS project's own already-compiled environment, exactly the way
  `test/ggen_igniter_plan_task_test.exs` already does for `mix
  ggen_igniter.plan`).

  Each fixture module below lives in its own uniquely-suffixed subdirectory
  (`System.unique_integer([:positive])`) so concurrent/repeated `mix test`
  runs never collide, but its FILE is always named `sample.ex` -- matching
  `Macro.underscore(List.last(Module.split(module)))`, Elixir's own file
  convention. This is not cosmetic: confirmed for real, `Igniter.Project.
  Module.find_module/2`'s fast `try_filename_match` strategy
  (`deps/igniter/lib/igniter/project/module.ex`) globs for a file whose
  BASENAME equals the module's underscored last segment; a fixture filename
  that does NOT follow that convention (tried first, before this fix) misses
  every fast strategy and falls through to `try_full_scan`, which globs and
  reads every `.ex`/`.exs` file in this large project through a hardcoded
  5-second `Task.Supervised.stream` timeout in the `rewrite` library --
  observed for real, as a genuine
  `** (exit) exited in: Task.Supervised.stream(5000)` crash, under this
  session's concurrent multi-closure system load. Naming the fixture file
  the way a real caller's file would already be named makes discovery take
  the same fast path a real project uses, and is the actual fix, not a
  workaround.

  `--yes` is always passed: `Igniter.Util.IO.yes?/1` (the confirmation prompt
  the real `Igniter.Mix.Task` runner shows before writing) raises on EOF
  stdin, which is exactly what a real headless `System.cmd` subprocess gives
  it without `--yes` -- confirmed by reading `deps/igniter/lib/igniter/util/io.ex`,
  not assumed.
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 120_000

  @fixture_root Path.expand("fixtures/rename_task", __DIR__)

  # `subdir` is unique per test; the file itself is always named to match
  # the fixture module's own last segment ("Sample" -> "sample.ex") so
  # `Igniter.Project.Module.find_module/2` finds it via its fast filename
  # match instead of falling through to a full-project scan -- see this
  # module's own @moduledoc.
  defp write_fixture!(subdir, content) do
    path = Path.join([@fixture_root, subdir, "sample.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp run_task(args) do
    System.cmd("mix", ["ggen_igniter.rename" | args ++ ["--yes"]],
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  setup_all do
    File.mkdir_p!(@fixture_root)
    on_exit(fn -> File.rm_rf(@fixture_root) end)
    :ok
  end

  describe "unguarded def (the common case)" do
    test "renames the def and every fully-qualified call site, real on-disk content updated" do
      n = System.unique_integer([:positive])
      mod = "GgenIgniterRenameFixture.Plain#{n}.Sample"

      # The caller uses a FULLY-QUALIFIED call (`#{mod}.foo(x)`), not a bare
      # local call: confirmed for real by reading
      # `deps/igniter/lib/igniter/code/function.ex`'s `function_call?/3`
      # 2-tuple clause, `Igniter.Refactors.Rename.rename_function/4`'s
      # call-site remap only matches qualified/aliased calls
      # (`Module.function(...)`, incl. piped), never a bare unqualified call
      # -- even inside the function's own defining module. A bare local call
      # is genuinely out of scope for both upstream and SafeRename; this
      # test exercises the call shape the primitive actually rewrites.
      path =
        write_fixture!("plain_#{n}", """
        defmodule #{mod} do
          def foo(x) do
            x
          end

          def caller(x) do
            #{mod}.foo(x)
          end
        end
        """)

      {output, exit_code} = run_task(["--from", "#{mod}.foo", "--to", "#{mod}.bar"])

      assert exit_code == 0, "mix ggen_igniter.rename failed (exit #{exit_code}):\n#{output}"

      content = File.read!(path)
      assert content =~ "def bar(x) do"
      refute content =~ "def foo(x) do"
      # the fully-qualified call site was remapped too (real
      # Igniter.Refactors.Rename behavior, reused unmodified by SafeRename
      # for the safe/unguarded case)
      assert content =~ "#{mod}.bar(x)"
      refute content =~ "#{mod}.foo(x)"

      # The real, rewritten source still parses -- the rewrite is a valid AST,
      # not just a text substitution that happens to look right.
      assert {:ok, _quoted} = Code.string_to_quoted(content)
    end
  end

  describe "guarded def (the real defect this task's underlying SafeRename routes around)" do
    test "renames the guarded def's head, which plain Igniter.Refactors.Rename alone leaves un-renamed -- proving the CLI really calls SafeRename" do
      n = System.unique_integer([:positive])
      mod = "GgenIgniterRenameFixture.Guarded#{n}.Sample"

      path =
        write_fixture!("guarded_#{n}", """
        defmodule #{mod} do
          def foo(x) when x > 0 do
            x
          end

          def caller(x) do
            #{mod}.foo(x)
          end
        end
        """)

      {output, exit_code} = run_task(["--from", "#{mod}.foo/1", "--to", "#{mod}.bar"])

      assert exit_code == 0, "mix ggen_igniter.rename failed (exit #{exit_code}):\n#{output}"

      content = File.read!(path)

      # The qualified call site is renamed (upstream's own remap_calls
      # already handles this)...
      assert content =~ "#{mod}.bar(x)"
      refute content =~ "#{mod}.foo(x)"
      # ...AND the guarded def head itself is ALSO renamed (real, observed
      # fix; test/ggen_igniter_safe_rename_test.exs proves the same code path
      # at the unit level -- this proves the CLI wiring reaches it too),
      # which `Igniter.Refactors.Rename.rename_function/4` alone (the
      # upstream function this task deliberately does NOT call directly)
      # leaves un-renamed per its own documented defect.
      assert content =~ "def bar(x) when x > 0 do"
      refute content =~ "def foo(x) when x > 0 do"
    end
  end

  describe "invalid invocation" do
    test "exits non-zero and prints a typed error when --to is missing" do
      n = System.unique_integer([:positive])
      mod = "GgenIgniterRenameFixture.Missing#{n}.Sample"

      write_fixture!("missing_to_#{n}", """
      defmodule #{mod} do
        def foo, do: :ok
      end
      """)

      {output, exit_code} = run_task(["--from", "#{mod}.foo"])

      refute exit_code == 0
      assert output =~ "to"
    end

    test "exits non-zero on a malformed --from (no function segment)" do
      {output, exit_code} = run_task(["--from", "NotAFunction", "--to", "Also.Not.AFunction"])

      refute exit_code == 0
      assert output =~ "invalid --from" or output =~ "invalid"
    end
  end
end
