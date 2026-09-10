defmodule GgenIgniter.LockOsPidLivenessTest do
  @moduledoc """
  Chicago-style: real lock files on disk, real OS processes (this test
  runner's own `System.pid()`, and a real short-lived `sh` subprocess spawned
  via `System.cmd/3`) -- no mocking of `System.cmd/3`, `File`, or any
  liveness primitive.

  Replaces `ggen_igniter_lock_node_restart_pid_reuse_test.exs`, which
  exercised the OLD, broken design: `holder_pid_status/1` parsing an
  `erlang_pid=` marker and calling `Process.alive?/1` on it, gated by a
  `node=`/`creation=` equality check. That design is wrong for this module's
  own disclosed primary scenario (two separate `mix` invocations -- two
  separate OS processes/BEAM VMs): `Process.alive?/1` only ever inspects the
  CALLING VM's own local process table, and for ordinary (non-`--sname`/
  `--name`) `mix` invocations `Node.self()` is always `:nonode@nohost` and
  `:erlang.system_info(:creation)` is a fixed value for every non-distributed
  BEAM boot -- so the node/creation guard trivially "matched" between any two
  real, separate `mix` invocations and never actually gated anything.

  The fix: `holder_pid_status/1` now resolves liveness via a real `kill -0`
  probe against the marker's `pid=` field (the real OS pid recorded via
  `System.pid()` at write time), which genuinely and portably identifies the
  same holder across OS processes and BEAM VMs on one machine.
  """

  use ExUnit.Case, async: false

  @lock_subpath ".ggen_igniter/.sync.lock"

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_lock_os_pid_#{tag}_#{System.unique_integer([:positive])}"
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

  test "a marker naming this test runner's real, genuinely-alive OS pid resolves :alive" do
    tmp_dir = scratch_dir!("alive")

    # System.pid/0 is the real OS pid of the BEAM VM running this very test
    # -- unambiguously alive right now, by construction.
    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=0 " <>
          "erlang_pid=#{inspect(self())} at=alive-control\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :alive
  end

  test "a marker naming a real OS pid that has genuinely already exited resolves :dead" do
    tmp_dir = scratch_dir!("dead")

    # A real, separate OS process (`sh -c 'echo $$'`) whose pid we capture --
    # by the time System.cmd/3 returns synchronously, that real subprocess
    # has genuinely exited, so its pid names a real, dead process (barring
    # the astronomically unlikely case of immediate pid reuse on a busy
    # host, which would make this assertion flaky, not wrong).
    {pid_output, 0} = System.cmd("sh", ["-c", "echo $$"])
    dead_os_pid = String.trim(pid_output)

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{dead_os_pid} node=#{Node.self()} creation=0 " <>
          "erlang_pid=#{inspect(self())} at=dead-control\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :dead
  end

  test "a marker with no pid= field resolves :unknown (falls back to mtime-age)" do
    tmp_dir = scratch_dir!("no_pid_field")

    lock_path =
      write_marker!(
        tmp_dir,
        "node=#{Node.self()} creation=0 erlang_pid=#{inspect(self())} at=missing-pid\n"
      )

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :unknown
  end

  test "an unreadable/missing lock file resolves :unknown" do
    tmp_dir = scratch_dir!("missing_file")
    lock_path = Path.join(tmp_dir, @lock_subpath)
    refute File.exists?(lock_path)

    assert GgenIgniter.Lock.holder_pid_status(lock_path) == :unknown
  end

  test "stale_lock?/1 reclaims immediately when the real recorded OS pid has died, regardless of a fresh mtime" do
    tmp_dir = scratch_dir!("stale_dead_fresh_mtime")

    {pid_output, 0} = System.cmd("sh", ["-c", "echo $$"])
    dead_os_pid = String.trim(pid_output)

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{dead_os_pid} node=#{Node.self()} creation=0 " <>
          "erlang_pid=#{inspect(self())} at=dead-fresh\n"
      )

    # Marker was just written -- mtime is genuinely fresh. If mtime-age were
    # the only signal, this would NOT be stale. PID-liveness (real, dead OS
    # pid) must win and report stale immediately.
    assert GgenIgniter.Lock.stale_lock?(lock_path)
  end

  test "stale_lock?/1 refuses to reclaim a lock naming a real, genuinely-alive OS pid, even with an old mtime" do
    tmp_dir = scratch_dir!("alive_old_mtime")

    lock_path =
      write_marker!(
        tmp_dir,
        "pid=#{System.pid()} node=#{Node.self()} creation=0 " <>
          "erlang_pid=#{inspect(self())} at=alive-old\n"
      )

    six_minutes_ago = div(System.os_time(:millisecond) - 6 * 60 * 1000, 1000)
    File.touch!(lock_path, six_minutes_ago)

    refute GgenIgniter.Lock.stale_lock?(lock_path)
  end
end
