defmodule GgenIgniter.PackLockStaleRaceTest do
  @moduledoc """
  Stale-lock reclaim race: 8 concurrent `PackLock.update/3` callers face an
  aged, token-owned lockdir on a real filesystem. Reclaim must be exclusive
  (no lost update) and leave no lockdir behind.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.PackLock

  @rounds 20
  @writers 8

  @tag :tmp_dir
  test "concurrent reclaim of a stale lockdir loses no update", %{tmp_dir: tmp} do
    for round <- 1..@rounds do
      dir = Path.join(tmp, "round#{round}")
      File.mkdir_p!(dir)
      lock_path = Path.join(dir, "ggen_igniter.pack.lock")
      lockdir = lock_path <> ".lockdir"

      File.mkdir_p!(lockdir)
      File.write!(Path.join(lockdir, "owner"), "dead-holder.#{round}")
      File.touch!(lockdir, {{2000, 1, 1}, {0, 0, 0}})

      parent = self()

      tasks =
        for i <- 1..@writers do
          Task.async(fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> :ok
            end

            PackLock.update(lock_path, fn l ->
              {:ok, PackLock.put(l, "p#{i}", %{"name" => "p#{i}", "sha256" => "x"})}
            end)
          end)
        end

      pids =
        for _ <- tasks do
          receive do
            {:ready, pid} -> pid
          end
        end

      Enum.each(pids, &send(&1, :go))
      Enum.each(tasks, fn t -> assert {:ok, _} = Task.await(t, 60_000) end)

      {:ok, lock} = PackLock.read(lock_path)

      assert lock["packs"] |> Map.keys() |> Enum.sort() ==
               Enum.map(1..@writers, &"p#{&1}") |> Enum.sort()

      refute File.exists?(lockdir)
    end
  end
end
