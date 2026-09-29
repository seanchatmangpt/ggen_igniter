defmodule GgenIgniter.PostgresCaseTest do
  @moduledoc """
  Chicago-style: `GgenIgniter.Test.PostgresCase` against a REAL Postgres through
  real Postgrex connections; assertions are on rows and on the real `pg_database`
  catalog. Tagged `:postgres` so the suite can exclude these when no server is
  reachable (ExUnit cannot skip at runtime). One always-run test proves
  `available?/0` never raises against an unreachable port. No doubles.
  """
  use ExUnit.Case, async: false
  # async: false -- the availability test mutates process-global env vars.

  alias GgenIgniter.Test.PostgresCase

  describe "available?/0 (always runs)" do
    test "returns false, not a raise, when pointed at an unreachable port" do
      previous = System.get_env("QUALIFY_PGPORT")
      System.put_env("QUALIFY_PGPORT", "1")

      on_exit(fn ->
        if previous,
          do: System.put_env("QUALIFY_PGPORT", previous),
          else: System.delete_env("QUALIFY_PGPORT")
      end)

      assert PostgresCase.available?() == false
    end

    test "does not kill, link to, or leave messages in the caller when the port is refused" do
      previous = System.get_env("QUALIFY_PGPORT")
      System.put_env("QUALIFY_PGPORT", "1")

      on_exit(fn ->
        if previous,
          do: System.put_env("QUALIFY_PGPORT", previous),
          else: System.delete_env("QUALIFY_PGPORT")
      end)

      # Run in a NON-trapping, freshly spawned caller: an untrappable linked exit
      # would kill it, and we would observe :DOWN with a non-:normal reason.
      parent = self()

      {pid, mon} =
        spawn_monitor(fn ->
          links_before = Process.info(self(), :links)
          r1 = PostgresCase.available?()
          r2 = PostgresCase.available?()
          {:messages, msgs} = Process.info(self(), :messages)
          send(parent, {:result, r1, r2, msgs, links_before == Process.info(self(), :links)})
        end)

      assert_receive {:DOWN, ^mon, :process, ^pid, :normal}, 15_000
      assert_received {:result, false, false, [], true}
    end
  end

  describe "against a real Postgres" do
    @describetag :integration
    @describetag :postgres

    test "available?/0 is true" do
      assert PostgresCase.available?() == true
    end

    test "create_database!/drop_database! round trip via the real catalog" do
      name = "ggen_test_#{System.unique_integer([:positive])}"
      refute PostgresCase.database_exists?(name)
      PostgresCase.create_database!(name)
      assert PostgresCase.database_exists?(name)
      PostgresCase.drop_database!(name)
      refute PostgresCase.database_exists?(name)
    end

    test "setup_database/1 yields a working fresh database", _ do
      %{database: db, connect_opts: opts} = PostgresCase.setup_database()
      assert db =~ ~r/^ggen_test_\d+$/
      {:ok, conn} = Postgrex.start_link(opts)
      Postgrex.query!(conn, "CREATE TABLE t (id int, name text)", [])
      Postgrex.query!(conn, "INSERT INTO t VALUES ($1, $2)", [7, "seven"])
      assert %{rows: [[7, "seven"]]} = Postgrex.query!(conn, "SELECT id, name FROM t", [])
      GenServer.stop(conn)
      PostgresCase.drop_database!(db)
      refute PostgresCase.database_exists?(db)
    end
  end
end
