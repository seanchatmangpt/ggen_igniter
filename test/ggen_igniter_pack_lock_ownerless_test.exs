defmodule GgenIgniter.PackLockOwnerlessTest do
  @moduledoc """
  Chicago-style: real tmp dir and real lockdirs on disk. An ownerless lockdir
  (holder died between mkdir and the token write) is reclaimed only when stale
  by mtime; fresh ownerless and live-owned lockdirs are never touched.
  async: false because the tests share the process-global monotonic deadline
  behavior of a real filesystem lock.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.PackLock

  defp put_fun(l), do: {:ok, PackLock.put(l, "p", %{"name" => "p", "sha256" => "x"})}

  @tag :tmp_dir
  test "aged ownerless lockdir is reclaimed and update succeeds", %{tmp_dir: tmp} do
    lock_path = Path.join(tmp, "ggen_igniter.pack.lock")
    lockdir = lock_path <> ".lockdir"
    File.mkdir_p!(lockdir)
    File.touch!(lockdir, {{2000, 1, 1}, {0, 0, 0}})

    assert {:ok, _} = PackLock.update(lock_path, [timeout_ms: 5_000], &put_fun/1)
    assert {:ok, lock} = PackLock.read(lock_path)
    assert Map.has_key?(lock["packs"], "p")
    refute File.exists?(lockdir)
    refute File.exists?(lockdir <> ".breaker")
  end

  @tag :tmp_dir
  test "fresh ownerless lockdir is not reclaimed", %{tmp_dir: tmp} do
    lock_path = Path.join(tmp, "ggen_igniter.pack.lock")
    lockdir = lock_path <> ".lockdir"
    File.mkdir_p!(lockdir)

    assert_raise RuntimeError, ~r/pack lock busy/, fn ->
      PackLock.update(lock_path, [timeout_ms: 150], &put_fun/1)
    end

    assert File.dir?(lockdir)
    refute File.exists?(lock_path)
  end

  @tag :tmp_dir
  test "fresh live-owned lockdir is untouched", %{tmp_dir: tmp} do
    lock_path = Path.join(tmp, "ggen_igniter.pack.lock")
    lockdir = lock_path <> ".lockdir"
    File.mkdir_p!(lockdir)
    File.write!(Path.join(lockdir, "owner"), "live-holder")

    assert_raise RuntimeError, ~r/pack lock busy/, fn ->
      PackLock.update(lock_path, [timeout_ms: 150], &put_fun/1)
    end

    assert File.read!(Path.join(lockdir, "owner")) == "live-holder"
  end
end
