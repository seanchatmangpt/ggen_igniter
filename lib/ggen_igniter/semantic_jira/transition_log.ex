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
  - `event_digest` commits to the whole event, including the `receipt_digest`
    and `transition_digest` it cites (`event_digest/1`), so a stored event can
    be re-derived and two events citing different receipts never collide.

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

  @doc """
  The digest `append/2` stamps as `event_digest`: `SemanticJira.digest_exact/1`
  of the event without `seq` and `event_digest`. It commits to the cited
  `receipt_digest` and `transition_digest`, so an event can be re-derived from
  its own content (`event["event_digest"] == event_digest(event)`) and two
  events that cite different receipts never share a digest.

  Logs written before this rule derived the digest with `SemanticJira.digest/1`
  (which drops the two cited digests); `legacy_event_digest/1` is that rule, for
  verifying such logs.
  """
  @spec event_digest(map()) :: String.t()
  def event_digest(event), do: SemanticJira.digest_exact(Map.drop(event, ["seq", "event_digest"]))

  @doc "The pre-`digest_exact/1` derivation of `event_digest`, kept to verify old logs."
  @spec legacy_event_digest(map()) :: String.t()
  def legacy_event_digest(event),
    do: SemanticJira.digest(Map.drop(event, ["seq", "event_digest"]))

  @spec append(Path.t(), map()) :: {:ok, map(), :appended | :already_recorded}
  def append(dir, event) do
    File.mkdir_p!(dir)
    event = Map.put(event, "event_digest", event_digest(event))

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
