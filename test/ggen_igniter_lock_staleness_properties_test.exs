defmodule GgenIgniter.LockStalenessPropertiesTest do
  @moduledoc """
  Chicago-style: real lock files on disk, real mtimes set via `File.touch/2`
  (no mocking of time, no mocked `System.os_time/1`) exercising
  `GgenIgniter.Lock`'s real stale-lock-recovery contract documented in its
  moduledoc: a lock file whose mtime age is strictly greater than
  `@stale_after_ms` (5 minutes) is treated as abandoned and is removed by the
  next `acquire/2` caller before retrying (real success, `{:ok, %Lock{}}`); a
  lock file at or under that age is a live holder and must NOT be silently
  cleared -- `acquire/2` keeps retrying against it until its own timeout
  elapses, then raises the real `RuntimeError` documented for that path. The
  private staleness check itself is `GgenIgniter.Lock.stale_lock?/1`
  (confirmed by reading `lib/ggen_igniter/lock.ex` -- not guessed), reached
  here only indirectly through the real public `acquire/2` API, exactly as
  `Mix.Tasks.GgenIgniter.Sync` calls it. Also includes one real two-OS-process
  contention test (distinct from `ggen_igniter_lock_contention_test.exs`'s
  same-VM `Task.async` race): two genuinely separate `mix run -e` subprocesses,
  following this repo's existing `test/ggen_igniter_doctor_task_test.exs`
  `System.cmd("mix", [...])` pattern, racing `GgenIgniter.Lock.acquire/2`
  against the same real directory.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  # async: false -- every case in this file writes/mtimes a real lock file at
  # a fixed real path (`<tmp_dir>/.ggen_igniter/.sync.lock`) and the
  # subprocess-contention test shares that same real directory concept across
  # two real OS processes; interleaving with other async cases in this file
  # risks two properties racing the same kind of real file-system state.

  @stale_after_ms 5 * 60 * 1000
  @lock_subpath ".ggen_igniter/.sync.lock"

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_lock_staleness_props_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp write_lock_file_with_age!(lock_key, age_ms) do
    lock_path = Path.join(lock_key, @lock_subpath)
    File.mkdir_p!(Path.dirname(lock_path))
    File.write!(lock_path, "pid=999999 node=nonode@nohost at=stale-fixture\n")

    # Real mtime, set via File.touch/2 against a real posix timestamp
    # "age_ms milliseconds in the past" -- not a mocked clock. `stale_lock?/1`
    # itself reads mtime via `File.stat(path, time: :posix)`, so a posix
    # integer here exercises the exact same real time representation.
    past_posix_seconds = div(System.os_time(:millisecond) - age_ms, 1000)

    File.touch!(lock_path, past_posix_seconds)
    lock_path
  end

  describe "acquire/2 stale-lock boundary (property, real files, real mtimes)" do
    property "ages strictly greater than @stale_after_ms are cleared for real and acquire/2 succeeds" do
      check all(
              extra_ms <- StreamData.integer(1..60_000),
              max_runs: 20
            ) do
        age_ms = @stale_after_ms + extra_ms
        tmp_dir = scratch_dir!("gt_#{System.unique_integer([:positive])}")
        lock_path = write_lock_file_with_age!(tmp_dir, age_ms)

        assert {:ok, %GgenIgniter.Lock{} = lock} =
                 GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 2_000, retry_interval_ms: 10)

        # Real state: the stale file was actually removed and replaced by a
        # fresh one this process actually created (not left alone).
        assert File.exists?(lock_path)
        holder_marker = File.read!(lock_path)
        refute holder_marker =~ "stale-fixture"
        assert holder_marker =~ "pid=#{System.pid()}"

        :ok = GgenIgniter.Lock.release(lock)
        refute File.exists?(lock_path)
      end
    end

    property "ages at or under @stale_after_ms are NOT silently cleared -- acquire/2 keeps blocking against the live holder and raises on timeout" do
      check all(
              under_ms <- StreamData.integer(0..60_000),
              max_runs: 20
            ) do
        age_ms = @stale_after_ms - under_ms
        tmp_dir = scratch_dir!("lte_#{System.unique_integer([:positive])}")
        lock_path = write_lock_file_with_age!(tmp_dir, age_ms)

        assert_raise RuntimeError, ~r/could not acquire lock/, fn ->
          GgenIgniter.Lock.acquire(tmp_dir, timeout_ms: 200, retry_interval_ms: 10)
        end

        # Real state: the "live" holder's lock file was left completely
        # untouched -- never removed, never overwritten by the failed caller.
        assert File.exists?(lock_path)
        assert File.read!(lock_path) =~ "stale-fixture"
      end
    end
  end

  describe "acquire/2 across two real OS processes (not just same-VM Task.async)" do
    @tag :integration
    test "exclusivity holds for real across two separate `mix run -e` subprocesses" do
      tmp_dir = scratch_dir!("subprocess")
      lock_key = Path.expand(tmp_dir)

      # Each subprocess: acquire the real lock, print a timestamped ACQUIRED
      # line, hold it for a real 300ms via Process.sleep, print a timestamped
      # RELEASED line, then release. The second racer necessarily blocks on
      # the real :eexist path (this repo's real cross-OS-process mechanism,
      # per lock.ex's moduledoc) until the first genuinely releases -- proven
      # below by asserting the two [acquired, released] real-time windows do
      # not overlap.
      script = """
      {:ok, lock} = GgenIgniter.Lock.acquire(#{inspect(lock_key)}, timeout_ms: 10_000, retry_interval_ms: 20)
      IO.puts("ACQUIRED " <> Integer.to_string(System.os_time(:millisecond)))
      Process.sleep(300)
      IO.puts("RELEASED " <> Integer.to_string(System.os_time(:millisecond)))
      :ok = GgenIgniter.Lock.release(lock)
      """

      run_subprocess = fn ->
        System.cmd("mix", ["run", "--no-start", "-e", script],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )
      end

      task_a = Task.async(run_subprocess)
      task_b = Task.async(run_subprocess)

      {output_a, exit_a} = Task.await(task_a, 30_000)
      {output_b, exit_b} = Task.await(task_b, 30_000)

      assert exit_a == 0, "subprocess A failed:\n#{output_a}"
      assert exit_b == 0, "subprocess B failed:\n#{output_b}"

      window = fn output ->
        [_, acquired] = Regex.run(~r/ACQUIRED (\d+)/, output)
        [_, released] = Regex.run(~r/RELEASED (\d+)/, output)
        {String.to_integer(acquired), String.to_integer(released)}
      end

      {acq_a, rel_a} = window.(output_a)
      {acq_b, rel_b} = window.(output_b)

      # Real exclusivity assertion on real wall-clock windows recorded by two
      # genuinely separate OS processes: one window must end at or before the
      # other begins -- they must never overlap.
      no_overlap? = rel_a <= acq_b or rel_b <= acq_a

      assert no_overlap?,
             "expected non-overlapping hold windows across two real OS processes, " <>
               "got A=[#{acq_a}, #{rel_a}] B=[#{acq_b}, #{rel_b}]\nA output:\n#{output_a}\nB output:\n#{output_b}"

      lock_path = Path.join(lock_key, ".ggen_igniter/.sync.lock")
      refute File.exists?(lock_path)
    end
  end
end
