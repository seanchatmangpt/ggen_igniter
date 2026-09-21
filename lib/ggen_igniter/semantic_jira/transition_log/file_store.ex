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
    `{:error, {:seq_conflict, head}}`; a losing strict writer releases its
    digest claim so a later append of the same event can still succeed.
  - `list/1` and `stream/1` return events ordered by `seq`.
  """

  @behaviour GgenIgniter.SemanticJira.TransitionLog.Store

  alias GgenIgniter.SemanticJira

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
    File.mkdir_p!(dir)
    event = Map.put(event, "event_digest", SemanticJira.digest(Map.delete(event, "seq")))

    case get(dir, event["event_digest"]) do
      :error -> claim(dir, event, Keyword.get(opts, :expected_seq))
      {:ok, existing} -> {:ok, existing, :already_recorded}
    end
  end

  # Optimistic path: the caller names the seq it expects to claim. A stale
  # expectation is refused before anything is claimed.
  defp claim(dir, event, nil), do: claim_digest(dir, event, nil)

  defp claim(dir, event, expected) when is_integer(expected) do
    head = head(dir)

    if expected == head + 1 do
      claim_digest(dir, event, expected)
    else
      {:error, {:seq_conflict, head}}
    end
  end

  # Two exclusive-create claims make concurrent writers safe: a per-digest
  # claim (one writer owns an event; duplicates wait for its file) and a
  # per-seq claim (one writer owns a seq). The event file itself is written to
  # a temp name and renamed, so readers never observe a partial file.
  defp claim_digest(dir, event, expected) do
    marker = Path.join(dir, "digest-#{String.slice(event["event_digest"], 7, 64)}.claim")

    case File.open(marker, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        write(dir, event, expected || next_seq(dir), expected != nil, marker)

      {:error, :eexist} ->
        await(dir, event["event_digest"], 500)
    end
  end

  defp await(dir, digest, 0), do: {:ok, find(dir, digest), :already_recorded}

  defp await(dir, digest, tries) do
    case find(dir, digest) do
      nil ->
        Process.sleep(10)
        await(dir, digest, tries - 1)

      existing ->
        {:ok, existing, :already_recorded}
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
        stamped = Map.put(event, "seq", seq)
        name = "#{pad}-#{String.slice(event["event_digest"], 7, 16)}.json"
        tmp = Path.join(dir, ".tmp-#{pad}-#{System.unique_integer([:positive])}.tmp")
        File.write!(tmp, Jason.encode!(stamped))
        File.rename!(tmp, Path.join(dir, name))
        {:ok, stamped, :appended}

      {:error, :eexist} when strict? ->
        # Lost the optimistic race for exactly this seq: nothing was stored,
        # so release the digest claim and report the observed head.
        File.rm(marker)
        {:error, {:seq_conflict, head(dir)}}

      {:error, :eexist} ->
        write(dir, event, seq + 1, strict?, marker)
    end
  end
end
