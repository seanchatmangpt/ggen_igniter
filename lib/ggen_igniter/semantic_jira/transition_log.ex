defmodule  GgenIgniter.SemanticJira.TransitionLog  do
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
  line/file (`{:unreadable, message}`), a line/file that decodes to valid JSON
  that is not an object (`{:not_an_object, line_no}` for a file ledger, 1-based
  physical line; `{:not_an_object, file_name}` for a directory ledger), or an
  event whose `event_digest` no longer recomputes (a tampered ledger) is
  `{:error, {:ledger_refused, reason}}`, never silently projected and never a
  crash. `append/2` refuses the same way before writing.

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

  @doc """
  The events of the ledger at `path`, ordered by `seq`. Raises `ArgumentError`
  (naming the typed refusal) on a ledger `fetch/1` would refuse for being
  undecodable or holding a non-object entry; use `fetch/1` for the typed form.
  """
  @spec read(Path.t()) :: [map()]
  def read(path) do
    case decode(path) do
      {:ok, events} -> events
      {:error, reason} -> raise ArgumentError, "ledger refused: #{inspect(reason)}"
    end
  end

  defp decode(path) do
    case kind(path) do
      :dir -> decode_dir(path)
      :file -> decode_file(path)
    end
  end

  @doc """
  `read/1` behind a typed refusal: `{:ok, events}`, or
  `{:error, {:ledger_refused, reason}}` when the ledger cannot be decoded or
  any event's `event_digest` does not recompute over its content.
  """
  @spec fetch(Path.t()) :: {:ok, [map()]} | {:error, {:ledger_refused, term()}}
  def fetch(path) do
    with {:ok, events} <- ledger(decode(path)) do
      case Enum.find(events, &(not intact?(&1))) do
        nil -> {:ok, events}
        event -> {:error, {:ledger_refused, {:event_digest_mismatch, event["seq"]}}}
      end
    end
  end

  defp ledger({:ok, events}), do: {:ok, events}
  defp ledger({:error, reason}), do: {:error, {:ledger_refused, reason}}

  # One ledger entry: only a JSON OBJECT is an event. Valid JSON of any other
  # shape (array, string, number, null) is a typed refusal located at `where`.
  defp decode_event(json, where) do
    case Jason.decode(json) do
      {:ok, %{} = event} -> {:ok, event}
      {:ok, _not_an_object} -> {:error, {:not_an_object, where}}
      {:error, error} -> {:error, {:unreadable, Exception.message(error)}}
    end
  end

  @spec append(Path.t(), map()) ::
          {:ok, map(), :appended | :already_recorded}
          | {:error, {:ledger_locked, Path.t()}}
          | {:error, {:ledger_refused, term()}}
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

  defp decode_dir(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Stream.map(&decode_dir_entry(dir, &1))
        |> decode_all()

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        unreadable(dir, reason)
    end
  end

  defp decode_dir_entry(dir, name) do
    path = Path.join(dir, name)

    case File.read(path) do
      {:ok, body} -> decode_event(body, name)
      {:error, reason} -> unreadable(path, reason)
    end
  end

  # Consumes lazily decoded entries in order, halting on the first refusal.
  defp decode_all(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, &decode_step/2)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp decode_step({:ok, event}, {:ok, acc}), do: {:cont, {:ok, [event | acc]}}
  defp decode_step({:error, _} = error, _acc), do: {:halt, error}

  defp unreadable(path, reason),
    do: {:error, {:unreadable, "#{path}: #{:file.format_error(reason)}"}}

  # Called only after `append_dir/2` admitted the ledger (or on files this
  # module itself wrote): a refusal here is a concurrent corruption and raises.
  defp read_dir(dir) do
    case decode_dir(dir) do
      {:ok, events} -> events
      {:error, reason} -> raise ArgumentError, "ledger refused: #{inspect(reason)}"
    end
  end

  defp append_dir(dir, event) do
    File.mkdir_p!(dir)

    with {:ok, events} <- ledger(decode_dir(dir)) do
      case find(events, event["event_digest"]) do
        nil -> claim_digest(dir, event)
        existing -> {:ok, existing, :already_recorded}
      end
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

  # Line numbers are 1-based PHYSICAL lines (blank lines count, and are
  # skipped), so a refusal points at the exact line an operator opens.
  defp decode_file(path) do
    case File.read(path) do
      {:ok, body} -> body |> file_entries() |> decode_all() |> sorted_by_seq()
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> unreadable(path, reason)
    end
  end

  defp file_entries(body) do
    body
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Stream.reject(fn {line, _line_no} -> String.trim(line) == "" end)
    |> Stream.map(fn {line, line_no} -> decode_event(line, line_no) end)
  end

  defp sorted_by_seq({:ok, events}), do: {:ok, Enum.sort_by(events, &(&1["seq"] || 0))}
  defp sorted_by_seq(error), do: error

  defp append_file(path, event) do
    File.mkdir_p!(Path.dirname(path))
    lock = path <> ".lock"

    with_lock(lock, @lock_attempts, fn ->
      with {:ok, events} <- ledger(decode_file(path)) do
        append_new_line(path, event, events)
      end
    end)
  end

  defp append_new_line(path, event, events) do
    case find(events, event["event_digest"]) do
      nil -> append_line(path, event, events)
      existing -> {:ok, existing, :already_recorded}
    end
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
