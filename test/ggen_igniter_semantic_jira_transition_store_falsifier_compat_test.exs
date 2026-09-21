defmodule GgenIgniter.SemanticJiraTransitionStoreFalsifierCompatTest do
  @moduledoc """
  QUALIFIER FALSIFIERS (backward compatibility, crash replay, cross-store
  equivalence) for the transition-store stream (`errc/transition-store`,
  builder head `a04566f`, base `dcebc42`). Chicago-style: real directories, a
  real local Postgres, real files left behind by a crashed writer, no doubles.

  Every test here is RED on `a04566f` on purpose (observed by the qualifier,
  2026-09-21); a fix turns it green and nothing else should change it. Where a
  failure is inherited unchanged from the pre-refactor `TransitionLog` at
  `dcebc42` the test says so -- it still breaks the invariant the new
  `TransitionLog.Store` behaviour declares MUST hold for every implementation.

  1. Public API: `TransitionLog.read/1`, `append/2`, `head/1`, `get/2` accepted
     a `Path.t()` (`IO.chardata()`, so a charlist) at `dcebc42`;
     `Store.resolve/1` now raises `FunctionClauseError` for it (REGRESSION).
  2. Crash replay: a writer killed (kill -9) after claiming an event's digest
     and before writing it leaves a `digest-*.claim` file; re-appending that
     event blocks ~5 s and returns `{:ok, nil, :already_recorded}` without
     storing anything (INHERITED from `dcebc42`; violates Store invariant 1).
  3. Idempotence: an event read back from the log and appended again is
     stored a second time under a new digest, because `event_digest` is part
     of the digest input (INHERITED; both stores).
  4. Cross-store equivalence: `jsonb` rewrites integral floats in exponent form
     (`1.0e16` reads back as the integer `10000000000000000`, `-0.0` as `0.0`),
     so the stored event's `event_digest` is no longer re-derivable from it on
     Postgres while it is on the file store; and `\\u0000` in a string is
     accepted by the file store and refused by Postgres (NEW, Postgres only).

  Postgres tests skip with a named reason when no Postgres is reachable.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.TransitionLog
  alias GgenIgniter.SemanticJira.TransitionLog.PostgresStore
  alias GgenIgniter.TestSupport.TransitionLogPostgres, as: PG

  @pg_skip (case PG.probe() do
              :ok ->
                nil

              {:error, reason} ->
                "SKIPPED: real Postgres unreachable, so the Postgres falsifiers are UNVERIFIED " <>
                  "on this machine (#{reason})"
            end)

  defp event(i),
    do: %{"kind" => "standing_transition_event", "identity" => "CF#{i}", "to" => "ALIVE"}

  defp tmp_dir(tag) do
    dir = Path.join(System.tmp_dir!(), "sj_cf_#{tag}_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "public API backward compatibility (QUALIFIER FALSIFIER, regression vs dcebc42)" do
    test "a charlist directory (Path.t() is IO.chardata) is still a valid store spec" do
      dir = tmp_dir("charlist") |> String.to_charlist()

      # dcebc42 accepted every one of these; a04566f raises FunctionClauseError in Store.resolve/1
      assert TransitionLog.read(dir) == []
      assert {:ok, %{"seq" => 1} = stored, :appended} = TransitionLog.append(dir, event(1))
      assert {:ok, ^stored, :already_recorded} = TransitionLog.append(dir, event(1))
      assert TransitionLog.read(dir) == [stored]
    end
  end

  describe "FileStore replay after a killed writer (QUALIFIER FALSIFIER, inherited from dcebc42)" do
    @tag timeout: 120_000
    test "a digest claim orphaned by a crash does not permanently poison re-append" do
      dir = tmp_dir("orphan")
      File.mkdir_p!(dir)
      e = event(1)
      digest = SemanticJira.digest(e)

      # exactly what a writer killed between "claim digest" and "write event" leaves behind
      # (observed after kill -9 of a 30-writer BEAM: 19 of 53 digest claims had no event file)
      File.write!(Path.join(dir, "digest-#{String.slice(digest, 7, 64)}.claim"), "")
      assert TransitionLog.read(dir) == []

      result = TransitionLog.append(dir, e)

      assert match?({:ok, %{"identity" => "CF1"}, _}, result),
             "re-append of an event whose writer crashed returned #{inspect(result)}; " <>
               "Store invariant 1 requires the stored event, never nil"

      assert [%{"identity" => "CF1"}] = TransitionLog.read(dir)
    end
  end

  describe "idempotence of an event read back from the log, file store (QUALIFIER FALSIFIER)" do
    test "re-appending a stored event is :already_recorded" do
      dir = tmp_dir("readd")
      assert {:ok, stored, :appended} = TransitionLog.append(dir, event(1))

      assert {:ok, ^stored, :already_recorded} = TransitionLog.append(dir, stored)
      assert length(TransitionLog.read(dir)) == 1
    end
  end

  describe "idempotence of an event read back from the log, Postgres (QUALIFIER FALSIFIER)" do
    if @pg_skip, do: @describetag(skip: @pg_skip)

    setup :pg_store

    test "re-appending a stored event is :already_recorded", %{store: store} do
      assert {:ok, stored, :appended} = TransitionLog.append(store, event(1))

      assert {:ok, ^stored, :already_recorded} = TransitionLog.append(store, stored)
      assert length(TransitionLog.read(store)) == 1
    end

    test "migrating a file-store log into Postgres preserves each event_digest and seq",
         %{store: store} do
      dir = tmp_dir("migrate")
      for i <- 1..3, do: {:ok, _, :appended} = TransitionLog.append(dir, event(i))
      file_events = TransitionLog.read(dir)

      for e <- file_events, do: TransitionLog.append(store, e)

      pg_events = TransitionLog.read(store)

      assert Enum.map(pg_events, & &1["event_digest"]) ==
               Enum.map(file_events, & &1["event_digest"])

      assert pg_events == file_events
    end
  end

  describe "cross-store equivalence (QUALIFIER FALSIFIER, Postgres only)" do
    if @pg_skip, do: @describetag(skip: @pg_skip)

    setup :pg_store

    test "an event's event_digest stays re-derivable from the stored event on both stores",
         %{store: store} do
      dir = tmp_dir("floats")

      for {label, e} <- [
            {"integral float in exponent form", %{"identity" => "F1", "v" => 1.0e16}},
            {"negative zero", %{"identity" => "F2", "v" => -0.0}}
          ],
          {name, log} <- [{"file", dir}, {"postgres", store}] do
        assert {:ok, stored, :appended} = TransitionLog.append(log, e)
        assert {:ok, back} = TransitionLog.get(log, stored["event_digest"])

        assert back["v"] === e["v"],
               "#{name} store: #{label} read back as #{inspect(back["v"])}, appended #{inspect(e["v"])}"

        assert SemanticJira.digest(Map.drop(back, ["seq", "event_digest"])) ==
                 back["event_digest"],
               "#{name} store: event_digest not re-derivable from the stored event (#{label})"
      end
    end

    test "both stores agree on whether an event containing a NUL character is storable",
         %{store: store} do
      dir = tmp_dir("nul")
      e = %{"identity" => "N1", "note" => "a\u0000b"}

      file_verdict = TransitionLog.append(dir, e) |> elem(0)
      pg_verdict = TransitionLog.append(store, e) |> elem(0)

      assert file_verdict == pg_verdict,
             "file store returned #{inspect(file_verdict)}, Postgres store returned #{inspect(pg_verdict)}"
    end
  end

  defp pg_store(_context) do
    table = "tl_cf_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
    on_exit(fn -> drop_table(table) end)
    {:ok, store} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 4])
    on_exit(fn -> safe_close(store) end)
    %{store: store, table: table}
  end

  defp drop_table(table) do
    {:ok, admin} = Postgrex.start_link(PG.conn_opts())
    Postgrex.query!(admin, ~s|DROP TABLE IF EXISTS "#{table}"|, [])
    Postgrex.query!(admin, ~s|DROP FUNCTION IF EXISTS "#{table}_reject_mutation"()|, [])
    GenServer.stop(admin)
  end

  defp safe_close(store) do
    PostgresStore.close(store)
  catch
    :exit, _ -> :ok
  end
end
