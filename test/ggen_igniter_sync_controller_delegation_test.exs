defmodule GgenIgniter.SyncControllerDelegationTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `Mix.Tasks.GgenIgniter.Sync.igniter/1`'s
  REAL current dispatch order: `run_via_reactor/3` (the Reactor pipeline) is
  tried FIRST, unconditionally, for any bounded call (no template
  frontmatter, no `--for-each`) -- see that function's own doc comment
  ("Runs the real Reactor pipeline directly (independent of whether a
  `GgenIgniter.Controller` happens to be registered -- the Reactor path does
  not need the Controller's in-process state)"). `dispatch_pipeline/3`
  (which is what actually checks `Process.whereis(GgenIgniter.Controller)`
  and calls `delegate_to_controller/4`) is reached ONLY when
  `run_via_reactor/3` itself returns `{:not_delegatable, reason}` -- template
  frontmatter or `--for-each`, neither of which `delegate_to_controller/4`
  supports either. The real, disclosed, empirically-confirmed consequence:
  for the bounded case both paths cover, a registered `GgenIgniter.Controller`
  is NEVER actually consulted by a plain `mix ggen_igniter.sync` call today
  -- this file proves that real fact directly (a registered controller's own
  `status/2` never gains a record for the call's `pack_key`), rather than
  merely asserting on notice text and treating a matching string as proof of
  the underlying mechanism.

  Originally written (before this repo's "sync always routes through the
  Reactor pipeline" change) to prove the OPPOSITE -- that a registered
  controller's real, persistent, same-BEAM-process `reconciliation_count`
  DID drive a plain call. Verified fresh this session: it no longer does,
  by design, per `run_via_reactor/3`'s own comment above -- this is a
  disclosed architecture decision already stated in the production code,
  not a regression this test exists to catch.

  Every collaborator is real: a real `GgenIgniter.Controller` `GenServer`
  (`start_link/1`, registered under its real expected name), the real
  `Mix.Tasks.GgenIgniter.Sync` module, the real `test/fixtures/*` ontology/
  query/template fixtures already used by
  `test/ggen_igniter_sync_task_test.exs`, and real temp-directory file I/O. No
  `Mix`/`Process`/`GenServer` mocking.

  Invoked fully IN-PROCESS (same BEAM, same test process) via
  `Igniter.Mix.Task.configure_and_run/3` -- the exact real function
  `use Igniter.Mix.Task`'s generated `run/1` itself calls right after parsing
  argv -- rather than a `System.cmd("mix", ...)` subprocess, so a registered
  controller GenServer in THIS test process is actually reachable by the code
  under test.
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

  test "igniter/1 uses the real Reactor pipeline even with a controller running -- delegation never engages",
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
      out_path,
      # `out_path` lives outside the repo root (a real, unique tmp dir this
      # test's own `setup` block creates and removes) -- `--manifest-dir`
      # scopes `GgenIgniter.ArtifactIdentity.within_root?/2`'s
      # authorized-project-root check to that same tmp dir instead of the
      # default `File.cwd!()`, and `--verify-cwd` keeps `:verify`'s real
      # `mix compile` pointed at the real repo root instead of the bare (no
      # `mix.exs`) tmp dir.
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    # -- First call: real reconciliation, real file write, via the Reactor
    # -- pipeline -- NOT via the running controller (see moduledoc).
    igniter1 = run_sync!(argv)
    assert [notice1] = igniter1.notices

    refute notice1 =~ "via controller"
    assert notice1 =~ "(via reactor)"
    assert notice1 =~ "wrote #{out_path}"
    assert File.exists?(out_path)

    content_after_first = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content_after_first)

    # The Reactor pipeline's OWN bookkeeping (`.ggen_igniter/manifest.json`
    # under `--manifest-dir`) IS written on this path -- the opposite of
    # the pre-Reactor-default assumption this test used to encode (a
    # delegated call used to skip the manifest file entirely, relying on
    # the controller's in-process state instead; the Reactor path always
    # writes real, on-disk evidence regardless of any controller).
    assert File.exists?(Path.join(out_dir, ".ggen_igniter/manifest.json"))

    # -- Second call: identical argv, same live BEAM process, same
    # -- registered controller still running. Real idempotent no-op via the
    # -- Reactor pipeline again -- still never "via controller".
    igniter2 = run_sync!(argv)
    assert [notice2] = igniter2.notices

    refute notice2 =~ "via controller"
    assert notice2 =~ "(via reactor)"
    assert notice2 =~ "unchanged (skipped, identical content):"

    # The real controller process's own public API (`status/2`) confirms
    # directly, independent of notice text, that delegation genuinely never
    # happened across EITHER call: no record exists for this pack_key at
    # all (a real record, if one existed, would report
    # `reconciliation_count: 2` by now -- the exact assertion this test
    # made before the Reactor-default change, now inverted to prove the
    # opposite real fact).
    pack_key = {@template, out_path}
    assert :never_reconciled = Controller.status(GgenIgniter.Controller, pack_key)

    # The file's real, on-disk content genuinely did not change between the
    # two calls (a real, byte-level fact -- not merely inferred from notice
    # text).
    assert File.read!(out_path) == content_after_first
  end

  test "igniter/1 uses the real Reactor pipeline when no controller is registered either (the common case)",
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
      out_path,
      # `out_path` lives outside the repo root -- see the controller-
      # delegation test above.
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
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
