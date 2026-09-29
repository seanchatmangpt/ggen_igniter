defmodule GgenIgniter.Test.PostgresCase do
  @moduledoc """
  Chicago-style helper for tests that need a REAL Postgres (no doubles).

  Connection settings come from `QUALIFY_PGHOST` (default `localhost`; a value
  starting with `/` is a unix-socket directory), `QUALIFY_PGPORT` (5432),
  `QUALIFY_PGUSER` (`postgres`), `QUALIFY_PGPASSWORD` (`postgres`),
  `QUALIFY_PGDATABASE` (`postgres`), matching
  `test/fixtures/ash_manufacture_pack/bin/qualify.sh`.
  """

  @doc """
  True iff a real `SELECT 1` succeeds within 2s. Never raises and never exits the
  caller: the probe runs in an unlinked, monitored process, so a refused
  connection (Postgrex's connection process exits abnormally under
  `backoff_type: :stop`) only takes down the probe, which is reported as `false`.
  """
  @spec available?() :: boolean()
  def available? do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    parent = self()
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, conn} = Postgrex.start_link(connect_opts() ++ [backoff_type: :stop])

            try do
              match?({:ok, %{rows: [[1]]}}, Postgrex.query(conn, "SELECT 1", [], timeout: 2_000))
            after
              try do
                GenServer.stop(conn)
              catch
                _, _ -> :ok
              end
            end
          catch
            _, _ -> false
          end

        send(parent, {ref, result})
      end)

    receive do
      {^ref, bool} ->
        Process.demonitor(mon, [:flush])
        bool

      {:DOWN, ^mon, :process, ^pid, _reason} ->
        # the probe died (e.g. linked Postgrex conn exited): unreachable
        flush(ref)
        false
    after
      3_000 ->
        Process.exit(pid, :kill)
        Process.demonitor(mon, [:flush])
        flush(ref)
        false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp flush(ref) do
    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end
  end

  @doc "Postgrex options from the QUALIFY_PG* environment (read at call time)."
  @spec connect_opts() :: keyword()
  def connect_opts do
    host = System.get_env("QUALIFY_PGHOST", "localhost")

    conn =
      if String.starts_with?(host, "/"), do: [socket_dir: host], else: [hostname: host]

    conn ++
      [
        port: String.to_integer(System.get_env("QUALIFY_PGPORT", "5432")),
        username: System.get_env("QUALIFY_PGUSER", "postgres"),
        password: System.get_env("QUALIFY_PGPASSWORD", "postgres"),
        database: System.get_env("QUALIFY_PGDATABASE", "postgres"),
        connect_timeout: 2_000
      ]
  end

  @doc "Creates database `name` via the `postgres` maintenance db."
  @spec create_database!(String.t()) :: :ok
  def create_database!(name), do: admin!("CREATE DATABASE #{quote_ident(name)}")

  @doc "Drops database `name` (forcing off any connections)."
  @spec drop_database!(String.t()) :: :ok
  def drop_database!(name),
    do: admin!("DROP DATABASE IF EXISTS #{quote_ident(name)} WITH (FORCE)")

  @doc "Does a database named `name` exist? (real catalog query)"
  @spec database_exists?(String.t()) :: boolean()
  def database_exists?(name) do
    {:ok, conn} = Postgrex.start_link(maintenance_opts())

    try do
      %{rows: rows} =
        Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [name])

      rows != []
    after
      GenServer.stop(conn)
    end
  end

  @doc """
  For ExUnit `setup`: creates a fresh unique database, registers an `on_exit`
  drop, returns `%{database: name, connect_opts: opts}` (opts target the new db).
  """
  @spec setup_database(map()) :: %{database: String.t(), connect_opts: keyword()}
  def setup_database(_context \\ %{}) do
    name = "ggen_test_#{System.unique_integer([:positive])}"
    create_database!(name)
    ExUnit.Callbacks.on_exit(fn -> drop_database!(name) end)
    %{database: name, connect_opts: Keyword.put(connect_opts(), :database, name)}
  end

  defp maintenance_opts, do: Keyword.put(connect_opts(), :database, "postgres")

  defp admin!(sql) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, conn} = Postgrex.start_link(maintenance_opts())

    try do
      Postgrex.query!(conn, sql, [])
      :ok
    after
      GenServer.stop(conn)
    end
  end

  defp quote_ident(name) do
    unless name =~ ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, do: raise(ArgumentError, "bad db name #{name}")
    ~s("#{name}")
  end
end
