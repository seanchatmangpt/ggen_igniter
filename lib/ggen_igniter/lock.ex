defmodule GgenIgniter.Lock do
  @moduledoc """
  A real, file-based cross-process lock used by `mix ggen_igniter.sync` (see
  `Mix.Tasks.GgenIgniter.Sync`'s AR-9 correction, 2026-08-27) to serialize
  concurrent mutating invocations against the same target project. Per the
  PRD's FR-5 (see `Mix.Tasks.GgenIgniter.Plan`'s moduledoc, "Read-only, no
  lock"), only verbs that mutate a target project's filesystem
  (`mix ggen_igniter.sync`, `mix ggen_igniter.replay`) acquire this lock --
  `mix ggen_igniter.doctor` and `mix ggen_igniter.plan` are both read-only and
  must never call `acquire/2`.

  ## Mechanism

  A real lock FILE (`.ggen_igniter/.sync.lock`, under the caller's
  `lock_key` directory -- typically `--manifest-dir` or `File.cwd!/0`),
  created with `File.open/2`'s `:exclusive` mode -- the OS itself refuses a
  second concurrent `:exclusive` open against the same path, so two BEAM
  processes (or two separate `mix` invocations, which is the real scenario
  this exists for -- not two processes in the same VM) genuinely cannot both
  win the race. This is not an in-memory/`:global`/`GenServer`-registered
  lock: those only serialize callers inside the SAME BEAM node, which is not
  what "two concurrent `mix ggen_igniter.sync` invocations" actually are.

  ## Stale-lock recovery

  A lock file older than 5 minutes is
  treated as abandoned (its holder crashed, was killed, or the machine
  restarted, without ever reaching `release/1`) and is removed automatically
  by the next `acquire/2` caller before retrying -- a crashed prior holder
  must never permanently wedge every future `mix ggen_igniter.sync` run. A
  live holder well inside that window is never preempted.

  ## Real functions, no mock anywhere in this chain

    * `acquire/2` -- blocks (retrying on a real interval) until the real lock
      file is created or `opts[:timeout_ms]` elapses, then raises a
      `RuntimeError` naming the still-held lock path. Returns
      `{:ok, %__MODULE__{}}` on success -- the ref `release/1` requires.
    * `release/1` -- deletes the real lock file. Idempotent: releasing a lock
      whose file was already removed (e.g. cleaned up out-of-band) is a
      no-op, never a raise, since every real call site (`Mix.Tasks.GgenIgniter.Sync`'s
      `try/after`) needs "leave nothing held" to succeed unconditionally.
  """

  @enforce_keys [:path, :key]
  defstruct [:path, :key]

  @type t :: %__MODULE__{path: String.t(), key: String.t()}

  @lock_subpath ".ggen_igniter/.sync.lock"
  @default_timeout_ms 30_000
  @default_retry_interval_ms 50
  @stale_after_ms 5 * 60 * 1000

  @doc """
  Acquires the real cross-process lock for `lock_key` (a directory path --
  typically `--manifest-dir` or `File.cwd!/0`). Blocks, retrying every
  `opts[:retry_interval_ms]` (default 50ms), until either the lock file is
  genuinely created by THIS process or `opts[:timeout_ms]` (default
  30000ms) elapses -- at which point it raises a `RuntimeError` naming the
  still-held lock path, rather than returning a value the existing
  `{:ok, lock_ref} = acquire(...)` call sites do not pattern-match against.

  Returns `{:ok, t()}` on success.
  """
  @spec acquire(String.t(), keyword()) :: {:ok, t()}
  def acquire(lock_key, opts \\ []) when is_binary(lock_key) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    retry_interval_ms = Keyword.get(opts, :retry_interval_ms, @default_retry_interval_ms)

    path = lock_path(lock_key)
    File.mkdir_p!(Path.dirname(path))

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_acquire(path, lock_key, deadline, retry_interval_ms)
  end

  defp do_acquire(path, lock_key, deadline, retry_interval_ms) do
    case File.open(path, [:write, :exclusive]) do
      {:ok, io} ->
        IO.write(io, holder_marker())
        File.close(io)
        {:ok, %__MODULE__{path: path, key: lock_key}}

      {:error, :eexist} ->
        if stale_lock?(path) do
          # A prior holder never reached `release/1` (crash, kill, machine
          # restart) -- break the stale lock and retry immediately rather
          # than waiting out the rest of the timeout against a lock nobody
          # still holds.
          File.rm(path)
          do_acquire(path, lock_key, deadline, retry_interval_ms)
        else
          if System.monotonic_time(:millisecond) >= deadline do
            raise RuntimeError,
                  "GgenIgniter.Lock: could not acquire lock #{inspect(path)} within timeout " <>
                    "-- another mutating ggen_igniter invocation appears to be running " <>
                    "against #{inspect(lock_key)}"
          else
            Process.sleep(retry_interval_ms)
            do_acquire(path, lock_key, deadline, retry_interval_ms)
          end
        end

      {:error, reason} ->
        raise RuntimeError,
              "GgenIgniter.Lock: could not create lock file #{inspect(path)}: #{inspect(reason)}"
    end
  end

  @doc """
  Releases a previously-acquired lock by deleting its real lock file.
  Idempotent -- a lock file already missing (removed out-of-band, or by a
  stale-lock recovery elsewhere) is treated as already-released, never a
  raise.
  """
  @spec release(t()) :: :ok
  def release(%__MODULE__{path: path}) do
    File.rm(path)
    :ok
  end

  defp lock_path(lock_key), do: Path.join(lock_key, @lock_subpath)

  defp holder_marker do
    "pid=#{System.pid()} node=#{Node.self()} at=#{DateTime.utc_now() |> DateTime.to_iso8601()}\n"
  end

  defp stale_lock?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        age_ms = System.os_time(:millisecond) - mtime * 1000
        age_ms > @stale_after_ms

      {:error, _reason} ->
        # The lock file vanished between the :eexist above and this stat
        # (its holder released it in the meantime) -- not stale-blocking;
        # the next do_acquire attempt will simply try to create it again.
        false
    end
  end
end
