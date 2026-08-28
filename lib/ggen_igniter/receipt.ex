defmodule GgenIgniter.Receipt do
  @moduledoc """
  CONSTRUCTION NOTE (2026-08-27): at the time this module was written, a
  concurrent workflow was tasked with building THIS file plus
  `lib/ggen_igniter/reactors/reconcile_reactor.ex` and
  `lib/ggen_igniter/telemetry/ocel_emitter.ex`. This repo was polled for
  their existence 6 times (~90 seconds, per the concurrency protocol given)
  and none had appeared yet -- only a forward-referencing comment in
  `mix.exs` evidenced the other workflow had started. This module is
  therefore this session's own from-scratch, best-effort construction, not a
  correction to pre-existing code. If the concurrent workflow's real version
  lands later, reconcile the two (do not silently prefer either) --
  `standing`'s four required atoms and the append-only-jsonl-per-admitted-
  attempt contract below are the two load-bearing requirements a merged
  version must keep.

  The RUN RECEIPT: a durable, append-only record of ONE admitted
  reconciliation ATTEMPT -- written to
  `<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`, one JSON object per
  line, one line per attempt.

  ## Receipt vs. manifest -- two different durable records, on purpose

  `GgenIgniter.Manifest` (`.ggen_igniter/manifest.json`) is the CURRENT-STATE
  cache: what does this recipe's most recent SUCCESSFUL run actually write,
  right now. It only ever advances on a real `:alive` standing -- that
  behavior is unchanged by this module.

  This module is the HISTORY: what was ATTEMPTED, every time, regardless of
  outcome. The concrete reason both are needed, in the user's own words:

  > If files were actually changed -- even temporarily -- then a
  > consequential physical actuation occurred... the run receipt should
  > record ACTUATION_STARTED -> files A,B changed -> verification failed ->
  > compensation started -> A,B restored -> resulting project hash ==
  > pre-run hash -> standing = COMPENSATED.

  A manifest-only world has NO record of that attempt at all once undo
  restores the pre-run bytes (the manifest never moved, and the files are
  back to their old content) -- yet a real, consequential actuation
  happened: disk was written to, twice. Losing that history is losing real
  operational evidence (what keeps failing verification here? how often?
  what does the failure loop look like?). This module is what keeps it.

  ## The five real standings

  `t:standing/0` MUST be one of:

    * `:alive` -- the attempt succeeded: files were written, verification
      passed, the change was admitted, and (`GgenIgniter.Manifest`) advanced.
    * `:refused` -- a fail-closed refusal BEFORE any actuation: nothing was
      ever written to disk (a path-safety guard, a missing precondition, a
      bad input). The receipt exists to record that an attempt was MADE and
      WHY it was refused, even though disk state never moved.
    * `:compensated` -- files WERE written, verification then failed for a
      reason other than a build/syntax break, undo restored the prior
      on-disk bytes, and the resulting hash was confirmed to match the
      pre-run hash.
    * `:build_broken` -- the same shape as `:compensated` (files written,
      then restored), but the specific reason verification failed was that
      the generated content itself does not parse/compile -- a genuine
      "the pack produced broken code" case, distinguished from a semantic
      verification failure so the two failure modes don't get conflated in
      the receipt history.
    * `:compensation_failed` -- CATASTROPHIC: files WERE written, verification
      then failed, and the attempt to UNDO those writes (restore the prior
      on-disk bytes) itself failed for one or more of the touched paths (a
      real `File.write!/File.rm` raising -- e.g. a target that became
      read-only, or was deleted out from under the process, between
      `:actuate` and its own revert). Unlike `:compensated`/`:build_broken`,
      this standing does NOT claim `pre_run_hash == post_run_hash` -- it
      cannot, because compensation genuinely did not fully succeed. The
      receipt's `metadata` names, explicitly: that a real mutation occurred,
      that verification failed, that restoration (compensation) ALSO
      failed, which exact paths could not be restored and why, which paths
      (if any) WERE successfully restored, and that manual repair may be
      required. This is the one standing this pipeline treats as an
      operator-facing incident, not a routine, self-healed failure -- see
      `GgenIgniter.Reactors.ReconcileReactor`'s moduledoc and
      `test/ggen_igniter_compensation_failure_test.exs` for the real,
      no-mock proof (a real `File.chmod!/2` makes a real revert write fail).

  Every one of the five is a real, distinct, intentional call site --
  `standing` is a closed set (`new/1` raises on anything else) precisely so
  a future caller cannot silently invent a sixth meaning.

  ## Format (one line of `.../receipts/<yyyy-mm-dd>.jsonl`)

      {
        "id": "rcpt_...",
        "recipe_key": "templates/resource.ex.eex=>lib/.../<%= ... %>.ex",
        "standing": "compensated",
        "started_at": "2026-08-27T12:00:00.000000Z",
        "finished_at": "2026-08-27T12:00:00.050000Z",
        "pre_run_hash": "sha256:...",
        "post_run_hash": "sha256:...",
        "files": ["lib/support_desk/support/ticket.ex"],
        "events": [ {"id": "ev_...", "activity": "ACTUATION_STARTED", ...}, ... ],
        "reason": "verification failed: ...",
        "metadata": {}
      }

  `pre_run_hash`/`post_run_hash` are built by `hash_files/1` /
  `hash_entries/1` -- a single digest over the EXACT set of files this
  attempt touched (not a whole-repository hash, which would be both
  impractical to compute per-attempt and would falsely flag as "changed"
  every unrelated file in a real project). On a `:compensated` or
  `:build_broken` receipt, `pre_run_hash == post_run_hash` is the real,
  checkable claim that compensation genuinely restored prior state -- see
  `test/ggen_igniter_receipt_compensated_test.exs`.
  """

  @receipts_reldir ".ggen_igniter/receipts"

  @standings [:alive, :refused, :compensated, :build_broken, :compensation_failed]

  @typedoc "One of the five real, closed-set standings a receipt may record."
  @type standing :: :alive | :refused | :compensated | :build_broken | :compensation_failed

  @typedoc "One receipt: one admitted reconciliation attempt, whatever its outcome."
  @type t :: %__MODULE__{
          id: String.t(),
          recipe_key: String.t() | nil,
          standing: standing(),
          started_at: String.t(),
          finished_at: String.t(),
          pre_run_hash: String.t() | nil,
          post_run_hash: String.t() | nil,
          files: [String.t()],
          events: [map()],
          reason: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:id, :standing, :started_at, :finished_at]
  defstruct id: nil,
            recipe_key: nil,
            standing: nil,
            started_at: nil,
            finished_at: nil,
            pre_run_hash: nil,
            post_run_hash: nil,
            files: [],
            events: [],
            reason: nil,
            metadata: %{}

  @doc "The five real, closed-set standing atoms a receipt may carry."
  @spec standings() :: [standing(), ...]
  def standings, do: @standings

  @doc "The receipts directory for consumer project `base_dir`: `<base_dir>/.ggen_igniter/receipts`."
  @spec dir(String.t()) :: String.t()
  def dir(base_dir), do: Path.join(base_dir, @receipts_reldir)

  @doc """
  The date-partitioned JSONL path a receipt stamped `at` (default: now) is
  appended to -- `<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`. Date
  partitioning keeps any single file bounded (an append-only log with no
  rotation would grow forever) while `read_all!/1` transparently reads every
  partition back in order.
  """
  @spec path(String.t(), DateTime.t()) :: String.t()
  def path(base_dir, at \\ DateTime.utc_now()) do
    Path.join(dir(base_dir), Calendar.strftime(at, "%Y-%m-%d") <> ".jsonl")
  end

  @doc """
  Builds a new receipt struct. `attrs` is a plain map/keyword list; `:standing`
  is required and MUST be one of `standings/0` (raises `ArgumentError`
  otherwise -- a receipt with an invented standing is a real correctness bug,
  refused loudly rather than silently persisted). `:id` is generated if not
  given; `:started_at`/`:finished_at` default to `DateTime.utc_now/0`
  (ISO8601-encoded) if not given.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)
    standing = Map.fetch!(attrs, :standing)

    unless standing in @standings do
      raise ArgumentError,
            "GgenIgniter.Receipt standing must be one of #{inspect(@standings)}, got: #{inspect(standing)}"
    end

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    attrs
    |> Map.put_new_lazy(:id, &generate_id/0)
    |> Map.put_new(:started_at, now)
    |> Map.put_new(:finished_at, now)
    |> then(&struct!(__MODULE__, &1))
  end

  defp generate_id do
    "rcpt_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @doc """
  A `"sha256:" <> hex` digest over `entries` -- a list of
  `{path, content_or_nil}` pairs, `nil` meaning the path was absent. Sorted
  by path first so the digest is order-independent (the same file set
  always hashes the same way regardless of enumeration order). This is the
  primitive both `hash_files/1` (reads current disk state) and
  `GgenIgniter.Reactors.ReconcileReactor` (hashing an already-captured
  pre-image, without re-reading disk) build on.
  """
  @spec hash_entries([{String.t(), binary() | nil}]) :: String.t()
  def hash_entries(entries) when is_list(entries) do
    digest =
      entries
      |> Enum.sort_by(fn {path, _content} -> path end)
      |> Enum.map_join("\n", fn
        {path, nil} -> path <> ":absent"
        {path, content} -> path <> ":" <> hex_sha256(content)
      end)

    "sha256:" <> hex_sha256(digest)
  end

  @doc """
  A `"sha256:" <> hex` digest over the REAL, CURRENT on-disk content of
  `paths` (missing files hash as `:absent`, matching `hash_entries/1`). This
  is the real "project hash" (scoped to the exact files one attempt
  touches, not a whole-repository hash) the user's compensation narrative
  refers to as "resulting project hash".
  """
  @spec hash_files([String.t()]) :: String.t()
  def hash_files(paths) when is_list(paths) do
    paths
    |> Enum.map(fn path ->
      case File.read(path) do
        {:ok, content} -> {path, content}
        {:error, _reason} -> {path, nil}
      end
    end)
    |> hash_entries()
  end

  defp hex_sha256(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  @doc "Converts a receipt struct to its plain, `Jason`-encodable, string-keyed map form."
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = receipt) do
    %{
      "id" => receipt.id,
      "recipe_key" => receipt.recipe_key,
      "standing" => Atom.to_string(receipt.standing),
      "started_at" => receipt.started_at,
      "finished_at" => receipt.finished_at,
      "pre_run_hash" => receipt.pre_run_hash,
      "post_run_hash" => receipt.post_run_hash,
      "files" => receipt.files,
      "events" => receipt.events,
      "reason" => receipt.reason,
      "metadata" => receipt.metadata
    }
  end

  @doc """
  REAL append-only persistence: encodes `receipt` as one JSON line and
  appends it (`File.write!/3` with `[:append]`) to `path(base_dir, at)` --
  never truncates, never rewrites a prior line. Creates the receipts
  directory if needed. This is deliberately NOT atomic-rename like
  `GgenIgniter.Manifest.persist!/2` -- an append-only log's failure mode
  (a torn last line on a real crash mid-write) is recoverable by discarding
  an incomplete final line, whereas `manifest.json` is a single
  point-in-time snapshot that atomic rename protects from ever being
  partially overwritten. See `GgenIgniter.Reactors.ReconcileReactor`'s
  moduledoc for why this receipt append happens BEFORE, and independent of,
  any manifest promotion.
  """
  @spec append!(String.t(), t()) :: :ok
  def append!(base_dir, %__MODULE__{} = receipt) do
    started_at =
      case DateTime.from_iso8601(receipt.started_at) do
        {:ok, dt, _offset} -> dt
        {:error, _} -> DateTime.utc_now()
      end

    receipt_path = path(base_dir, started_at)
    File.mkdir_p!(Path.dirname(receipt_path))

    line = Jason.encode!(to_json_map(receipt)) <> "\n"
    File.write!(receipt_path, line, [:append])
    :ok
  end

  @doc """
  Reads every receipt line back from EVERY `.jsonl` partition under
  `dir(base_dir)`, in file-then-line order (oldest date partition first;
  each partition is itself append-ordered, so this is the real
  chronological attempt history). Returns `[]` (not an error) when no
  receipts directory exists yet -- the honest "no attempts recorded yet"
  state, matching `GgenIgniter.Manifest.load/1`'s same "first run" honesty.
  """
  @spec read_all!(String.t()) :: [map()]
  def read_all!(base_dir) do
    receipts_dir = dir(base_dir)

    case File.ls(receipts_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.sort()
        |> Enum.flat_map(fn filename ->
          receipts_dir
          |> Path.join(filename)
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
        end)

      {:error, :enoent} ->
        []
    end
  end

  @doc """
  Reconstructs the CURRENT standing for one recipe (`recipe_key`) by
  re-reading the real, on-disk receipt chain under `base_dir` -- ZERO
  in-process state is consulted. This simulates exactly what a genuinely
  fresh BEAM process (no live `GgenIgniter.Controller`, no prior GenServer
  state -- e.g. after a real restart) would see: `GgenIgniter.Controller`'s
  `reconciliation_count`/`last_run_at` are real, process-only knowledge
  (see that module's moduledoc) that this function makes NO attempt to
  recover; what IS durable, and what this function reconstructs, is the
  chain of admitted attempts and the standing the last one left behind.

  `recipe_key` is the SAME `(template_path, out_template)` identity
  `GgenIgniter.Manifest.recipe_key/2` builds and every `GgenIgniter.Receipt`
  persists verbatim in its `"recipe_key"` field (see
  `GgenIgniter.Reactors.ReconcileReactor`'s `render_target/2`) -- the real,
  durable identity a receipt chain is keyed by on disk, in contrast to
  `GgenIgniter.Controller`'s `pack_key`, which is an arbitrary, PURELY
  in-process caller-supplied term with no on-disk representation at all.

  `read_all!/1`'s full chronological history is filtered down to
  `recipe_key`'s own receipts, then walked in order verifying REAL chain
  continuity: receipt N's `pre_run_hash` must equal the most recent prior
  receipt's `post_run_hash` whenever both sides recorded a hash. A
  `:refused` receipt records neither hash (nothing was ever actuated), so
  it is skipped as a continuity checkpoint -- it neither breaks nor extends
  the chain, it is simply not evidence about file content either way. A
  receipt whose `pre_run_hash` does NOT match the expected prior hash is
  real, located evidence that the on-disk history being trusted here does
  not check out -- either the stored receipt lines were tampered with, or
  some other, out-of-band write touched this recipe's target between two
  admitted attempts.

  Returns:

    * `{:ok, %{standing: standing(), receipt: map(), receipt_count: pos_integer()}}`
      -- chain verified intact end to end; `standing`/`receipt` describe the
      LAST receipt for `recipe_key`.
    * `{:error, :no_receipts}` -- `recipe_key` has no receipts at all under
      `base_dir` (the honest "nothing to reconstruct" case, matching
      `read_all!/1`'s own "no directory yet" honesty).
    * `{:error, {:chain_broken, %{at_index: non_neg_integer(), receipt_id: String.t(), expected_pre_run_hash: String.t() | nil, actual_pre_run_hash: String.t()}}}`
      -- a real, located break: `at_index` is the 0-based position (within
      `recipe_key`'s OWN filtered history, not the whole-directory history)
      of the FIRST receipt whose `pre_run_hash` fails to match the expected
      prior hash.
  """
  @spec reconstruct_standing(String.t(), String.t()) ::
          {:ok, %{standing: standing(), receipt: map(), receipt_count: pos_integer()}}
          | {:error, :no_receipts}
          | {:error, {:chain_broken, map()}}
  def reconstruct_standing(base_dir, recipe_key)
      when is_binary(base_dir) and is_binary(recipe_key) do
    base_dir
    |> read_all!()
    |> Enum.filter(&(&1["recipe_key"] == recipe_key))
    |> verify_chain()
  end

  defp verify_chain([]), do: {:error, :no_receipts}

  defp verify_chain(receipts) do
    case Enum.reduce_while(receipts, {:ok, nil}, &check_link/2) do
      {:ok, _last_expected_hash} ->
        last = List.last(receipts)

        {:ok,
         %{
           standing: String.to_existing_atom(last["standing"]),
           receipt: last,
           receipt_count: length(receipts)
         }}

      {:break, receipt, expected, actual} ->
        {:error,
         {:chain_broken,
          %{
            at_index: Enum.find_index(receipts, &(&1["id"] == receipt["id"])),
            receipt_id: receipt["id"],
            expected_pre_run_hash: expected,
            actual_pre_run_hash: actual
          }}}
    end
  end

  # One link of the chain walk. `expected_pre_hash` is the most recent real
  # hashed checkpoint seen so far (a prior receipt's `post_run_hash`), or
  # `nil` before the first hashed receipt has been seen at all.
  defp check_link(receipt, {:ok, expected_pre_hash}) do
    actual_pre = receipt["pre_run_hash"]

    cond do
      # A :refused receipt (or any receipt recording no pre_run_hash) never
      # touched files -- not a continuity checkpoint either way.
      is_nil(actual_pre) ->
        {:cont, {:ok, expected_pre_hash}}

      is_nil(expected_pre_hash) or actual_pre == expected_pre_hash ->
        {:cont, {:ok, receipt["post_run_hash"]}}

      true ->
        {:halt, {:break, receipt, expected_pre_hash, actual_pre}}
    end
  end
end
