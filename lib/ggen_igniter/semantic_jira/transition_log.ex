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
  line/file (`{:unreadable, message}`), a line/file that decodes to valid JSON
  that is not an object (`{:not_an_object, line_no}` for a file ledger, 1-based
  physical line; `{:not_an_object, file_name}` for a directory ledger), or an
  event whose `event_digest` no longer recomputes (a tampered ledger) is
  `{:error, {:ledger_refused, reason}}`, never silently projected and never a
  crash. `append/2` refuses the same way before writing.

  Two digest rules are public for ledger consumers: `event_digest/1`, the
  current rule (`SemanticJira.digest_exact/1` over the event minus `seq` and
  `event_digest`, eliding nothing — the event commits to the receipt it
  records), and `legacy_event_digest/1`, the pre-v26.10.1 rule
  (`SemanticJira.digest/1` over the same map, so the nine derived `*_digest`
  fields are elided) that events written before receipt-committing carry.
  `append/2` stamps and `fetch/1` verifies with `event_digest/1` only — the
  legacy rule has never been a verification rule of this module, only a
  deprecated, shrinking compatibility window: it exists solely so xaas's
  `Xaas.Ultracode.SemanticJiraBridge.derives?/1` can still admit the three
  committed pre-v26.10.1 episode ledgers that verify ONLY under it (xaas
  `docs/sjira/v26.9.23/episodes/{fmt-1,me-1,me-2}/ledger.ndjson` — the D1
  census of 2026-10-02, which found every other committed ledger current-rule
  or dead under both rules). The window is scheduled for removal at the
  v26.11.1 milestone; from now on a consumer should probe the legacy export's
  availability instead of calling it unconditionally.

  ## Epoch + vector clocks (loops-of-loops spec §1 Loop 2)

  Every event this module writes carries `"epoch"` — the LEDGER-GENERATION
  counter — and, when the caller passes `opts[:vc]`, a `"vc"` vector clock
  `%{"<replica>" => counter}`. The two fields are ordinary event fields, so
  `event_digest/1` commits to them automatically; pre-L3 events without them
  still verify because the digest is computed over whatever fields exist (no
  legacy arm is needed for READS — only `legacy_event_digest/1`'s pre-existing,
  shrinking window above predates this). New writes always stamp `epoch`
  (`vc` stays optional).

  The bump law: an epoch is advanced only when the replica/ledger declares a
  new generation — `opts[:epoch_bump]` is that explicit advance (stamped
  epoch = last + bump), `opts[:epoch]` is an explicit stamp, and otherwise the
  epoch STAYS: events written in the same receipt-window share the ledger's
  current generation. `seq` orders events WITHIN a generation; the epoch
  orders generations. A ledger's last epoch is the max over its events'
  epochs and the `<dir>/epoch` / `<path>.epoch` marker file (default 0 when
  neither exists — the pre-L3 shape). An append whose explicit `opts[:epoch]`
  is below the ledger's last epoch is refused before any byte is written:
  `{:error, {:ledger_refused, :epoch_regression}}`. Honest residue: within
  one ledger form's own append critical section (the ndjson lock, the
  directory digest claim) the stamped epoch is exact; a plain append racing a
  concurrent `epoch_bump` from another replica may stamp the pre-bump epoch —
  epoch advances declare a generation, and concurrent bumps serialize on the
  marker (max-guarded), so the observed epoch sequence never decreases.

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

  @doc """
  Appends `event` to the ledger at `path`, stamping `seq`, `event_digest`,
  `epoch`, and — only when `opts[:vc]` is given — `vc` (see the "Epoch +
  vector clocks" section of the moduledoc for the bump law and the
  `{:error, {:ledger_refused, :epoch_regression}}` refusal).

  Options:

    * `:vc` — the writer's vector clock, `%{"<replica>" => counter}` (string
      keys, non-negative integer counters). Absent → the event carries none.
    * `:epoch` — explicit stamp; must be `>=` the ledger's last epoch.
    * `:epoch_bump` — explicit advance (stamped epoch = last + bump); the
      marker is persisted so the declared generation survives even if no
      event follows.
  """
  @spec append(Path.t(), map(), keyword()) ::
          {:ok, map(), :appended | :already_recorded}
          | {:error, {:ledger_locked, Path.t()}}
          | {:error, {:ledger_refused, term()}}
  def append(path, event, opts \\ []) do
    case kind(path) do
      :dir -> append_dir(path, event, opts)
      :file -> append_file(path, event, opts)
    end
  end

  # The L3 stamp: `vc` (when the caller carries one), then `epoch`, then the
  # digest — in that order, so `event_digest/1` commits to both new fields.
  # Any caller-supplied `vc`/`epoch`/`event_digest` is overwritten.
  defp stamp(ledger, events, event, opts) do
    with {:ok, epoch} <- next_epoch(ledger, events, opts) do
      event =
        event
        |> Map.drop(["vc", "epoch", "event_digest"])
        |> maybe_vc(opts[:vc])
        |> Map.put("epoch", epoch)
        |> then(&Map.put(&1, "event_digest", event_digest(&1)))

      if epoch > marker_epoch(ledger), do: write_epoch_marker(ledger, epoch)
      {:ok, event}
    end
  end

  defp maybe_vc(event, nil), do: event

  defp maybe_vc(event, vc) do
    unless is_map(vc) and Enum.all?(vc, fn {r, n} -> is_binary(r) and is_integer(n) and n >= 0 end),
      do: raise(ArgumentError, "append/3 opts[:vc] must map string replica ids to non-negative integers")

    Map.put(event, "vc", vc)
  end

  # The stamp decision, taken against the ledger's own critical section (the
  # events just decoded): explicit `:epoch` must not regress; `:epoch_bump`
  # advances; otherwise the epoch stays.
  defp next_epoch(ledger, events, opts) do
    last = last_epoch(ledger, events)

    cond do
      (e = opts[:epoch]) != nil ->
        unless is_integer(e) and e >= 0,
          do: raise(ArgumentError, "append/3 opts[:epoch] must be a non-negative integer")

        if e < last,
          do: {:error, {:ledger_refused, :epoch_regression}},
          else: {:ok, e}

      (b = opts[:epoch_bump]) != nil ->
        unless is_integer(b) and b >= 1,
          do: raise(ArgumentError, "append/3 opts[:epoch_bump] must be a positive integer")

        {:ok, last + b}

      true ->
        {:ok, last}
    end
  end

  # Last epoch = max over the ledger's events' epochs and the marker file;
  # pre-L3 events carry no epoch and contribute 0.
  defp last_epoch(ledger, events),
    do:
      events
      |> Enum.map(&(&1["epoch"] || 0))
      |> Enum.max(fn -> 0 end)
      |> max(marker_epoch(ledger))

  defp epoch_marker(ledger),
    do: if(kind(ledger) == :dir, do: Path.join(ledger, "epoch"), else: ledger <> ".epoch")

  defp marker_epoch(ledger) do
    case File.read(epoch_marker(ledger)) do
      {:ok, body} ->
        case Integer.parse(String.trim(body)) do
          {n, ""} when n >= 0 -> n
          _ -> 0
        end

      _ ->
        0
    end
  end

  # The marker follows the .claim spirit: a durable record of the declared
  # generation, max-guarded so it never moves backwards. In directory form
  # bumps serialize on `<dir>/epoch.lock` (same exclusive-create pattern as
  # the ndjson lock); in file form the append lock is already held.
  defp write_epoch_marker(ledger, epoch) do
    marker = epoch_marker(ledger)

    case kind(ledger) do
      :dir ->
        with_lock(Path.join(ledger, "epoch.lock"), @lock_attempts, fn ->
          if epoch > marker_epoch(ledger), do: File.write!(marker, Integer.to_string(epoch))
        end)

      :file ->
        if epoch > marker_epoch(ledger), do: File.write!(marker, Integer.to_string(epoch))
    end
  end

  @doc """
  The digest `append/2` stamps and `fetch/1` verifies: `SemanticJira.digest_exact/1`
  over the event minus `seq`/`event_digest` — nothing is elided, so the event
  commits to the receipt it records (`receipt_digest` included), independent of
  map insertion order. `Xaas.Ultracode.SemanticJiraBridge.derives?/1` accepts it
  first.
  """
  @spec event_digest(map()) :: String.t()
  def event_digest(event),
    do: SemanticJira.digest_exact(Map.drop(event, ["seq", "event_digest"]))

  @doc """
  The pre-v26.10.1 digest rule events written before receipt-committing carry:
  `SemanticJira.digest/1` over the event minus `seq`/`event_digest` — the nine
  derived `*_digest` fields (including `receipt_digest`) are elided, so it
  diverges from `event_digest/1` on any event holding one. The bridge's
  `derives?/1` accepts it for logs written before the receipt-committing rule,
  while that export still ships.
  """
  @deprecated "Shrinking compatibility window (D1, 2026-10-02): consumers must probe availability via function_exported?/3 and fall back to event_digest/1; scheduled for removal at the v26.11.1 milestone"
  @spec legacy_event_digest(map()) :: String.t()
  def legacy_event_digest(event),
    do: SemanticJira.digest(Map.drop(event, ["seq", "event_digest"]))

  defp intact?(event) when is_map(event), do: event["event_digest"] == event_digest(event)
  defp intact?(_), do: false

  @doc """
  `true` when vector clock `a` dominates `b`: for every replica `r`,
  `a[r] >= b[r]` AND for at least one replica `a[r] > b[r]` — a missing
  replica counts as 0. Two equal clocks do not dominate each other, and the
  empty clock dominates nothing.

  This is the conflict law `Reconciler` applies before promotion (see
  `vc_concurrent?/2`): knowledge of the same WorkOrder's history only
  extends, it never disagrees.
  """
  @spec vc_dominates?(map(), map()) :: boolean()
  def vc_dominates?(a, b) when is_map(a) and is_map(b) do
    replicas = MapSet.union(MapSet.new(Map.keys(a)), MapSet.new(Map.keys(b)))

    ge = Enum.all?(replicas, &(Map.get(a, &1, 0) >= Map.get(b, &1, 0)))
    gt = Enum.any?(replicas, &(Map.get(a, &1, 0) > Map.get(b, &1, 0)))
    ge and gt
  end

  @doc """
  `true` when the clocks are UNORDERED: neither `a[r] <= b[r]` for all `r`
  nor `b[r] <= a[r]` for all `r` (missing replica counts as 0). Two EQUAL
  clocks are the same history, never a conflict — a replay carries the same
  clock as the event it replays and must not refuse.

  This is the conflict law `Reconciler.reconcile/4` applies before promotion:
  an incoming receipt whose `vc` is concurrent with the last event's `vc`
  for the same identity refuses as
  `{:error, {:refused, {:vc_concurrent, incoming, last}}}` — the
  deterministic-replay defense (loops-of-loops spec §1 Loop 2).
  """
  @spec vc_concurrent?(map(), map()) :: boolean()
  def vc_concurrent?(a, b) when is_map(a) and is_map(b) do
    not vc_le?(a, b) and not vc_le?(b, a)
  end

  # a <= b componentwise (missing replica counts 0); enumerating `a` is
  # sufficient — a replica only in `b` has a[r] = 0 <= b[r] trivially.
  defp vc_le?(a, b), do: Enum.all?(a, fn {r, n} -> n <= Map.get(b, r, 0) end)

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

  defp append_dir(dir, event, opts) do
    File.mkdir_p!(dir)

    with {:ok, events} <- ledger(decode_dir(dir)),
         {:ok, stamped} <- stamp(dir, events, event, opts) do
      case find(events, stamped["event_digest"]) do
        nil -> claim_digest(dir, stamped)
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

  defp append_file(path, event, opts) do
    File.mkdir_p!(Path.dirname(path))
    lock = path <> ".lock"

    with_lock(lock, @lock_attempts, fn ->
      with {:ok, events} <- ledger(decode_file(path)),
           {:ok, stamped} <- stamp(path, events, event, opts) do
        append_new_line(path, stamped, events)
      end
    end)
  end

  defp append_new_line(path, stamped, events) do
    case find(events, stamped["event_digest"]) do
      nil -> append_line(path, stamped, events)
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
