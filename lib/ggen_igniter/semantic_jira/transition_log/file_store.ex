defmodule GgenIgniter.SemanticJira.TransitionLog.FileStore do
  @moduledoc """
  File-backed `GgenIgniter.SemanticJira.TransitionLog.Store`: one immutable
  JSON file per event, named `<seq>-<event_digest>.json` under a caller-given
  directory (the store's ref). This is the original `TransitionLog`
  implementation moved behind the storage behaviour; the on-disk layout is
  unchanged.

  - `append/3` is safe under concurrent writers: a per-digest and a per-seq
    exclusive-create claim make each event and each `seq` single-owner, and
    the event file appears atomically (temp file + rename). An event whose
    `event_digest` is already present is returned unchanged (idempotent).
    Existing files are never rewritten. A writer that crashes after claiming
    a seq leaves a gap, never a duplicate.
  - `expected_seq: n` (optimistic concurrency) claims exactly `n` or returns
    `{:error, {:seq_conflict, head}}`. A strict writer that loses the seq race
    releases its digest claim; every duplicate writer waiting on that claim
    re-enters the claim protocol (it never treats "a claim exists" as "the
    event will appear"), so each gets the stored event or its own
    `seq_conflict`.
  - `append/3` never returns a nil event. A digest claim orphaned by a writer
    killed before it wrote its file (`kill -9`) is detected by the waiters
    (the claim file's mtime does not change for `claim_stale_ms`, default
    5000 ms and at least 1000 ms because mtimes have one-second resolution;
    the owner touches it while it searches for a free seq) and taken over
    under a `.takeover` lock. Before publishing, an owner re-checks
    that no other writer already stored the digest. Residual, not claimed
    away: an owner suspended for longer than `claim_stale_ms` between that
    re-check and its rename can still publish a duplicate.
  - `list/1` and `stream/1` return events ordered by `seq`.
  """

  @behaviour GgenIgniter.SemanticJira.TransitionLog.Store

  alias GgenIgniter.SemanticJira.TransitionLog.Store

  @stale_ms 5_000
  # File mtimes have one-second resolution: below this a claim re-created by a
  # takeover could be mistaken for the stale one it replaced.
  @min_stale_ms 1_000
  @poll_ms 10

  @impl true
  def list(dir), do: dir |> stream() |> Enum.to_list()

  @impl true
  def stream(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Stream.map(&(dir |> Path.join(&1) |> File.read!() |> Jason.decode!()))

      {:error, :enoent} ->
        []
    end
  end

  @impl true
  def get(dir, digest) do
    suffix = "-#{String.slice(digest, 7, 16)}.json"

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, suffix))
        |> Enum.sort()
        |> Enum.find_value(:error, &read_if_digest(Path.join(dir, &1), digest))

      {:error, :enoent} ->
        :error
    end
  end

  defp read_if_digest(path, digest) do
    event = path |> File.read!() |> Jason.decode!()
    if event["event_digest"] == digest, do: {:ok, event}
  end

  @impl true
  def head(dir) do
    case File.ls(dir) do
      {:ok, _} -> next_seq(dir) - 1
      {:error, :enoent} -> 0
    end
  end

  @impl true
  def append(dir, event, opts \\ []) do
    with :ok <- Store.admit(event) do
      File.mkdir_p!(dir)
      event = Map.put(event, "event_digest", Store.event_digest(event))

      ctx = %{
        expected: Keyword.get(opts, :expected_seq),
        stale_ms: max(Keyword.get(opts, :claim_stale_ms, @stale_ms), @min_stale_ms)
      }

      attempt(dir, event, ctx)
    end
  end

  # One pass through the claim protocol. Every path that finds the digest
  # claimed but unfinished comes back here (`await/4`), so a released or taken
  # over claim is re-claimed instead of being reported as recorded.
  defp attempt(dir, event, ctx) do
    case get(dir, event["event_digest"]) do
      {:ok, existing} -> {:ok, existing, :already_recorded}
      :error -> claim(dir, event, ctx)
    end
  end

  # Optimistic path: the caller names the seq it expects to claim. A stale
  # expectation is refused before anything is claimed.
  defp claim(dir, event, %{expected: nil} = ctx), do: claim_digest(dir, event, ctx)

  defp claim(dir, event, %{expected: expected} = ctx) when is_integer(expected) do
    head = head(dir)

    if expected == head + 1 do
      claim_digest(dir, event, ctx)
    else
      {:error, {:seq_conflict, head}}
    end
  end

  # Two exclusive-create claims make concurrent writers safe: a per-digest
  # claim (one writer owns an event; duplicates wait for its file) and a
  # per-seq claim (one writer owns a seq). The event file itself is written to
  # a temp name and renamed, so readers never observe a partial file.
  defp claim_digest(dir, event, ctx) do
    marker = marker_path(dir, event)

    case File.open(marker, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        own(dir, event, ctx, marker)

      {:error, :eexist} ->
        await(dir, event, ctx, watch(marker))
    end
  end

  # The owner of a digest claim either stores the event or releases the claim;
  # an exception must not leave a claim behind that no one will ever finish.
  defp own(dir, event, ctx, marker) do
    write(dir, event, ctx.expected || next_seq(dir), ctx.expected != nil, marker)
  rescue
    error ->
      File.rm(marker)
      reraise error, __STACKTRACE__
  end

  defp marker_path(dir, event),
    do: Path.join(dir, "digest-#{String.slice(event["event_digest"], 7, 64)}.claim")

  # A duplicate writer waits for the claim's owner. It returns only a stored
  # event, and otherwise re-enters the protocol when the claim is released
  # (strict loser) or goes stale (crashed owner).
  defp await(dir, event, ctx, {marker, _, _} = seen) do
    case find(dir, event["event_digest"]) do
      nil ->
        if File.exists?(marker) do
          await_owner(dir, event, ctx, observe(seen))
        else
          attempt(dir, event, ctx)
        end

      existing ->
        {:ok, existing, :already_recorded}
    end
  end

  defp await_owner(dir, event, ctx, {_marker, _mtime, since} = seen) do
    if System.monotonic_time(:millisecond) - since >= ctx.stale_ms do
      takeover(dir, event, ctx, seen)
    else
      Process.sleep(@poll_ms)
      await(dir, event, ctx, seen)
    end
  end

  # `{marker, mtime, since}`: the claim's mtime as last observed and the
  # (monotonic) time it was first observed unchanged. An owner that is still
  # working touches the claim, which resets the clock.
  defp watch(marker), do: {marker, mtime(marker), System.monotonic_time(:millisecond)}

  defp observe({marker, mtime, since}) do
    case mtime(marker) do
      ^mtime -> {marker, mtime, since}
      changed -> {marker, changed, System.monotonic_time(:millisecond)}
    end
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  # Takes over a claim nobody has touched for `stale_ms`. Serialised by an
  # exclusive `.takeover` lock and re-checked under it, so only one waiter
  # removes the stale claim and a claim that was meanwhile re-created (fresh
  # mtime) is left alone.
  defp takeover(dir, event, ctx, {marker, stale_mtime, _since} = seen) do
    lock = marker <> ".takeover"

    case File.open(lock, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)

        try do
          if find(dir, event["event_digest"]) == nil and mtime(marker) == stale_mtime,
            do: File.rm(marker)
        after
          File.rm(lock)
        end

        attempt(dir, event, ctx)

      {:error, :eexist} ->
        drop_stale_lock(lock, ctx.stale_ms)
        Process.sleep(@poll_ms)
        await(dir, event, ctx, seen)
    end
  end

  # The lock itself can be orphaned by a waiter killed mid-takeover.
  defp drop_stale_lock(lock, stale_ms) do
    case mtime(lock) do
      nil -> :ok
      mtime -> if System.os_time(:second) - mtime > div(stale_ms, 1000) + 1, do: File.rm(lock)
    end
  end

  defp find(dir, digest) do
    case get(dir, digest) do
      {:ok, event} -> event
      :error -> nil
    end
  end

  defp next_seq(dir) do
    claims =
      dir
      |> File.ls!()
      |> Enum.count(&(String.starts_with?(&1, "seq-") and String.ends_with?(&1, ".claim")))

    max(claims, length(list(dir))) + 1
  end

  defp write(dir, event, seq, strict?, marker) do
    pad = String.pad_leading(Integer.to_string(seq), 8, "0")

    case File.open(Path.join(dir, "seq-#{pad}.claim"), [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        publish(dir, Map.put(event, "seq", seq), pad)

      {:error, :eexist} when strict? ->
        # Lost the optimistic race for exactly this seq: nothing was stored,
        # so release the digest claim (waiting duplicates re-enter the claim
        # protocol) and report the observed head.
        File.rm(marker)
        {:error, {:seq_conflict, head(dir)}}

      {:error, :eexist} ->
        # still working: keep the claim's mtime fresh for the waiters
        File.touch(marker)
        write(dir, event, seq + 1, strict?, marker)
    end
  end

  defp publish(dir, stamped, pad) do
    name = "#{pad}-#{String.slice(stamped["event_digest"], 7, 16)}.json"
    tmp = Path.join(dir, ".tmp-#{pad}-#{System.unique_integer([:positive])}.tmp")
    File.write!(tmp, Jason.encode!(stamped))

    # A waiter may have taken this claim over while we were suspended and
    # stored the event already; do not store it twice.
    case find(dir, stamped["event_digest"]) do
      nil ->
        File.rename!(tmp, Path.join(dir, name))
        {:ok, stamped, :appended}

      existing ->
        File.rm(tmp)
        {:ok, existing, :already_recorded}
    end
  end
end
