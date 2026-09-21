defmodule GgenIgniter.SemanticJiraTransitionStorePostgresTest do
  @moduledoc """
  Chicago-style: the real `TransitionLog.PostgresStore` against a REAL local
  Postgres (throwaway database `ggen_igniter_transition_test`, one uniquely
  named table per test, dropped on exit). No test doubles: real Postgrex
  pools, real SQL constraints and triggers, real concurrent writer processes
  (including writers on separate connection pools), real `Reconciler`
  admission over real WorkOrders. Asserts on resulting database state and on
  projections, and compares replay from the Postgres store with replay from
  the real `FileStore` for the same events.

  Runs the shared store contract (`GgenIgniter.TransitionStoreCase`) that the
  file store also passes, then the Postgres-only invariants: UNIQUE(seq),
  UNIQUE(digest), event/column consistency CHECKs, append-only triggers
  (UPDATE / DELETE / TRUNCATE rejected), idempotent and concurrent migration.

  `async: false`: every test shares one database and opens several
  connection pools; serial execution keeps the connection count bounded.

  SKIP CONDITION: if no Postgres is reachable (`TransitionLogPostgres.probe/0`
  fails) every test in this module is skipped with a named reason printed to
  stderr and carried on the `:skip` tag -- never a silent pass, never a
  substituted double.
  """
  use GgenIgniter.TransitionStoreCase, async: false

  import GgenIgniter.TestSupport.SemanticJiraFixtures

  alias GgenIgniter.SemanticJira.Reconciler
  alias GgenIgniter.SemanticJira.TransitionLog.{FileStore, PostgresStore}
  alias GgenIgniter.TestSupport.TransitionLogPostgres, as: PG

  @moduletag :postgres

  @pg_skip (case PG.probe() do
              :ok ->
                nil

              {:error, reason} ->
                "SKIPPED: real Postgres unreachable, so PostgresStore is UNVERIFIED on this " <>
                  "machine (#{reason}); set GGEN_TRANSITION_PG_URL or start Postgres"
            end)

  if @pg_skip do
    IO.puts(:stderr, "[transition-store] #{@pg_skip}")
    @moduletag skip: @pg_skip
  end

  setup do
    # Collision-resistant per-test table: the database outlives the VM, so a
    # bare counter could land on a table left behind by an earlier (possibly
    # broken) run -- which the store would then, correctly, refuse.
    table = "tl_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
    on_exit(fn -> drop_table(table) end)

    {:ok, store} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 10])
    on_exit(fn -> safe_close(store) end)

    %{store: store, table: table}
  end

  store_contract()

  # -- helpers ---------------------------------------------------------------

  defp drop_table(table) do
    {:ok, admin} = Postgrex.start_link(PG.conn_opts())
    Postgrex.query!(admin, ~s|DROP TABLE IF EXISTS "#{table}"|, [])
    Postgrex.query!(admin, ~s|DROP FUNCTION IF EXISTS "#{table}_reject_mutation"()|, [])
    GenServer.stop(admin)
  end

  defp q(store, sql, params \\ []), do: Postgrex.query(store.conn, sql, params)

  defp pg_code({:error, %Postgrex.Error{postgres: %{code: code}}}), do: code

  defp pg_constraint({:error, %Postgrex.Error{postgres: %{constraint: c}}}), do: c

  defp raw_insert(store, seq, digest, event) do
    q(
      store,
      ~s|INSERT INTO "#{store.table}" (seq, digest, event) VALUES ($1, $2, $3)|,
      [seq, digest, event]
    )
  end

  defp row_count(store) do
    %{rows: [[n]]} = Postgrex.query!(store.conn, ~s|SELECT count(*) FROM "#{store.table}"|, [])
    n
  end

  defp raw_rows(store) do
    Postgrex.query!(
      store.conn,
      ~s|SELECT seq, digest, event FROM "#{store.table}" ORDER BY seq|,
      []
    ).rows
  end

  # The pool is linked to the (already exited) test process and may be gone.
  defp safe_close(store) do
    PostgresStore.close(store)
  catch
    :exit, _ -> :ok
  end

  defp consistent_event(seq, digest),
    do: %{"event_digest" => digest, "seq" => seq, "to" => "ALIVE"}

  defp dg(n), do: "sha256:" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")

  # -- schema invariants -----------------------------------------------------

  describe "schema invariants (enforced by the database)" do
    test "connect verifies every invariant against the catalog", %{store: store} do
      assert PostgresStore.invariants(store) == %{
               unique_seq: true,
               unique_digest: true,
               event_consistent: true,
               append_only_row: true,
               append_only_truncate: true
             }
    end

    test "UNIQUE(seq): a second event cannot claim an occupied seq", %{store: store, table: table} do
      assert {:ok, _} = raw_insert(store, 1, dg(1), consistent_event(1, dg(1)))
      res = raw_insert(store, 1, dg(2), consistent_event(1, dg(2)))
      assert pg_code(res) == :unique_violation
      assert pg_constraint(res) == "#{table}_seq_uniq"
      assert %{rows: [[1]]} = elem(q(store, ~s|SELECT count(*) FROM "#{table}"|), 1)
    end

    test "UNIQUE(digest): the same event cannot be stored under a second seq",
         %{store: store, table: table} do
      assert {:ok, _} = raw_insert(store, 1, dg(1), consistent_event(1, dg(1)))
      res = raw_insert(store, 2, dg(1), consistent_event(2, dg(1)))
      assert pg_code(res) == :unique_violation
      assert pg_constraint(res) == "#{table}_digest_uniq"
    end

    test "CHECK: the event document must agree with its digest and seq columns",
         %{store: store, table: table} do
      # digest column disagrees with event_digest inside the document
      res = raw_insert(store, 1, dg(1), consistent_event(1, dg(2)))
      assert pg_code(res) == :check_violation
      assert pg_constraint(res) == "#{table}_event_consistent"

      # seq column disagrees with seq inside the document
      res = raw_insert(store, 1, dg(1), consistent_event(2, dg(1)))
      assert pg_code(res) == :check_violation

      # seq must be positive
      res = raw_insert(store, 0, dg(1), consistent_event(0, dg(1)))
      assert pg_code(res) == :check_violation
      assert pg_constraint(res) == "#{table}_seq_positive"

      assert row_count(store) == 0
    end

    test "append-only: UPDATE, DELETE and TRUNCATE are rejected and change nothing",
         %{store: store, table: table} do
      {:ok, ev, :appended} =
        TransitionLog.append(store, %{"identity" => "A", "to" => "ALIVE"})

      before_rows = raw_rows(store)

      for sql <- [
            ~s|UPDATE "#{table}" SET event = '{}'::jsonb|,
            ~s|UPDATE "#{table}" SET seq = seq + 10|,
            ~s|UPDATE "#{table}" SET digest = 'x'|,
            ~s|DELETE FROM "#{table}"|,
            ~s|DELETE FROM "#{table}" WHERE seq = 1|,
            ~s|TRUNCATE "#{table}"|
          ] do
        res = q(store, sql)
        assert pg_code(res) == :restrict_violation, "#{sql} was not rejected: #{inspect(res)}"
        assert res |> elem(1) |> Map.fetch!(:postgres) |> Map.fetch!(:message) =~ "append-only"
      end

      # also rejected inside an explicit transaction, and the txn is aborted
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Postgrex.transaction(store.conn, fn tx ->
          Postgrex.query!(tx, ~s|DELETE FROM "#{table}"|, [])
        end)
      end

      assert raw_rows(store) == before_rows
      assert TransitionLog.read(store) == [ev]
    end

    test "migrate!/1 is idempotent and safe under concurrent migration", %{store: store} do
      assert :ok = PostgresStore.migrate!(store)
      assert :ok = PostgresStore.migrate!(store)

      fresh = %{
        store
        | table:
            "tl_fresh_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
      }

      on_exit(fn -> drop_table(fresh.table) end)

      results =
        1..8
        |> Task.async_stream(fn _ -> PostgresStore.migrate!(fresh) end,
          max_concurrency: 8,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert results == List.duplicate(:ok, 8)
      assert Enum.all?(PostgresStore.invariants(fresh), fn {_, v} -> v end)
    end

    test "an unmigrated table is refused (fail closed) rather than trusted", %{store: store} do
      table =
        "tl_missing_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"

      assert {:error, {:missing_invariants, missing}} =
               PostgresStore.new(store.conn, table: table, migrate: false)

      assert Enum.sort(missing) ==
               Enum.sort([
                 :unique_seq,
                 :unique_digest,
                 :event_consistent,
                 :append_only_row,
                 :append_only_truncate
               ])
    end

    test "a pre-existing table that lacks an invariant is refused, not adopted", %{store: store} do
      table = "tl_weak_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
      on_exit(fn -> drop_table(table) end)

      # same columns, but no UNIQUE(seq) and no consistency CHECK
      Postgrex.query!(
        store.conn,
        ~s|CREATE TABLE "#{table}" (seq bigint NOT NULL, digest text NOT NULL, event jsonb NOT NULL, | <>
          ~s|recorded_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT "#{table}_digest_uniq" UNIQUE (digest))|,
        []
      )

      assert {:error, {:missing_invariants, missing}} =
               PostgresStore.new(store.conn, table: table)

      assert :unique_seq in missing
      assert :event_consistent in missing
      refute :unique_digest in missing
    end

    test "a hostile table name is refused before any SQL is built", %{store: store} do
      for bad <- [~s|x"; DROP TABLE y; --|, "Has Caps", "", "1abc", String.duplicate("a", 60)] do
        assert {:error, {:invalid_table_name, ^bad}} =
                 PostgresStore.new(store.conn, table: bad)
      end
    end
  end

  # -- reads -----------------------------------------------------------------

  describe "stream/1 pagination" do
    test "streams a multi-page log in seq order without loading it as one query",
         %{store: store, table: table} do
      n = 1_230

      Postgrex.query!(
        store.conn,
        """
        INSERT INTO "#{table}" (seq, digest, event)
        SELECT s, 'sha256:' || lpad(to_hex(s), 64, '0'),
               jsonb_build_object('event_digest', 'sha256:' || lpad(to_hex(s), 64, '0'), 'seq', s)
        FROM generate_series(1, #{n}) AS s
        """,
        []
      )

      assert TransitionLog.head(store) == n
      assert store |> TransitionLog.stream() |> Enum.map(& &1["seq"]) == Enum.to_list(1..n)
      assert store |> TransitionLog.stream() |> Enum.take(3) |> Enum.map(& &1["seq"]) == [1, 2, 3]
      assert length(TransitionLog.read(store)) == n

      # append continues after a bulk-loaded log
      assert {:ok, %{"seq" => 1_231}, :appended} =
               TransitionLog.append(store, %{"identity" => "NEXT", "to" => "ALIVE"})
    end
  end

  # -- connection failure ----------------------------------------------------

  describe "connect/1" do
    @tag timeout: 60_000
    @tag capture_log: true
    test "returns {:error, _} and does not leave a linked pool behind" do
      {:links, before_links} = Process.info(self(), :links)

      assert {:error, _reason} =
               PostgresStore.connect(
                 hostname: "localhost",
                 port: 1,
                 username: "nobody",
                 database: "nothing",
                 pool_size: 1,
                 queue_target: 200,
                 queue_interval: 500,
                 timeout: 2_000
               )

      {:links, after_links} = Process.info(self(), :links)
      assert Enum.sort(after_links) == Enum.sort(before_links)
    end

    test "expand_url/1 parses userinfo (percent-decoded), host, port and database" do
      assert PostgresStore.expand_url(url: "postgres://me:p%40ss:w@db.example:6543/logs") ==
               [
                 hostname: "db.example",
                 port: 6543,
                 username: "me",
                 password: "p@ss:w",
                 database: "logs"
               ]

      assert Enum.sort(
               PostgresStore.expand_url(url: "postgres://me@localhost/logs", pool_size: 3)
             ) ==
               Enum.sort(pool_size: 3, hostname: "localhost", username: "me", database: "logs")

      # explicit options win over the URL
      assert PostgresStore.expand_url(url: "postgres://me@h/logs", database: "other")[:database] ==
               "other"

      assert PostgresStore.expand_url(hostname: "h") == [hostname: "h"]
    end

    test "url option is expanded into connection settings", %{table: table} do
      base = PG.conn_opts()

      auth =
        if base[:password], do: "#{base[:username]}:#{base[:password]}", else: base[:username]

      url = "postgres://#{auth}@#{base[:hostname]}:#{base[:port]}/#{PG.database()}"
      table = table <> "_url"
      on_exit(fn -> drop_table(table) end)

      assert {:ok, via_url} = PostgresStore.connect(url: url, table: table, pool_size: 2)

      assert {:ok, %{"seq" => 1}, :appended} =
               TransitionLog.append(via_url, %{"identity" => "U"})

      PostgresStore.close(via_url)
    end
  end

  # -- concurrency across separate pools -------------------------------------

  describe "concurrent writers on separate connection pools" do
    test "no duplicate seq and no lost event across two pools and 60 writers",
         %{store: store, table: table} do
      {:ok, second} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 4])
      on_exit(fn -> safe_close(second) end)
      stores = [store, second]

      results =
        1..60
        |> Task.async_stream(
          fn i ->
            TransitionLog.append(
              Enum.at(stores, rem(i, 2)),
              %{"identity" => "W#{i}", "to" => "ALIVE"}
            )
          end,
          max_concurrency: 60,
          ordered: false,
          timeout: 120_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(results, &match?({:ok, _, :appended}, &1))

      # database-level truth, independent of the store's own reads
      assert {:ok, %{rows: [[60, 60, 60, 1, 60]]}} =
               q(
                 store,
                 ~s|SELECT count(*), count(DISTINCT seq), count(DISTINCT digest), min(seq), max(seq) FROM "#{table}"|
               )
    end

    test "the same event written from both pools concurrently is stored once",
         %{store: store, table: table} do
      {:ok, second} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 4])
      on_exit(fn -> safe_close(second) end)
      event = %{"identity" => "ONLY", "to" => "ALIVE"}

      results =
        1..40
        |> Task.async_stream(
          fn i ->
            TransitionLog.append(Enum.at([store, second], rem(i, 2)), event)
          end,
          max_concurrency: 40,
          ordered: false,
          timeout: 120_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 1
      assert Enum.count(results, &match?({:ok, _, :already_recorded}, &1)) == 39
      assert row_count(store) == 1
    end

    test "retries under seq contention are bounded and never duplicate (pool of 3, 45 writers)",
         %{table: table} do
      {:ok, narrow} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 3])
      on_exit(fn -> safe_close(narrow) end)

      results =
        1..45
        |> Task.async_stream(
          &TransitionLog.append(narrow, %{"identity" => "N#{&1}"}),
          max_concurrency: 45,
          ordered: false,
          timeout: 120_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(results, &match?({:ok, _, :appended}, &1))

      assert narrow |> TransitionLog.read() |> Enum.map(& &1["seq"]) ==
               Enum.to_list(1..45)
    end
  end

  # -- replay equivalence and the reconciler -----------------------------------

  describe "Reconciler over the Postgres store; replay equals replay from the file store" do
    setup do
      dir = Path.join(System.tmp_dir!(), "sj_store_pg_cmp_#{System.unique_integer([:positive])}")
      File.rm_rf!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    defp run_scenario(log, opts) do
      root = wo("ROOT")
      b = wo("B", ["ROOT"])
      c = wo("C", ["ROOT"])
      rb = receipt(b)
      rc = receipt(c)

      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root), log, opts)
      # siblings minted before ROOT moved (stale snapshot), both admitted
      assert {:ok, _, :appended} = Reconciler.reconcile(b, rb, log, opts)
      assert {:ok, _, :appended} = Reconciler.reconcile(c, rc, log, opts)
      assert {:ok, _, :already_recorded} = Reconciler.reconcile(b, rb, log, opts)

      # refusals store nothing
      assert {:error, {:refused, :definition_mismatch}} =
               Reconciler.reconcile(Map.put(b, "acceptance", ["x"]), rb, log, opts)

      [root, b, c]
    end

    test "sequential scenario: event lists, projection and frontier are identical",
         %{store: store, dir: dir} do
      graph = run_scenario(store, [])
      [root, b, c] = graph
      file_graph = run_scenario(dir, [])

      pg_events = TransitionLog.read(store)
      file_events = TransitionLog.read(dir)

      assert length(pg_events) == 3
      assert pg_events == file_events

      assert SemanticJira.project(graph, pg_events) ==
               SemanticJira.project(file_graph, file_events)

      assert SemanticJira.frontier_from_events(graph, pg_events) ==
               SemanticJira.frontier_from_events(file_graph, file_events)

      {projected, _} = SemanticJira.project(graph, pg_events)
      assert Enum.map(projected, & &1["standing"]) == ["ALIVE", "ALIVE", "ALIVE"]

      # replay from the log alone (producer state discarded) reproduces standing
      replayed =
        pg_events
        |> Enum.map(&Map.drop(&1, ["seq"]))
        |> Enum.with_index(1)
        |> Enum.map(fn {e, i} -> Map.put(e, "seq", i) end)

      assert SemanticJira.project(graph, replayed) == SemanticJira.project(graph, pg_events)

      # every spelling of "use the Postgres store" addresses the same log: the
      # same receipts are already-recorded no-ops (a store struct wins over a
      # conflicting :store option)
      assert {:ok, _, :already_recorded} =
               Reconciler.reconcile(root, receipt(root), {PostgresStore, store})

      assert {:ok, _, :already_recorded} =
               Reconciler.reconcile(b, receipt(b), store, store: PostgresStore)

      assert {:ok, _, :already_recorded} =
               Reconciler.reconcile(c, receipt(c), store, store: FileStore)

      assert length(TransitionLog.read(store)) == 3
    end

    test "dependent is refused until its dependency is logged, on Postgres too", %{store: store} do
      b = wo("B", ["ROOT"])

      assert {:error, {:refused, {:promotion_refused, failed}}} =
               Reconciler.reconcile(b, receipt(b), store)

      assert :dependencies in failed
      assert row_count(store) == 0
    end

    test "concurrent crown: duplicate sibling receipts across two pools dedupe; replay equals file replay",
         %{store: store, table: table, dir: dir} do
      {:ok, second} = PostgresStore.connect(PG.conn_opts() ++ [table: table, pool_size: 4])
      on_exit(fn -> safe_close(second) end)

      root = wo("ROOT")
      siblings = for i <- 1..6, do: wo("S#{i}", ["ROOT"])
      graph = [root | siblings]

      drive = fn logs ->
        assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root), hd(logs))
        # every receipt minted before any sibling moved; each submitted twice
        jobs = Enum.map(siblings, &{&1, receipt(&1)})
        work = Enum.with_index(jobs ++ jobs)

        work
        |> Task.async_stream(
          fn {{w, r}, i} -> Reconciler.reconcile(w, r, Enum.at(logs, rem(i, length(logs)))) end,
          max_concurrency: length(work),
          ordered: false,
          timeout: 120_000
        )
        |> Enum.map(fn {:ok, r} -> r end)
      end

      results = drive.([store, second])
      assert Enum.all?(results, &match?({:ok, _, s} when s in [:appended, :already_recorded], &1))
      assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 6

      pg_events = TransitionLog.read(store)
      assert Enum.map(pg_events, & &1["seq"]) == Enum.to_list(1..7)
      assert pg_events |> Enum.map(& &1["event_digest"]) |> Enum.uniq() |> length() == 7

      file_results = drive.([dir])
      assert Enum.count(file_results, &match?({:ok, _, :appended}, &1)) == 6
      file_events = TransitionLog.read(dir)

      # seq order of the siblings is scheduler-dependent, but the SET of events
      # (seq stripped) and the projected standing must be identical
      strip = fn events ->
        events |> Enum.map(&Map.delete(&1, "seq")) |> Enum.sort_by(& &1["identity"])
      end

      assert strip.(pg_events) == strip.(file_events)
      assert SemanticJira.project(graph, pg_events) == SemanticJira.project(graph, file_events)

      {projected, _} = SemanticJira.project(graph, pg_events)
      assert Enum.all?(projected, &(&1["standing"] == "ALIVE"))
    end
  end
end
