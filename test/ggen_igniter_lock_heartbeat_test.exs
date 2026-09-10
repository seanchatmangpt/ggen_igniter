defmodule GgenIgniter.LockHeartbeatTest do
  @moduledoc """
  Chicago-style: real lock files on disk, a real spawned Elixir process
  holding the lock, no mocked clock and no mocked `Process.alive?/1`.
  Exercises the real fix for the gap GAPS-TO-FILL.v26.9.1.md #6 describes: a
  legitimately slow same-node holder whose lock file's mtime has aged past
  `@stale_after_ms` (5 minutes) must NOT have its lock stolen by a second
  concurrent `GgenIgniter.Lock.acquire/2` caller, because
  `GgenIgniter.Lock`'s real `holder_pid_status/1` resolves the holder's
  `erlang_pid=` marker via `:erlang.list_to_pid/1` and checks
  `Process.alive?/1` for real before ever consulting mtime-age. Conversely, a
  holder process that has genuinely exited is immediately reclaimable even
  with a fresh mtime.
  """

  use ExUnit.Case, async: false

  # async: false -- writes/touches a real lock file at a fixed real path per
  # test, same rationale as ggen_igniter_lock_staleness_properties_test.exs.

  @stale_after_ms 5 * 60 * 1000
  @lock_subpath ".ggen_igniter/.sync.lock"

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_lock_heartbeat_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "a live same-node holder's lock is NOT stolen even once its file's mtime is well past @stale_after_ms" do
    tmp_dir = scratch_dir!("live_old_mtime")
    lock_path = Path.join(tmp_dir, @lock_subpath)

    parent = self()

    # A real process that genuinely holds the lock for real, past
    # @stale_after_ms while alive -- this is the exact regression scenario:
    # a legitimately slow run, not a crashed one.
    holder =
      spawn(fn ->
        {:ok, lock} = GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 5_000)
        send(parent, {:acquired, lock})

        receive do
          :release -> :ok
        after
          5_000 -> :timeout
        end

        :ok = GgenIgniter.Lock.release(lock)
        send(parent, :released)
      end)

    assert_receive {:acquired, %GgenIgniter.Lock{}}, 5_000
    assert Process.alive?(holder)

    # Real mtime, set via File.touch/2 against a real posix timestamp well
    # past @stale_after_ms -- not a mocked clock. The holder process is
    # still genuinely alive the entire time.
    past_posix_seconds =
      div(System.os_time(:millisecond) - @stale_after_ms - 60_000, 1000)

    File.touch!(lock_path, past_posix_seconds)
    assert Process.alive?(holder)

    # A real second acquire/2 call must keep blocking against the live
    # holder (PID-liveness wins over mtime-age) and raise the documented
    # timeout error -- it must NOT silently steal the lock.
    assert_raise RuntimeError, ~r/could not acquire lock/, fn ->
      GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 300, retry_interval_ms: 20)
    end

    # Real state: the live holder's lock file is untouched.
    assert File.exists?(lock_path)
    assert File.read!(lock_path) =~ "erlang_pid=#{inspect(holder)}"

    send(holder, :release)
    assert_receive :released, 5_000
    refute File.exists?(lock_path)
  end

  test "a holder whose real OS process has genuinely died is immediately reclaimable, even with a fresh mtime" do
    tmp_dir = scratch_dir!("dead_fresh_mtime")
    lock_path = Path.join(tmp_dir, @lock_subpath)
    File.mkdir_p!(Path.dirname(lock_path))

    # A real, separate OS process (`sh -c 'echo $$'`) whose pid we capture --
    # by the time System.cmd/3 returns synchronously, that real subprocess
    # has genuinely exited. This models the exact disclosed primary scenario
    # (a separate `mix` OS process that crashed without reaching `release/1`)
    # more faithfully than a same-VM `spawn/1`, whose lightweight-process
    # death does not end the real OS pid the fix now keys liveness on.
    {pid_output, 0} = System.cmd("sh", ["-c", "echo $$"])
    dead_os_pid = String.trim(pid_output)

    File.write!(
      lock_path,
      "pid=#{dead_os_pid} node=#{Node.self()} creation=0 " <>
        "erlang_pid=#{inspect(self())} at=crashed-holder\n"
    )

    # The file's mtime is genuinely fresh (just written) -- if mtime-age
    # were the only signal this would fail with a timeout, proving
    # PID-liveness (the real, dead OS pid) is checked first and wins.
    assert File.exists?(lock_path)

    assert {:ok, %GgenIgniter.Lock{} = new_lock} =
             GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 2_000, retry_interval_ms: 10)

    assert File.read!(lock_path) =~ "pid=#{System.pid()}"

    :ok = GgenIgniter.Lock.release(new_lock)
    refute File.exists?(lock_path)
  end
end
