defmodule GgenIgniter.SyncControllerDelegationTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `Mix.Tasks.GgenIgniter.Sync.igniter/1`
  actually delegates real reconciliation work to a running
  `GgenIgniter.Controller` (registered under the name `GgenIgniter.Controller`,
  `Process.whereis/1`-discoverable -- the same registration idiom this
  codebase's own `GgenIgniter.Engine.Qlever` already uses for
  `GgenIgniter.Finch`) instead of running the standalone pipeline inline, and
  that the standalone pipeline is the exact fallback when no controller is
  registered (the common case, exercised by every other
  `test/ggen_igniter_sync_*.exs` file, none of which registers one).

  Every collaborator is real: a real `GgenIgniter.Controller` `GenServer`
  (`start_link/1`, registered under its real expected name), the real
  `Mix.Tasks.GgenIgniter.Sync` module, the real `test/fixtures/*` ontology/
  query/template fixtures already used by
  `test/ggen_igniter_sync_task_test.exs`, and real temp-directory file I/O. No
  `Mix`/`Process`/`GenServer` mocking.

  Invoked fully IN-PROCESS (same BEAM, same test process) via
  `Igniter.Mix.Task.configure_and_run/3` -- the exact real function
  `use Igniter.Mix.Task`'s generated `run/1` itself calls right after parsing
  argv -- rather than a `System.cmd("mix", ...)` subprocess. This is
  deliberate: the whole point of this test is proving that IN-PROCESS
  controller state (a real GenServer's `reconciliation_count`) persists
  across two calls in the SAME BEAM process without a fresh disk read. A
  subprocess-per-invocation test could never observe that -- a fresh `mix`
  invocation is a fresh, state-free OS process every time, which is exactly
  the CLI-only behavior `GgenIgniter.Controller`'s own moduledoc contrasts
  itself against.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.Controller

  @ontology "test/fixtures/audit_trail_ontology.ttl"
  @template "test/fixtures/extension.ex.eex"

  setup do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_controller_delegation_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    # Guard against test pollution from another test leaving a stray
    # `GgenIgniter.Controller` registered -- would silently corrupt this
    # test's own delegation proof (both tests below assert `refute` this
    # first, rather than assuming a clean slate).
    if pid = Process.whereis(GgenIgniter.Controller) do
      GenServer.stop(pid)
    end

    %{out_dir: out_dir}
  end

  test "igniter/1 delegates to a real running controller: notice reflects real in-process state",
       %{out_dir: out_dir} do
    refute Process.whereis(GgenIgniter.Controller)

    {:ok, controller_pid} = Controller.start_link(name: GgenIgniter.Controller)
    on_exit(fn -> if Process.alive?(controller_pid), do: GenServer.stop(controller_pid) end)

    assert Process.whereis(GgenIgniter.Controller) == controller_pid

    out_path = Path.join(out_dir, "resource.ex")

    argv = [
      "--engine",
      "sparql",
      "--ontology",
      @ontology,
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      @template,
      "--out",
      out_path
    ]

    # -- First call: real reconciliation, real file write, controller's first
    # -- ever record for this pack_key (`{template_path, out_path}`).
    igniter1 = run_sync!(argv)
    assert [notice1] = igniter1.notices

    assert notice1 =~ "via controller: reconciliation #1 for"
    assert notice1 =~ "wrote #{out_path}"
    assert File.exists?(out_path)

    content_after_first = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content_after_first)

    # The manifest.json reconciliation file (the standalone pipeline's own
    # bookkeeping) is deliberately NOT written on the delegated path -- the
    # controller's in-process state is this call's reconciliation record
    # instead. Real, disclosed trade-off (see this task's own moduledoc).
    refute File.exists?(Path.join(out_dir, ".ggen_igniter/manifest.json"))

    # -- Second call: identical argv, same live BEAM process. If `igniter/1`
    # -- had silently fallen back to the standalone pipeline instead of
    # -- actually delegating, this notice would read
    # -- "unchanged (skipped, identical content): ..." with NO
    # -- "via controller" suffix at all (see the fallback test below for
    # -- exactly what that looks like) -- it would never say
    # -- "reconciliation #2", a number that exists ONLY in this one BEAM
    # -- process's GenServer state, never on disk.
    igniter2 = run_sync!(argv)
    assert [notice2] = igniter2.notices

    assert notice2 =~ "via controller: reconciliation #2 for"
    assert notice2 =~ "unchanged (skipped, identical content):"

    # The real controller process itself confirms the identical fact via its
    # own public API (`status/2`), independent of the CLI's own notice text --
    # a second, independent read of the same real in-process state.
    pack_key = {@template, out_path}
    assert {:ok, record} = Controller.status(GgenIgniter.Controller, pack_key)
    assert record.reconciliation_count == 2
    assert record.receipt.outcome == :unchanged
    assert record.receipt.engine == "sparql"

    # The file's real, on-disk content genuinely did not change between the
    # two calls (a real, byte-level fact -- not merely inferred from notice
    # text).
    assert File.read!(out_path) == content_after_first
  end

  test "igniter/1 falls back to the exact standalone pipeline when no controller is registered",
       %{out_dir: out_dir} do
    refute Process.whereis(GgenIgniter.Controller)

    out_path = Path.join(out_dir, "resource_no_controller.ex")

    argv = [
      "--engine",
      "sparql",
      "--ontology",
      @ontology,
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      @template,
      "--out",
      out_path
    ]

    igniter = run_sync!(argv)
    assert [notice] = igniter.notices

    refute notice =~ "via controller"
    assert notice =~ "wrote #{out_path}"
    assert File.exists?(out_path)
  end

  # Real, in-process invocation of the real `mix ggen_igniter.sync` Igniter
  # task -- exactly the same `parse_argv/1` + `igniter/1` call sequence
  # `use Igniter.Mix.Task`'s generated `run/1` performs after argv parsing
  # (`Igniter.Mix.Task.configure_and_run/3` is that shared, public plumbing),
  # minus only the outer `Mix.Task.run("compile")` and the final
  # `Igniter.do_or_dry_run/2` diff-printing step -- neither of which this
  # module's own `Actuate.write_file!/3`-based writes depend on, since actual
  # file writes happen via real `File.write!/2` calls inside the pipeline
  # itself, not through Igniter's in-memory source/diff machinery.
  defp run_sync!(argv) do
    Igniter.new()
    |> Map.put(:task, "ggen_igniter.sync")
    |> Igniter.Mix.Task.configure_and_run(Mix.Tasks.GgenIgniter.Sync, argv)
  end
end
