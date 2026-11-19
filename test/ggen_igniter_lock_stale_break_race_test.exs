defmodule GgenIgniterLockStaleBreakRaceTest do
  @moduledoc """
  Chicago-style: real tmp_dir, real lock file, real Tasks racing
  `GgenIgniter.Lock.acquire/2`, a real exited OS process supplying a dead pid.
  No test doubles. Pins two laws of `lib/ggen_igniter/lock.ex`:

    * breaking a stale lock never deletes a lock a concurrent winner just
      created (rename-claim, not stale-check-then-rm), so the critical section
      is never entered by two holders at once;
    * `release/1` removes the lock file only when it still carries the
      releasing lock's own marker, so a stolen-and-reacquired lock survives.

  Synchronisation is by message barrier and bounded acquire timeouts, never a
  fixed sleep.
  """

  # async: false -- shares one real lock path per test and spawns real OS processes.
  use ExUnit.Case, async: false

  @tasks 8
  @rounds 50

  defp dead_os_pid do
    {out, 0} = System.cmd("sh", ["-c", "echo $$"])
    String.trim(out)
  end

  @tag :tmp_dir
  test "stale lock broken by 8 racers never admits two holders", %{tmp_dir: tmp_dir} do
    lock_path = GgenIgniter.Lock.lock_path(tmp_dir)
    File.mkdir_p!(Path.dirname(lock_path))
    dead = dead_os_pid()
    parent = self()
    counter = :counters.new(1, [])

    for round <- 1..@rounds do
      File.write!(lock_path, "pid=#{dead} node=nonode@nohost\n")
      assert GgenIgniter.Lock.stale_lock?(lock_path)
      ref = make_ref()

      tasks =
        for _ <- 1..@tasks do
          Task.async(fn ->
            send(parent, {ref, :ready})

            receive do
              {^ref, :go} -> :ok
            end

            {:ok, lock} =
              GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 10_000, retry_interval_ms: 1)

            :counters.add(counter, 1, 1)
            seen = :counters.get(counter, 1)
            :counters.sub(counter, 1, 1)
            :ok = GgenIgniter.Lock.release(lock)
            seen
          end)
        end

      for _ <- 1..@tasks, do: assert_receive({^ref, :ready}, 5_000)
      for t <- tasks, do: send(t.pid, {ref, :go})

      seen = Enum.map(tasks, &Task.await(&1, 30_000))

      assert length(seen) == @tasks, "round #{round}: not all acquirers completed"
      assert Enum.max(seen) == 1, "round #{round}: concurrent holders #{inspect(seen)}"
      refute File.exists?(lock_path), "round #{round}: lock file left behind"
    end

    refute File.exists?(lock_path)
    assert :counters.get(counter, 1) == 0
  end

  @tag :tmp_dir
  test "release by a robbed holder leaves the thief's lock in place", %{tmp_dir: tmp_dir} do
    lock_path = GgenIgniter.Lock.lock_path(tmp_dir)

    {:ok, a} = GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 1_000)
    assert File.exists?(lock_path)

    # B steals: removes A's file out-of-band and acquires.
    :ok = File.rm(lock_path)
    {:ok, b} = GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 1_000)
    refute a.marker == b.marker

    :ok = GgenIgniter.Lock.release(a)
    assert File.exists?(lock_path)
    assert File.read!(lock_path) =~ "marker=#{b.marker} "

    :ok = GgenIgniter.Lock.release(b)
    refute File.exists?(lock_path)
  end
end
