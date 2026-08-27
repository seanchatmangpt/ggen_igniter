defmodule GgenIgniter.ControllerTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.Controller`'s real economic
  claim: a persistent `GenServer` holds live reconciliation state IN THIS
  BEAM PROCESS across multiple `reconcile/2` calls, unlike `mix
  ggen_igniter.sync`'s per-invocation model (a fresh OS process every run,
  with no in-memory continuity between runs at all).

  Every collaborator here is real: a real `GgenIgniter.Controller`
  `GenServer` (started directly via `start_link/1`, not through the
  application's supervision tree -- opt-in wiring is proven separately by
  reading `application.ex`), the real `test/fixtures/sample-pack` fixture
  (ontology + SPARQL gates + EEx template, the same fixture
  `test/ggen_igniter_sync_pack_test.exs` already exercises against the real
  Mix task), the real `GgenIgniter.Reconcile.run/1` pipeline, and real
  temp-directory file I/O. No `Mix`/`Process` mocking, no stubbed
  collaborators.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Controller

  setup do
    {:ok, pid} = Controller.start_link([])

    out_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_controller_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)

    good_opts = [
      engine: "sparql",
      pack_dir: "test/fixtures/sample-pack",
      out: Path.join(out_dir, "resource.ex")
    ]

    %{pid: pid, out_dir: out_dir, good_opts: good_opts}
  end

  test "status/1 reports :never_reconciled for a key that has never been reconciled", %{pid: pid} do
    assert Controller.status(pid, :untouched_key) == :never_reconciled
  end

  test "reconcile/2 called twice against the same real pack: second call is real 'unchanged', " <>
         "and the in-process record (not a fresh disk read) proves state persisted across calls",
       %{pid: pid, good_opts: good_opts} do
    key = :sample_pack

    assert Controller.status(pid, key) == :never_reconciled

    # -- First real reconciliation: fresh file, real :written outcome.
    assert {:ok, record1} = Controller.reconcile(pid, key, good_opts)
    assert record1.receipt.outcome == :written
    assert record1.receipt.engine == "sparql"
    assert record1.manifest == %{good_opts[:out] => :written}
    assert record1.reconciliation_count == 1
    assert File.exists?(good_opts[:out])

    # status/1 right after reconcile/2 returns the EXACT SAME record --
    # a pure in-process GenServer.call, no disk I/O of its own -- proving
    # the record handed back by reconcile/2 is literally what now lives in
    # this process's state, not something reconstructed per-call.
    assert Controller.status(pid, key) == {:ok, record1}

    # -- Second real reconciliation, identical opts, same live process.
    assert {:ok, record2} = Controller.reconcile(pid, key, good_opts)

    # The real, disk-level fact: the file's content did not change, so
    # `GgenIgniter.Actuate.write_file!/3` (a real byte-for-byte compare)
    # reports :unchanged -- same real guarantee the CLI's separate-process
    # model would also observe from this one file.
    assert record2.receipt.outcome == :unchanged
    assert record2.manifest == %{good_opts[:out] => :unchanged}

    # What the CLI's per-invocation model CANNOT produce: real knowledge
    # that lives only in this process's memory, not derivable from the file
    # on disk (which looks byte-identical whether reconciled once or twice).
    # A second, fresh `mix ggen_igniter.sync` OS process has no channel to
    # ask "how many times has this key been reconciled before" other than
    # re-parsing some persisted-to-disk manifest -- this GenServer just
    # already knows, because it held the state across both calls.
    assert record2.reconciliation_count == 2

    # last_run_at genuinely advanced between call 1 and call 2 -- proof the
    # record was actually replaced, not left aliased to the first call's data.
    assert DateTime.compare(record2.last_run_at, record1.last_run_at) == :gt

    # status/1 again reflects the SECOND call's real record, sourced purely
    # from GenServer state -- never re-reads the file to answer this.
    assert Controller.status(pid, key) == {:ok, record2}
  end

  test "status/1 returns the real, correct in-memory record after each call, for distinct keys",
       %{
         pid: pid,
         out_dir: out_dir,
         good_opts: good_opts
       } do
    key_a = :pack_a
    key_b = :pack_b

    out_a = good_opts[:out]
    out_b = Path.join(out_dir, "resource_b.ex")

    assert {:ok, record_a} = Controller.reconcile(pid, key_a, good_opts)
    assert {:ok, record_b} = Controller.reconcile(pid, key_b, Keyword.put(good_opts, :out, out_b))

    assert record_a.manifest == %{out_a => :written}
    assert record_b.manifest == %{out_b => :written}

    # Each key's own real record, independently retrievable -- distinct
    # keys never bleed into each other's in-memory state.
    assert Controller.status(pid, key_a) == {:ok, record_a}
    assert Controller.status(pid, key_b) == {:ok, record_b}
    assert Controller.status(pid, :never_touched) == :never_reconciled
  end

  test "a real crash inside reconcile/2 (nonexistent ontology path) returns a clean error, " <>
         "does not crash the GenServer, and does not corrupt another key's already-good state",
       %{pid: pid, out_dir: out_dir, good_opts: good_opts} do
    key_a = :good_key
    key_b = :bad_key

    # Key A: a real, successful reconciliation first.
    assert {:ok, record_a} = Controller.reconcile(pid, key_a, good_opts)
    assert record_a.receipt.outcome == :written

    # Key B: a real, deliberately broken ontology path -- this raises inside
    # `GgenIgniter.Ontology.load!/1` -> `RDF.Turtle.read_file!/1` (confirmed
    # directly: a real `File.Error` for "no such file or directory").
    bad_opts =
      good_opts
      |> Keyword.delete(:pack_dir)
      |> Keyword.merge(
        ontology: "test/fixtures/does_not_exist_reconcile_controller_test.ttl",
        query: "spec=test/fixtures/spec.rq",
        template: "test/fixtures/extension.ex.eex",
        out: Path.join(out_dir, "should_never_be_written.ex")
      )

    assert {:error, {File.Error, message}} = Controller.reconcile(pid, key_b, bad_opts)
    assert message =~ "no such file or directory"

    # The GenServer itself is still alive -- a real crash inside the pipeline
    # did not take the process down.
    assert Process.alive?(pid)

    # Key B was never reconciled (the failure happened before any file was
    # written, and before this key's state was ever set).
    assert Controller.status(pid, key_b) == :never_reconciled
    refute File.exists?(Path.join(out_dir, "should_never_be_written.ex"))

    # Key A's already-good record is completely untouched by key B's failure.
    assert Controller.status(pid, key_a) == {:ok, record_a}

    # And the server is still fully functional for further real work: a
    # second real reconciliation for key A behaves exactly as it would have
    # if key B's failure had never happened (count keeps advancing).
    assert {:ok, record_a2} = Controller.reconcile(pid, key_a, good_opts)
    assert record_a2.reconciliation_count == 2
    assert record_a2.receipt.outcome == :unchanged
  end
end
