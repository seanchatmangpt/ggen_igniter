defmodule GgenIgniter.LockNodeRestartPidReuseTest do
  @moduledoc """
  Chicago-style: real lock files on disk, real `self()`/`Node.self()`/
  `:erlang.system_info(:creation)` values -- no mocking. Exercises the fix for
  the disclosed gap in `GgenIgniter.Lock.holder_pid_status/1`: the printed
  `<A.B.C>` pid text alone cannot distinguish "the same BEAM incarnation that
  wrote this marker" from "a later incarnation of a node with the same name
  whose process table reused that same slot for something else." The fix adds
  a `creation=` field (Erlang's own per-incarnation counter) to the marker and
  requires it to match the CURRENT node's creation before trusting
  `Process.alive?/1`.

  This test cannot literally restart the BEAM mid-test (that would kill the
  test runner), so it exercises the real, disclosed decision boundary
  directly: a lock file whose `creation=` field does not match this node's
  real, current `:erlang.system_info(:creation)` value must resolve to
  `:unknown` (never `:alive`), even when its `erlang_pid=` names a genuinely,
  currently-alive process (this very test process) and its `node=` matches
  `Node.self()` exactly -- proving the creation check, not just the node
  check, gates the `:alive` answer. This is exactly the scenario a real node
  restart under the same `--sname`/`--name` produces: same node name, stale
  creation, a reused pid slot that now belongs to something unrelated.
  """

  use ExUnit.Case, async: false

  @lock_subpath ".ggen_igniter/.sync.lock"

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_lock_pid_reuse_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp write_marker!(lock_key, content) do
    lock_path = Path.join(lock_key, @lock_subpath)
    File.mkdir_p!(Path.dirname(lock_path))
    File.write!(lock_path, content)
    lock_path
  end

  test "matching node= and matching creation=, live erlang_pid= resolves :alive (real control case)" do
    tmp_dir = scratch_dir!("match")
    real_creation = :erlang.system_info(:creation)

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=#{real_creation} " <>
          "erlang_pid=#{inspect(self())} at=control\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :alive
  end

  test "matching node= but a STALE creation= (simulated post-restart pid-slot reuse) resolves :unknown, never :alive" do
    tmp_dir = scratch_dir!("stale_creation")
    real_creation = :erlang.system_info(:creation)
    # A creation value that is real (an integer, well-formed) but genuinely
    # NOT this node's current one -- the exact shape a marker written by a
    # prior, now-restarted BEAM incarnation of the same node name would have.
    stale_creation = real_creation + 1

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=#{stale_creation} " <>
          "erlang_pid=#{inspect(self())} at=stale-incarnation\n"
      )

    # self() is genuinely alive right now -- if the creation check were
    # missing (the pre-fix behavior), this would falsely resolve :alive
    # exactly as the reported gap describes. The fix must resolve :unknown
    # instead, falling back to mtime-age rather than trusting a stale
    # incarnation's pid-slot claim.
    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :unknown
  end

  test "matching node=, missing creation= entirely (marker predating this fix) resolves :unknown, not :alive" do
    tmp_dir = scratch_dir!("no_creation_field")

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} erlang_pid=#{inspect(self())} at=old-format\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :unknown
  end

  test "stale-creation marker falls back to real mtime-age via stale_lock?/1 (fresh mtime -> not stale)" do
    tmp_dir = scratch_dir!("fallback_fresh")
    real_creation = :erlang.system_info(:creation)

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=#{real_creation + 1} " <>
          "erlang_pid=#{inspect(self())} at=stale-incarnation\n"
      )

    # Real, fresh mtime (just written) -- :unknown liveness falls back to
    # mtime-age, and a fresh file is not old enough to be reclaimable yet.
    refute GgenIgniter.Lock.stale_lock?(lock_path)
  end

  test "stale-creation marker falls back to real mtime-age via stale_lock?/1 (old mtime -> stale, reclaimable)" do
    tmp_dir = scratch_dir!("fallback_old")
    real_creation = :erlang.system_info(:creation)

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=#{real_creation + 1} " <>
          "erlang_pid=#{inspect(self())} at=stale-incarnation\n"
      )

    six_minutes_ago = div(System.os_time(:millisecond) - 6 * 60 * 1000, 1000)
    File.touch!(lock_path, six_minutes_ago)

    # Real mtime-age fallback: with liveness :unknown (stale creation) and a
    # real mtime older than @stale_after_ms, the lock is reclaimable -- the
    # pid-reuse guard must not permanently wedge acquisition, it must hand
    # off to the real mtime signal.
    assert GgenIgniter.Lock.stale_lock?(lock_path)
  end

  test "matching node= and creation= but a malformed erlang_pid= (regex-matching, list_to_pid-rejecting) resolves :unknown, never raises" do
    tmp_dir = scratch_dir!("malformed_pid")
    real_creation = :erlang.system_info(:creation)

    # "<0.999999999.0>" satisfies the erlang_pid= regex (digits and dots
    # inside <...>) but :erlang.list_to_pid/1 rejects it with ArgumentError
    # because 999999999 is out of range for the serial field on this node --
    # this is the real rescue clause in parse_erlang_pid/1 that every other
    # test in this file bypasses by always supplying inspect(self()).
    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=#{real_creation} " <>
          "erlang_pid=#PID<0.999999999.0> at=malformed-pid\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :unknown
  end
end
