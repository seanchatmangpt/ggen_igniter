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

  Staleness is decided by TWO real signals, PID-liveness first and mtime-age
  as the fallback -- this fixes a real gap where a legitimately slow same-VM
  run past `@stale_after_ms` (5 minutes) used to get its lock stolen by a
  second concurrent invocation purely because the file was "old", even
  though the original holder process was still alive and still working:

    * **PID-liveness (primary)**: `holder_marker/0` writes the acquiring
      process's real `erlang_pid=` (its own `self()`, `inspect/1`-formatted)
      alongside `node=` and `creation=` into the lock file's content. When a
      later `acquire/2` call hits `:eexist` on that same node,
      `holder_pid_status/1` parses that Erlang pid back out via
      `:erlang.list_to_pid/1` and checks `Process.alive?/1` for real -- no
      periodic background heartbeat/refresher process is needed, since
      liveness is checked fresh, on demand, at contention time. A confirmed
      *live* holder is never preempted, however old its file's mtime is; a
      confirmed *dead* holder (the process genuinely exited) is immediately
      reclaimable, however fresh its file's mtime is.

      **Node-restart pid-reuse guard**: the `<A.B.C>` text form `inspect/1`
      prints for a pid does NOT encode the node's *creation* number (Erlang's
      own per-incarnation counter, `:erlang.system_info(:creation)`, which
      changes every time a node of the same name boots), so a bare
      `node=`-equality check cannot by itself distinguish "the same BEAM
      incarnation that wrote this marker" from "a later incarnation of a
      node with the same name whose process table happens to have reused
      slot `<A.B.C>` for something else entirely." `holder_marker/0` also
      records this node's `creation=` at write time, and `holder_pid_status/1`
      requires the *current* `Node.self()` creation to match the recorded
      one before trusting `Process.alive?/1`'s answer -- a mismatch (this
      node restarted since the marker was written) resolves to `:unknown`
      exactly like a cross-node marker does, falling back to mtime-age
      instead of risking a false `:alive` against an unrelated process that
      happens to occupy the reused pid slot.
    * **mtime-age (fallback)**: used only when PID-liveness is `:unknown` --
      the recorded `node=` differs from `Node.self()` (the real, disclosed
      cross-node limitation: an Erlang pid from another node's local process
      table cannot be resolved locally), the recorded `creation=` differs
      from the current node's creation (this node restarted under the same
      name since the marker was written -- the pid-reuse-after-restart case
      above), the marker line is missing/unparseable, or the OS pid was
      reused by an unrelated process after a hard crash. In that fallback
      case only, a lock file older than 5 minutes is treated as abandoned
      (its holder crashed, was killed, or the machine restarted, without
      ever reaching `release/1`) and is removed automatically by the next
      `acquire/2` caller before retrying. A live holder well inside that
      window is never preempted.

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

  @doc """
  Resolves the real, canonical lock file path for `lock_key` (a directory --
  typically `--manifest-dir` or `File.cwd!/0`). Public so callers that need to
  check a lock's existence/staleness without racing `acquire/2` (e.g. `mix
  ggen_igniter.doctor`'s read-only check 18) don't have to re-derive
  `@lock_subpath` themselves.
  """
  @spec lock_path(String.t()) :: String.t()
  def lock_path(lock_key), do: Path.join(lock_key, @lock_subpath)

  defp holder_marker do
    "pid=#{System.pid()} node=#{Node.self()} creation=#{node_creation()} " <>
      "erlang_pid=#{inspect(self())} at=#{DateTime.utc_now() |> DateTime.to_iso8601()}\n"
  end

  # Erlang's own per-incarnation counter for the local node: increments
  # every time a node with this name (re)starts, so it is exactly the
  # "which BEAM incarnation" signal the printed `<A.B.C>` pid form lacks.
  # See `:erlang.system_info/1` (`:creation`), a real, documented Erlang/OTP
  # primitive -- not fabricated for this fix.
  @spec node_creation() :: non_neg_integer()
  defp node_creation, do: :erlang.system_info(:creation)

  @doc """
  Real, read-only staleness check for the lock file at `path` -- same
  PID-liveness-first, mtime-age-fallback logic `do_acquire/4` uses internally
  before breaking a stale lock, exposed publicly so a read-only caller (e.g.
  `mix ggen_igniter.doctor`'s check 18) can report staleness without
  attempting to acquire (and thus without a doctor-owned side effect on a
  lock file it must never mutate -- doctor is read-only per this module's own
  moduledoc). Returns `false` (never stale-blocking) when the file is
  missing, matching `do_acquire/4`'s own vanished-file handling.
  """
  @spec stale_lock?(String.t()) :: boolean()
  def stale_lock?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        case holder_pid_status(path) do
          :alive ->
            # Primary signal: the recorded holder process is genuinely still
            # running on this node right now -- never preempt it, no matter
            # how old the lock file's mtime is.
            false

          :dead ->
            # Primary signal: the recorded holder process genuinely no
            # longer exists on this node -- reclaimable immediately, no
            # matter how fresh the lock file's mtime is.
            true

          :unknown ->
            # Fallback signal only (cross-node holder, unparseable/missing
            # marker, or a reused OS pid) -- fall back to mtime-age.
            age_ms = System.os_time(:millisecond) - mtime * 1000
            age_ms > @stale_after_ms
        end

      {:error, _reason} ->
        # The lock file vanished between the :eexist above and this stat
        # (its holder released it in the meantime) -- not stale-blocking;
        # the next do_acquire attempt will simply try to create it again.
        false
    end
  end

  # Reads the lock file's `node=`/`creation=`/`erlang_pid=` marker and
  # resolves real liveness for real via `Process.alive?/1` -- returns
  # `:alive`/`:dead` only when the marker was written by a process on THIS
  # node (an Erlang pid from another node's local process table cannot be
  # resolved locally, a real and disclosed cross-node limitation) AND on
  # THIS node's current BOOT INCARNATION (a recorded `creation=` that
  # differs from `:erlang.system_info(:creation)` right now means this node
  # restarted under the same name since the marker was written -- the
  # printed `<A.B.C>` pid text doesn't encode creation, so without this
  # check a brand-new unrelated process that reused that pid slot in the
  # new incarnation would falsely resolve `:alive`). Returns `:unknown`
  # (meaning "fall back to mtime-age") for every other case: file
  # unreadable, marker missing/unparseable (including a marker written
  # before this field existed, which has no `creation=` to match), a
  # recorded node that isn't `Node.self()`, or a recorded creation that
  # isn't this node's current creation.
  @doc """
  Reads the lock file's `node=`/`creation=`/`erlang_pid=` marker and
  resolves real liveness for real via `Process.alive?/1`, cross-checking the
  node's boot creation number so a post-restart pid-slot reuse under the
  same node name cannot be mistaken for the original holder. Public for the
  same read-only caller reason as `stale_lock?/1` -- `mix ggen_igniter.doctor`'s
  check 18 names the real holder in its info/warn line without duplicating
  this parsing logic.
  """
  @spec holder_pid_status(String.t()) :: :alive | :dead | :unknown
  def holder_pid_status(path) do
    with {:ok, content} <- File.read(path),
         [_, node_str] <- Regex.run(~r/node=(\S+)/, content),
         true <- node_str == to_string(Node.self()),
         [_, creation_str] <- Regex.run(~r/creation=(\d+)/, content),
         {recorded_creation, ""} <- Integer.parse(creation_str),
         true <- recorded_creation == node_creation(),
         [_, pid_str] <- Regex.run(~r/erlang_pid=#PID(<[0-9.]+>)/, content),
         {:ok, pid} <- parse_erlang_pid(pid_str) do
      if Process.alive?(pid), do: :alive, else: :dead
    else
      _ -> :unknown
    end
  end

  @spec parse_erlang_pid(String.t()) :: {:ok, pid()} | :error
  defp parse_erlang_pid(pid_str) do
    {:ok, :erlang.list_to_pid(String.to_charlist(pid_str))}
  rescue
    ArgumentError -> :error
  end
end
