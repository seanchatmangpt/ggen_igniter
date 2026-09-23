defmodule GgenIgniter.SemanticJira.TransitionLog do
  @moduledoc """
  Append-only, file-backed log of standing transition events. The ledger path
  is either a DIRECTORY or a FILE, resolved explicitly by `kind/1`:

  - an existing directory is a directory ledger; an existing regular file is
    a file ledger;
  - a path that does not exist yet is a file ledger when its extension is
    `.ndjson` or `.jsonl` (the `standing-ledger.ndjson` shape
    `Xaas.Ultracode.SemanticCrown` passes as `--ledger`), otherwise a
    directory ledger.

  Directory ledger: one immutable JSON file per event, named
  `<seq>-<event_digest>.json`. `append/2` is safe under concurrent writers: a
  per-digest and a per-seq exclusive-create claim make each event and each
  `seq` single-owner, and the event file appears atomically (temp file +
  rename). A writer that crashes after claiming a seq leaves a gap, never a
  duplicate.

  File ledger: one JSON event per line (ndjson). `append/2` holds an
  exclusive-create `<path>.lock` for the read-dedupe-append critical section,
  so concurrent writers serialize; the file is only ever appended to, never
  rewritten, and the path is never `mkdir_p`'d (only its parent is).

  In both forms an event whose `event_digest` is already present is returned
  unchanged (`:already_recorded`, idempotent), `read/1` returns events ordered
  by `seq`, and `fetch/1` is `read/1` behind a typed refusal: an undecodable
  line/file or an event whose `event_digest` no longer recomputes (a tampered
  ledger) is `{:error, {:ledger_refused, reason}}`, never silently projected.

  The WorkOrder definition is never touched; current standing is the
  projection `GgenIgniter.SemanticJira.project/2` of this log over the graph.
  """

  alias GgenIgniter.SemanticJira

  @file_extensions ~w(.ndjson .jsonl)
  @lock_attempts 500
  @lock_sleep_ms 10

  @doc "Resolves whether `path` is a `:dir` or a `:file` ledger (see the moduledoc)."
  @spec kind(Path.t()) :: :dir | :file
  def kind(path) do
    cond do
      File.dir?(path) -> :dir
      File.regular?(path) -> :file
      Path.extname(path) in @file_extensions -> :file
      true -> :dir
    end
  end

  @spec read(Path.t()) :: [map()]
  def read(path) do
    case kind(path) do
      :dir -> read_dir(path)
      :file -> read_file(path)
    end
  end

  @doc """
  `read/1` behind a typed refusal: `{:ok, events}`, or
  `{:error, {:ledger_refused, reason}}` when the ledger cannot be decoded or
  any event's `event_digest` does not recompute over its content.
  """
  @spec fetch(Path.t()) :: {:ok, [map()]} | {:error, {:ledger_refused, term()}}
  def fetch(path) do
    events = read(path)

    case Enum.find(events, &(not intact?(&1))) do
      nil -> {:ok, events}
      event -> {:error, {:ledger_refused, {:event_digest_mismatch, event["seq"]}}}
    end
  rescue
    error in [Jason.DecodeError, File.Error] ->
      {:error, {:ledger_refused, {:unreadable, Exception.message(error)}}}
  end

  @spec append(Path.t(), map()) ::
          {:ok, map(), :appended | :already_recorded} | {:error, {:ledger_locked, Path.t()}}
  def append(path, event) do
    event = Map.put(event, "event_digest", event_digest(event))

    case kind(path) do
      :dir -> append_dir(path, event)
      :file -> append_file(path, event)
    end
  end

  defp event_digest(event), do: SemanticJira.digest(Map.drop(event, ["seq", "event_digest"]))

  defp intact?(event) when is_map(event), do: event["event_digest"] == event_digest(event)
  defp intact?(_), do: false

  # ── directory ledger ──────────────────────────────────────────────────────

  defp read_dir(dir) do
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

  defp append_dir(dir, event) do
    File.mkdir_p!(dir)

    case find(read_dir(dir), event["event_digest"]) do
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

  defp await(dir, digest, 0), do: {:ok, find(read_dir(dir), digest), :already_recorded}

  defp await(dir, digest, tries) do
    case find(read_dir(dir), digest) do
      nil ->
        Process.sleep(10)
        await(dir, digest, tries - 1)

      existing ->
        {:ok, existing, :already_recorded}
    end
  end

  defp find(events, digest), do: Enum.find(events, &(&1["event_digest"] == digest))

  defp next_seq(dir) do
    claims =
      dir
      |> File.ls!()
      |> Enum.count(&(String.starts_with?(&1, "seq-") and String.ends_with?(&1, ".claim")))

    max(claims, length(read_dir(dir))) + 1
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

  # ── file ledger (ndjson) ──────────────────────────────────────────────────

  defp read_file(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.sort_by(&(&1["seq"] || 0))

      {:error, :enoent} ->
        []
    end
  end

  defp append_file(path, event) do
    File.mkdir_p!(Path.dirname(path))
    lock = path <> ".lock"

    with_lock(lock, @lock_attempts, fn ->
      events = read_file(path)

      case find(events, event["event_digest"]) do
        nil -> append_line(path, event, events)
        existing -> {:ok, existing, :already_recorded}
      end
    end)
  end

  # Called only while holding the ledger lock: the next seq is one past the
  # highest seq on disk, and the line is appended (the file is never rewritten).
  defp append_line(path, event, events) do
    seq = events |> Enum.map(&(&1["seq"] || 0)) |> Enum.max(fn -> 0 end) |> Kernel.+(1)
    stamped = Map.put(event, "seq", seq)
    File.write!(path, Jason.encode!(stamped) <> "\n", [:append])
    {:ok, stamped, :appended}
  end

  defp with_lock(lock, 0, _fun), do: {:error, {:ledger_locked, lock}}

  defp with_lock(lock, attempts, fun) do
    case File.open(lock, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)

        try do
          fun.()
        after
          File.rm(lock)
        end

      {:error, :eexist} ->
        Process.sleep(@lock_sleep_ms)
        with_lock(lock, attempts - 1, fun)
    end
  end
end
