defmodule GgenIgniter.SemanticJiraTransitionStoreQualifierFalsifiersTest do
  @moduledoc """
  QUALIFIER FALSIFIERS for the transition-store stream (`errc/transition-store`,
  builder head `a04566f`). Chicago-style: real directories, a real local
  Postgres, real concurrent processes, no doubles.

  Each test encodes a claim from the stream's receipt and FAILS on `a04566f`
  (observed by the qualifier, 2026-09-21). They are red on purpose: a fix
  turns them green, nothing else should change them.

  1. `FileStore` optimistic-concurrency path: a writer that loses the
     `expected_seq` race releases its digest claim (`File.rm(marker)`), but
     concurrent duplicate writers of the same event are already parked in
     `await/3` on that claim and, after ~5 s, return `{:ok, nil,
     :already_recorded}` -- a nil "stored" event.
  2. `PostgresStore` consistency CHECK: `(event->>'event_digest') = digest AND
     (event->>'seq')::bigint = seq` evaluates to NULL (which a CHECK accepts)
     when the document lacks either key, so `{}` is stored.
  3. `PostgresStore.invariants/1` matches constraints/triggers by NAME only,
     so a table carrying the right names with wrong definitions (no append-only
     enforcement at all) is adopted by `new/2` instead of refused.

  Postgres tests skip with a named reason when no Postgres is reachable.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira.TransitionLog
  alias GgenIgniter.SemanticJira.TransitionLog.PostgresStore
  alias GgenIgniter.TestSupport.TransitionLogPostgres, as: PG

  @pg_skip (case PG.probe() do
              :ok ->
                nil

              {:error, reason} ->
                "SKIPPED: real Postgres unreachable, so PostgresStore falsifiers are UNVERIFIED " <>
                  "on this machine (#{reason})"
            end)

  defp event(i) do
    %{
      "kind" => "standing_transition_event",
      "identity" => "QF#{i}",
      "from" => "UNKNOWN",
      "to" => "ALIVE",
      "receipt_digest" => "sha256:" <> String.pad_leading("#{i}", 64, "0"),
      "authority" => "NONE"
    }
  end

  describe "FileStore expected_seq (QUALIFIER FALSIFIER 1)" do
    @tag timeout: 180_000
    test "duplicate strict writers of a losing event never receive a nil event" do
      results =
        for round <- 1..4 do
          dir =
            Path.join(System.tmp_dir!(), "sj_qf1_#{round}_#{System.unique_integer([:positive])}")

          on_exit(fn -> File.rm_rf!(dir) end)

          tasks =
            for i <- [1, 2], _dup <- 1..6 do
              Task.async(fn ->
                receive do
                  :go -> TransitionLog.append(dir, event(i), expected_seq: 1)
                end
              end)
            end

          Enum.each(tasks, &send(&1.pid, :go))
          Enum.map(tasks, &Task.await(&1, 60_000))
        end
        |> List.flatten()

      nil_events = Enum.filter(results, &match?({:ok, nil, _}, &1))

      assert nil_events == [],
             "#{length(nil_events)} of #{length(results)} strict appends returned a nil " <>
               "event as {:ok, nil, :already_recorded}"
    end
  end

  describe "PostgresStore SQL invariants (QUALIFIER FALSIFIERS 2 and 3)" do
    if @pg_skip, do: @describetag(skip: @pg_skip)

    setup do
      table = "tl_qf_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
      on_exit(fn -> drop_table(table) end)
      {:ok, store} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 4])
      on_exit(fn -> safe_close(store) end)
      %{store: store, table: table}
    end

    test "the consistency CHECK rejects an event document lacking event_digest or seq",
         %{store: store, table: table} do
      digest = fn n -> "sha256:" <> String.pad_leading(Integer.to_string(n, 16), 64, "0") end

      cases = [
        {"empty document", 1, digest.(1), %{}},
        {"no seq", 2, digest.(2), %{"event_digest" => digest.(2)}},
        {"no event_digest", 3, digest.(3), %{"seq" => 3}}
      ]

      verdicts =
        for {label, seq, dg, doc} <- cases do
          res =
            Postgrex.query(
              store.conn,
              ~s|INSERT INTO "#{table}" (seq, digest, event) VALUES ($1, $2, $3)|,
              [seq, dg, doc]
            )

          {label, sql_code(res)}
        end

      assert verdicts == Enum.map(cases, fn {label, _, _, _} -> {label, :check_violation} end),
             "expected every malformed document to be rejected by the CHECK, got #{inspect(verdicts)}"
    end

    test "a table with the right constraint/trigger names but wrong definitions is refused",
         %{store: store} do
      spoof =
        "tl_qf_spoof_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"

      on_exit(fn -> drop_table(spoof) end)

      for sql <- [
            ~s|CREATE TABLE "#{spoof}" (seq bigint NOT NULL, digest text NOT NULL, | <>
              ~s|event jsonb NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(), | <>
              ~s|CONSTRAINT "#{spoof}_seq_uniq" UNIQUE (recorded_at), | <>
              ~s|CONSTRAINT "#{spoof}_digest_uniq" UNIQUE (recorded_at, digest), | <>
              ~s|CONSTRAINT "#{spoof}_event_consistent" CHECK (true))|,
            ~s|CREATE FUNCTION "#{spoof}_reject_mutation"() RETURNS trigger | <>
              ~s|LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$|,
            ~s|CREATE TRIGGER "#{spoof}_append_only_row" AFTER INSERT ON "#{spoof}" | <>
              ~s|FOR EACH ROW EXECUTE FUNCTION "#{spoof}_reject_mutation"()|,
            ~s|CREATE TRIGGER "#{spoof}_append_only_truncate" AFTER INSERT ON "#{spoof}" | <>
              ~s|FOR EACH ROW EXECUTE FUNCTION "#{spoof}_reject_mutation"()|
          ] do
        Postgrex.query!(store.conn, sql, [])
      end

      assert {:error, {:missing_invariants, _}} =
               PostgresStore.new(store.conn, table: spoof, migrate: false)
    end
  end

  defp sql_code({:error, %Postgrex.Error{postgres: %{code: code}}}), do: code
  defp sql_code({:ok, _}), do: :accepted

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
