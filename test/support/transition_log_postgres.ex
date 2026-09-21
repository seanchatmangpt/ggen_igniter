defmodule GgenIgniter.TestSupport.TransitionLogPostgres do
  @moduledoc """
  Chicago-style: connection plumbing for the real-Postgres transition-store
  tests. There is no fake server -- `probe/0` opens a real connection to the
  local Postgres, creates the throwaway database `ggen_igniter_transition_test`
  if absent, and reports why not when the server is unreachable, so the test
  module can skip with a named, visible reason instead of failing or silently
  substituting a double.

  Connection settings come from `GGEN_TRANSITION_PG_URL`
  (`postgres://user:pass@host:port/ignored`; the database name is always the
  throwaway one) or default to `localhost:5432` as `$PGUSER`/`$USER`
  (`$PGPASSWORD` if set) -- the local trust-auth setup on this fleet.
  """

  @database "ggen_igniter_transition_test"

  @doc "Name of the throwaway test database."
  def database, do: @database

  @doc "Postgrex connection options for `database` (default: the throwaway database)."
  @spec conn_opts(String.t()) :: keyword()
  def conn_opts(database \\ @database) do
    base =
      case System.get_env("GGEN_TRANSITION_PG_URL") do
        nil -> env_opts()
        url -> url_opts(url)
      end

    Keyword.put(base, :database, database)
  end

  defp env_opts do
    maybe_put(
      [
        hostname: System.get_env("PGHOST") || "localhost",
        port: String.to_integer(System.get_env("PGPORT") || "5432"),
        username: System.get_env("PGUSER") || System.get_env("USER") || "postgres"
      ],
      :password,
      System.get_env("PGPASSWORD")
    )
  end

  defp url_opts(url) do
    uri = URI.parse(url)
    [user | rest] = String.split(uri.userinfo || "postgres", ":", parts: 2)

    maybe_put(
      [hostname: uri.host || "localhost", port: uri.port || 5432, username: URI.decode(user)],
      :password,
      rest |> List.first() |> decode_password()
    )
  end

  defp decode_password(nil), do: nil
  defp decode_password(password), do: URI.decode(password)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  `:ok` when a real Postgres is reachable and the throwaway database exists
  (created here if needed); `{:error, reason_string}` otherwise.
  """
  @spec probe() :: :ok | {:error, String.t()}
  def probe do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    # Isolated in a task that traps exits: with an unreachable server the
    # Postgrex pool process dies and would otherwise take the caller with it.
    task =
      Task.async(fn ->
        Process.flag(:trap_exit, true)
        do_probe()
      end)

    case Task.yield(task, 20_000) || Task.shutdown(task) do
      {:ok, result} -> result
      _ -> {:error, "Postgres probe timed out"}
    end
  end

  defp do_probe do
    opts =
      "postgres"
      |> conn_opts()
      |> Keyword.merge(
        pool_size: 1,
        backoff_type: :stop,
        queue_target: 500,
        queue_interval: 1_000
      )

    with :ok <- tcp_reachable(opts[:hostname], opts[:port]),
         {:ok, conn} <- Postgrex.start_link(opts) do
      try do
        ensure_database(conn)
      after
        if Process.alive?(conn), do: GenServer.stop(conn)
      end
    else
      {:error, reason} -> {:error, "cannot connect to Postgres: #{inspect(reason)}"}
    end
  catch
    kind, reason -> {:error, "Postgres probe #{kind}: #{inspect(reason)}"}
  end

  defp tcp_reachable(host, port) do
    case :gen_tcp.connect(String.to_charlist(host), port, [], 2_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, "#{host}:#{port} not reachable (#{reason})"}
    end
  end

  defp ensure_database(conn) do
    case Postgrex.query(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [@database]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
        case Postgrex.query(conn, ~s(CREATE DATABASE "#{@database}"), []) do
          {:ok, _} -> :ok
          {:error, %Postgrex.Error{postgres: %{code: :duplicate_database}}} -> :ok
          {:error, reason} -> {:error, "cannot create #{@database}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Postgres unreachable: #{inspect(reason)}"}
    end
  end
end
