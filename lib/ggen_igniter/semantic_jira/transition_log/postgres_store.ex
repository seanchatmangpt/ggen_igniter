if Code.ensure_loaded?(Postgrex) do
  defmodule GgenIgniter.SemanticJira.TransitionLog.PostgresStore do
    @moduledoc """
    Postgres-backed `GgenIgniter.SemanticJira.TransitionLog.Store`: the same
    append-only transition log as `FileStore`, with the invariants enforced
    by the database instead of by exclusive-create files.

    Store spec: a `%PostgresStore{}` (from `connect/1` or `new/2`), usable
    anywhere a `TransitionLog` path is, e.g.

        {:ok, store} = PostgresStore.connect(database: "mydb")
        Reconciler.reconcile(work_order, receipt, store)

    or, equivalently, `Reconciler.reconcile(work_order, receipt, ref, store: PostgresStore)`.

    ## Schema (one table per log, created idempotently by `migrate!/1`)

    | Column | Invariant |
    |---|---|
    | `seq bigint` | `UNIQUE`, `CHECK (seq > 0)` -- exclusive per-seq claim |
    | `digest text` | `UNIQUE` -- exclusive per-digest claim (idempotent replay) |
    | `event jsonb` | `CHECK` that `event->>'event_digest' = digest` and `event->>'seq' = seq` |
    | `recorded_at timestamptz` | informational; never read by projection |

    Append-only is enforced by triggers that reject every `UPDATE`, `DELETE`
    and `TRUNCATE` (SQLSTATE `23001`, `restrict_violation`). `migrate!/1` also
    issues `REVOKE UPDATE, DELETE, TRUNCATE ... FROM PUBLIC`, which only
    matters if `ALTER DEFAULT PRIVILEGES` had granted them to PUBLIC. A
    superuser or table owner can still `DROP TRIGGER`/`DROP TABLE`;
    tamper-*evidence* (signing, hash chain) is not claimed, same as the file
    store. `connect/1` and `new/2` fail closed: a table missing any invariant
    is refused (`{:error, {:missing_invariants, [...]}}`), never adopted.

    ## Optimistic concurrency

    `append/3` reads the head, then inserts `seq = head + 1`. Two writers that
    pick the same `seq` collide on `UNIQUE(seq)`; the loser re-reads the head
    and retries (bounded, jittered). With `expected_seq: n` the loser is not
    retried: it gets `{:error, {:seq_conflict, head}}` and stores nothing.
    Two writers of the same event collide on `UNIQUE(digest)`
    (`ON CONFLICT (digest) DO NOTHING`): exactly one row is stored and the
    other gets `{:ok, event, :already_recorded}`. Commit order can differ
    from `seq` order, so a reader may briefly see `seq` 6 before 5 commits;
    `SemanticJira.project/2` sorts by `seq`, so replay of a settled log is
    deterministic. Gaps are possible only if a writer is killed between
    claiming and committing (a single autocommit statement, so in practice
    never); duplicates are not.

    ## Optional dependency

    `:postgrex` is `optional: true` in `mix.exs`. A consumer without it gets a
    stub module whose functions raise an actionable error.
    """

    @behaviour GgenIgniter.SemanticJira.TransitionLog.Store

    alias GgenIgniter.SemanticJira

    @default_table "semantic_jira_transition_log"
    @page 500
    @max_attempts 1_000

    defstruct conn: nil, table: @default_table

    @type t :: %__MODULE__{conn: GenServer.server(), table: String.t()}

    @doc """
    Starts a Postgrex pool (linked to the caller), verifies the connection,
    creates/verifies the log table, and returns the store.

    Options: `:url` (`postgres://user:pass@host:port/db`) or any
    `Postgrex.start_link/1` option (`:hostname`, `:socket_dir`, `:username`,
    `:password`, `:database`, `:pool_size`, ...), plus `:table` (default
    `#{@default_table}`) and `:migrate` (default `true`; `false` only
    verifies).
    """
    @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
    def connect(opts) do
      {table, opts} = Keyword.pop(opts, :table, @default_table)
      {migrate?, opts} = Keyword.pop(opts, :migrate, true)

      with {:ok, _} <- Application.ensure_all_started(:postgrex),
           {:ok, conn} <- start_pool(opts) do
        case setup(conn, table, migrate?) do
          {:ok, store} ->
            {:ok, store}

          {:error, _} = error ->
            # this function owns the pool it started; `new/2` never stops a
            # connection it did not start
            close(%__MODULE__{conn: conn, table: table})
            error
        end
      end
    end

    @doc """
    Wraps an already-running `Postgrex` connection/pool. Same `:table` and
    `:migrate` options as `connect/1`.
    """
    @spec new(GenServer.server(), keyword()) :: {:ok, t()} | {:error, term()}
    def new(conn, opts \\ []) do
      setup(conn, Keyword.get(opts, :table, @default_table), Keyword.get(opts, :migrate, true))
    end

    @doc "Stops the pool started by `connect/1`."
    @spec close(t()) :: :ok
    def close(%__MODULE__{conn: conn}) when is_pid(conn), do: GenServer.stop(conn)
    def close(%__MODULE__{}), do: :ok

    @doc """
    Creates the log table, its unique constraints, check constraints and
    append-only triggers if absent. Idempotent and safe to run concurrently
    (serialised by a transaction-scoped advisory lock).
    """
    @spec migrate!(t()) :: :ok
    def migrate!(%__MODULE__{conn: conn, table: table}) do
      t = ident!(table)

      statements = [
        "SELECT pg_advisory_xact_lock(hashtext($1::text))",
        """
        CREATE TABLE IF NOT EXISTS #{t} (
          seq bigint NOT NULL,
          digest text NOT NULL,
          event jsonb NOT NULL,
          recorded_at timestamptz NOT NULL DEFAULT now(),
          CONSTRAINT #{ident!(table <> "_seq_uniq")} UNIQUE (seq),
          CONSTRAINT #{ident!(table <> "_digest_uniq")} UNIQUE (digest),
          CONSTRAINT #{ident!(table <> "_seq_positive")} CHECK (seq > 0),
          CONSTRAINT #{ident!(table <> "_event_consistent")}
            CHECK ((event->>'event_digest') = digest AND (event->>'seq')::bigint = seq)
        )
        """,
        """
        CREATE OR REPLACE FUNCTION #{ident!(table <> "_reject_mutation")}() RETURNS trigger
        LANGUAGE plpgsql AS $fn$
        BEGIN
          RAISE EXCEPTION 'transition log % is append-only: % rejected', TG_TABLE_NAME, TG_OP
            USING ERRCODE = 'restrict_violation';
        END
        $fn$
        """,
        trigger_sql(table, "_append_only_row", "BEFORE UPDATE OR DELETE", "ROW"),
        trigger_sql(table, "_append_only_truncate", "BEFORE TRUNCATE", "STATEMENT"),
        "REVOKE UPDATE, DELETE, TRUNCATE ON #{t} FROM PUBLIC"
      ]

      {:ok, :ok} =
        Postgrex.transaction(conn, fn tx ->
          Enum.each(statements, fn
            "SELECT pg_advisory_xact_lock" <> _ = sql -> Postgrex.query!(tx, sql, [table])
            sql -> Postgrex.query!(tx, sql, [])
          end)
        end)

      :ok
    end

    defp trigger_sql(table, suffix, event, granularity) do
      name = table <> suffix

      """
      DO $do$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = '#{name}' AND tgrelid = '#{ident!(table)}'::regclass
        ) THEN
          CREATE TRIGGER #{ident!(name)} #{event} ON #{ident!(table)}
            FOR EACH #{granularity} EXECUTE FUNCTION #{ident!(table <> "_reject_mutation")}();
        END IF;
      END
      $do$
      """
    end

    @doc """
    Inspects the catalog and reports which invariants the table really has:
    `%{unique_seq: bool, unique_digest: bool, append_only_row: bool,
    append_only_truncate: bool, event_consistent: bool}`.
    """
    @spec invariants(t()) :: %{atom() => boolean()}
    def invariants(%__MODULE__{conn: conn, table: table}) do
      ident!(table)

      constraint = fn suffix, type ->
        Postgrex.query!(
          conn,
          "SELECT count(*) FROM pg_constraint WHERE conname = $1 AND contype::text = $2 " <>
            "AND conrelid = to_regclass($3)",
          [table <> suffix, type, ident!(table)]
        ).rows == [[1]]
      end

      trigger = fn suffix ->
        Postgrex.query!(
          conn,
          "SELECT count(*) FROM pg_trigger WHERE tgname = $1 AND tgrelid = to_regclass($2) " <>
            "AND tgenabled = 'O'",
          [table <> suffix, ident!(table)]
        ).rows == [[1]]
      end

      %{
        unique_seq: constraint.("_seq_uniq", "u"),
        unique_digest: constraint.("_digest_uniq", "u"),
        event_consistent: constraint.("_event_consistent", "c"),
        append_only_row: trigger.("_append_only_row"),
        append_only_truncate: trigger.("_append_only_truncate")
      }
    end

    # -- Store callbacks ---------------------------------------------------

    @impl true
    def append(%__MODULE__{} = store, event, opts \\ []) do
      event = Map.put(event, "event_digest", SemanticJira.digest(Map.delete(event, "seq")))
      digest = event["event_digest"]

      case get(store, digest) do
        {:ok, existing} -> {:ok, existing, :already_recorded}
        :error -> attempt(store, event, digest, Keyword.get(opts, :expected_seq), 1)
      end
    end

    @impl true
    def list(%__MODULE__{conn: conn, table: table}) do
      conn
      |> Postgrex.query!("SELECT event FROM #{ident!(table)} ORDER BY seq", [])
      |> Map.fetch!(:rows)
      |> Enum.map(fn [event] -> event end)
    end

    @impl true
    def stream(%__MODULE__{conn: conn, table: table}) do
      sql = "SELECT seq, event FROM #{ident!(table)} WHERE seq > $1 ORDER BY seq LIMIT $2"

      Stream.resource(
        fn -> 0 end,
        fn after_seq ->
          case Postgrex.query!(conn, sql, [after_seq, @page]).rows do
            [] ->
              {:halt, after_seq}

            rows ->
              {Enum.map(rows, fn [_seq, event] -> event end), rows |> List.last() |> hd()}
          end
        end,
        fn _ -> :ok end
      )
    end

    @impl true
    def get(%__MODULE__{conn: conn, table: table}, digest) do
      case Postgrex.query!(conn, "SELECT event FROM #{ident!(table)} WHERE digest = $1", [digest]) do
        %{rows: [[event]]} -> {:ok, event}
        %{rows: []} -> :error
      end
    end

    @impl true
    def head(%__MODULE__{conn: conn, table: table}) do
      %{rows: [[head]]} =
        Postgrex.query!(conn, "SELECT COALESCE(MAX(seq), 0) FROM #{ident!(table)}", [])

      head
    end

    # -- append: optimistic claim of `seq`, retried on collision ------------

    defp attempt(_store, _event, _digest, nil, tries) when tries > @max_attempts,
      do: {:error, :seq_contention}

    defp attempt(store, event, digest, expected, tries) do
      head = head(store)

      if expected != nil and expected != head + 1 do
        {:error, {:seq_conflict, head}}
      else
        seq = expected || head + 1
        insert(store, Map.put(event, "seq", seq), digest, seq, expected, tries)
      end
    end

    defp insert(
           %__MODULE__{conn: conn, table: table} = store,
           stamped,
           digest,
           seq,
           expected,
           tries
         ) do
      sql = """
      INSERT INTO #{ident!(table)} (seq, digest, event) VALUES ($1, $2, $3)
      ON CONFLICT (digest) DO NOTHING
      RETURNING event
      """

      seq_constraint = table <> "_seq_uniq"

      case Postgrex.query(conn, sql, [seq, digest, stamped]) do
        {:ok, %{num_rows: 1, rows: [[event]]}} ->
          {:ok, event, :appended}

        # Another writer stored this exact event first.
        {:ok, %{num_rows: 0}} ->
          {:ok, existing} = get(store, digest)
          {:ok, existing, :already_recorded}

        # Lost the race for this seq to another writer.
        {:error,
         %Postgrex.Error{postgres: %{code: :unique_violation, constraint: ^seq_constraint}}} ->
          if expected do
            {:error, {:seq_conflict, head(store)}}
          else
            Process.sleep(:rand.uniform(min(tries, 8)))
            retry(store, Map.delete(stamped, "seq"), digest, tries + 1)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    # A concurrent writer may have stored this very event since we looked.
    defp retry(store, event, digest, tries) do
      case get(store, digest) do
        {:ok, existing} -> {:ok, existing, :already_recorded}
        :error -> attempt(store, event, digest, nil, tries)
      end
    end

    # -- connection / setup -------------------------------------------------

    defp setup(conn, table, migrate?) do
      store = %__MODULE__{conn: conn, table: table}

      with :ok <- check_ident(table),
           {:ok, _} <- Postgrex.query(conn, "SELECT 1", []),
           :ok <- if(migrate?, do: migrate!(store), else: :ok),
           :ok <- verify(store) do
        {:ok, store}
      end
    rescue
      e in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, e}
    end

    defp verify(store) do
      case for {name, false} <- invariants(store), do: name do
        [] -> :ok
        missing -> {:error, {:missing_invariants, missing}}
      end
    end

    defp start_pool(opts) do
      opts =
        opts
        |> expand_url()
        |> Keyword.put_new(:pool_size, 10)
        |> Keyword.put_new(:queue_target, 2_000)
        |> Keyword.put_new(:queue_interval, 10_000)

      Postgrex.start_link(opts)
    end

    @doc false
    # Expands a `:url` option (`postgres://user:pass@host:port/db`, userinfo
    # percent-decoded) into Postgrex connection options; explicit options win.
    @spec expand_url(keyword()) :: keyword()
    def expand_url(opts) do
      case Keyword.pop(opts, :url) do
        {nil, opts} ->
          opts

        {url, opts} ->
          uri = URI.parse(url)
          {user, password} = split_userinfo(uri.userinfo)

          url_opts =
            [
              hostname: uri.host,
              port: uri.port,
              username: user,
              password: password,
              database: uri.path && String.trim_leading(uri.path, "/")
            ]
            |> Enum.reject(fn {_, v} -> v in [nil, ""] end)

          Keyword.merge(url_opts, opts)
      end
    end

    defp split_userinfo(nil), do: {nil, nil}

    defp split_userinfo(userinfo) do
      case String.split(userinfo, ":", parts: 2) do
        [user, password] -> {URI.decode(user), URI.decode(password)}
        [user] -> {URI.decode(user), nil}
      end
    end

    # Table names are interpolated into SQL, so they are restricted to a plain
    # lower-case identifier (and always double-quoted).
    defp check_ident(name) do
      if is_binary(name) and Regex.match?(~r/\A[a-z_][a-z0-9_]{0,40}\z/, name),
        do: :ok,
        else: {:error, {:invalid_table_name, name}}
    end

    # Derived names (`<table>_seq_uniq`, ...) are longer than the table name
    # but stay under Postgres' 63-byte identifier limit.
    defp ident!(name) do
      if is_binary(name) and Regex.match?(~r/\A[a-z_][a-z0-9_]{0,62}\z/, name),
        do: ~s("#{name}"),
        else: raise(ArgumentError, "invalid identifier: #{inspect(name)}")
    end
  end
else
  defmodule GgenIgniter.SemanticJira.TransitionLog.PostgresStore do
    @moduledoc """
    Stub: `:postgrex` is an optional dependency of `ggen_igniter` and is not
    in this project's deps, so the Postgres transition-log store is
    unavailable. Add `{:postgrex, "~> 0.19"}` to your own deps to use it.
    Every function raises.
    """

    @behaviour GgenIgniter.SemanticJira.TransitionLog.Store

    defstruct conn: nil, table: nil

    defp unavailable! do
      raise RuntimeError,
            "GgenIgniter.SemanticJira.TransitionLog.PostgresStore needs the optional " <>
              ":postgrex dependency; add {:postgrex, \"~> 0.19\"} to your mix.exs deps"
    end

    def connect(_opts), do: unavailable!()
    def new(_conn, _opts \\ []), do: unavailable!()
    def close(_store), do: unavailable!()
    def migrate!(_store), do: unavailable!()
    def invariants(_store), do: unavailable!()

    @impl true
    def append(_store, _event, _opts \\ []), do: unavailable!()
    @impl true
    def list(_store), do: unavailable!()
    @impl true
    def stream(_store), do: unavailable!()
    @impl true
    def get(_store, _digest), do: unavailable!()
    @impl true
    def head(_store), do: unavailable!()
  end
end
