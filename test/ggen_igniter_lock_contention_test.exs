defmodule GgenIgniterLockContentionTest do
  @moduledoc """
  Real lock-contention dogfood test for `GgenIgniter.Lock` (see
  `lib/ggen_igniter/lock.ex`). Spawns two genuinely concurrent Elixir
  processes via `Task.async/1`, both racing `GgenIgniter.Lock.acquire/2`
  against the SAME `base_dir`/`lock_key` at nearly the same time. No mocks:
  this exercises the real `File.open/2` `:exclusive`-mode OS-level race the
  module's moduledoc documents -- the assertion is on real resulting state
  (which task actually got `{:ok, %GgenIgniter.Lock{}}`, which one actually
  raised), not on any interaction/call-count check.

  Because `acquire/2` blocks-and-retries rather than failing fast, the loser
  is given a short `timeout_ms` so the second racer's failure mode (a
  `RuntimeError` naming the still-held lock path) is observed directly
  instead of waiting out the 30s default.

  The winner genuinely holds the lock (a real `Process.sleep/1`) for longer
  than the loser's `timeout_ms` before returning, rather than letting its
  task process exit the instant `acquire/2` returns. This matters for real:
  `GgenIgniter.Lock`'s real PID-liveness staleness check (see `lock.ex`'s
  "Stale-lock recovery" moduledoc section) checks whether the holder's
  process is genuinely still alive, on demand, at contention time -- a
  winner whose process exits immediately after acquiring (never calling
  `release/1`) is indistinguishable from a real crashed holder, and its
  lock becomes correctly, immediately reclaimable. Holding the lock for a
  real duration here is what makes "exactly one winner" the correct
  real-world expectation instead of an artifact of an unnaturally
  short-lived task process.
  """

  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "exactly one of two concurrent Task.async acquirers wins the real file lock", %{
    tmp_dir: tmp_dir
  } do
    lock_key = tmp_dir

    # A short barrier so both tasks race File.open/2's :exclusive mode as
    # close together as real BEAM process scheduling allows.
    parent = self()
    ref = make_ref()

    # A real hold duration: whichever task genuinely wins the OS-level race
    # must stay alive (not exit its process) for longer than the loser's
    # timeout_ms below, so the loser's failure is a real "still held by a
    # live process" outcome rather than a race against an already-dead
    # holder's PID.
    hold_ms = 500
    loser_timeout_ms = 200

    task_a =
      Task.async(fn ->
        send(parent, {ref, :ready})
        receive do: ({^ref, :go} -> :ok)

        try do
          {:ok, lock} = GgenIgniter.Lock.acquire(lock_key, timeout_ms: loser_timeout_ms)
          Process.sleep(hold_ms)
          {:ok, {:ok, lock}}
        rescue
          e in RuntimeError -> {:error, :locked, e}
        end
      end)

    task_b =
      Task.async(fn ->
        send(parent, {ref, :ready})
        receive do: ({^ref, :go} -> :ok)

        try do
          {:ok, lock} = GgenIgniter.Lock.acquire(lock_key, timeout_ms: loser_timeout_ms)
          Process.sleep(hold_ms)
          {:ok, {:ok, lock}}
        rescue
          e in RuntimeError -> {:error, :locked, e}
        end
      end)

    # Wait for both tasks to be scheduled and parked at the barrier, then
    # release them at (as close to) the same instant as possible.
    receive do: ({^ref, :ready} -> :ok)
    receive do: ({^ref, :ready} -> :ok)
    send(task_a.pid, {ref, :go})
    send(task_b.pid, {ref, :go})

    result_a = Task.await(task_a, 5_000)
    result_b = Task.await(task_b, 5_000)

    results = [result_a, result_b]

    winners =
      Enum.filter(results, fn
        {:ok, {:ok, %GgenIgniter.Lock{}}} -> true
        _ -> false
      end)

    losers =
      Enum.filter(results, fn
        {:error, :locked, %RuntimeError{}} -> true
        _ -> false
      end)

    assert length(winners) == 1,
           "expected exactly one winner, got: #{inspect(results)}"

    assert length(losers) == 1,
           "expected exactly one loser to raise RuntimeError (mapped to {:error, :locked, _}), got: #{inspect(results)}"

    # Real state assertion: the lock file genuinely exists on disk after the
    # race, and releasing the real winner's lock actually removes it.
    [{:ok, {:ok, winner_lock}}] = winners
    lock_path = Path.join(lock_key, ".ggen_igniter/.sync.lock")
    assert File.exists?(lock_path)

    :ok = GgenIgniter.Lock.release(winner_lock)
    refute File.exists?(lock_path)
  end
end
