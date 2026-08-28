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

    task_a =
      Task.async(fn ->
        send(parent, {ref, :ready})
        receive do: ({^ref, :go} -> :ok)

        try do
          {:ok, GgenIgniter.Lock.acquire(lock_key, timeout_ms: 500)}
        rescue
          e in RuntimeError -> {:error, :locked, e}
        end
      end)

    task_b =
      Task.async(fn ->
        send(parent, {ref, :ready})
        receive do: ({^ref, :go} -> :ok)

        try do
          {:ok, GgenIgniter.Lock.acquire(lock_key, timeout_ms: 500)}
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
