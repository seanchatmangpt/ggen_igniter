defmodule GgenIgniter.SemanticJira.TransitionLog do
  @moduledoc """
  Append-only, file-backed log of standing transition events (one immutable
  JSON file per event, named `<seq>-<event_digest>.json` under a caller-given
  directory).

  - `append/2` is safe under concurrent writers: a per-digest and a per-seq
    exclusive-create claim make each event and each `seq` single-owner, and
    the event file appears atomically (temp file + rename). An event whose
    `event_digest` is already present is returned unchanged (idempotent).
    Existing files are never rewritten. A writer that crashes after claiming
    a seq leaves a gap, never a duplicate.
  - `read/1` returns events ordered by `seq`.

  The WorkOrder definition is never touched; current standing is the
  projection `GgenIgniter.SemanticJira.project/2` of this log over the graph.
  """

  alias GgenIgniter.SemanticJira

  @spec read(Path.t()) :: [map()]
  def read(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&(dir |> Path.join(&1) |> File.read!() |> Jason.decode!()))

      {:error, :enoent} ->
        []
    end
  end

  @spec append(Path.t(), map()) :: {:ok, map(), :appended | :already_recorded}
  def append(dir, event) do
    File.mkdir_p!(dir)
    event = Map.put(event, "event_digest", SemanticJira.digest(Map.delete(event, "seq")))

    case find(dir, event["event_digest"]) do
      nil -> claim_digest(dir, event)
      existing -> {:ok, existing, :already_recorded}
    end
  end

  # Two exclusive-create claims make concurrent writers safe: a per-digest
  # claim (one writer owns an event; duplicates wait for its file) and a
  # per-seq claim (one writer owns a seq). The event file itself is written to
  # a temp name and renamed, so readers never observe a partial file.
  defp claim_digest(dir, event) do
    marker = Path.join(dir, "digest-#{String.slice(event["event_digest"], 7, 64)}.claim")

    case File.open(marker, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        write(dir, event, next_seq(dir))

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

  defp find(dir, digest), do: Enum.find(read(dir), &(&1["event_digest"] == digest))

  defp next_seq(dir) do
    claims =
      dir
      |> File.ls!()
      |> Enum.count(&(String.starts_with?(&1, "seq-") and String.ends_with?(&1, ".claim")))

    max(claims, length(read(dir))) + 1
  end

  defp write(dir, event, seq) do
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

      {:error, :eexist} ->
        write(dir, event, seq + 1)
    end
  end
end
