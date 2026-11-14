defmodule GgenIgniter.Convergence do
  @moduledoc """
  Round state machine per content-sha: a reviewed subject is re-reviewed in
  bounded rounds until it passes, its findings are fixed-and-advanced, or the
  round cap is exhausted and the review ESCALATES — never a silent round 4.

  Four real states, one per round record (`rounds.jsonl` line, written by
  `GgenIgniter.ReviewStore`):

    * `ROUND_RUNNING` — the round is in flight (recorded only implicitly:
      a round whose record exists has already finished; the atom is the
      record's starting state and the type's anchor).
    * `ROUND_PASSED` — reviewer returned zero findings this round; terminal.
    * `ROUND_FIXED_ADVANCES` — findings exist but the cap is not exhausted;
      class fixes apply (`GgenIgniter.Convergence.Classes.apply_class_fix/3`)
      and the loop advances to the next round.
    * `REVIEW_ESCALATED` — findings exist AT the cap (`round >= @max_rounds`);
      terminal, wrapped in a real `GgenIgniter.Receipt` via `new/2` with the
      review attrs (`review_sha`, `round`, `decision`) as extra attrs — the
      five-standing contract in `lib/ggen_igniter/receipt.ex` is NOT modified.

  `decide/2` is total: `(round, findings)` -> `{:ok, decision, record}` for
  every input, no raise path. The cap is checked BEFORE any reviewer dispatch
  (`run/2` consults `decide/3`'s cap branch before calling the injected
  `reviewer: fun` for that round), so a capped round never reaches a reviewer.

  ## Loop driver

  `run/2` takes the subject (`%{sha: sha, base_dir: dir, diff: diff_text}`)
  and opts including `reviewer: fun`, a critic fn receiving
  `%{scope:, hunks:, round:}` and returning a list of finding maps
  (`%{file:, hunk_id:, class:, message:}`). The DEFAULT reviewer is
  `GgenIgniter.Convergence.Critic.review/1` — a real deterministic critic
  over the hunks' added lines (`:formatting` trailing whitespace,
  `:dead_code` IO.inspect/dbg, `:missing_doc` defmodule-without-moduledoc,
  hunk-local) — not an always-empty pass; an injected `reviewer:` fn
  overrides it. Round 1 reviews the full scope;
  rounds 2+ review ONLY new/changed hunks (`GgenIgniter.Convergence.Hunks`
  parses the diff; `hunk_id = GgenIgniter.Digest.sha256(file <> hunk_text)`);
  a finding whose hunk is unchanged is carried, not re-posted; a finding is
  cleared only when its hunk disappears or its class is fixed globally.
  """

  alias GgenIgniter.Convergence.Classes
  alias GgenIgniter.Convergence.Critic
  alias GgenIgniter.Convergence.Hunks
  alias GgenIgniter.ReviewStore

  @max_rounds 3

  @round_states [:round_running, :round_passed, :round_fixed_advances, :review_escalated]
  @terminal_states [:round_passed, :review_escalated]
  @decisions [:continue, :pass, :escalate]

  @typedoc "Round state atoms; the closed set every record's `state` draws from."
  @type round_state :: :round_running | :round_passed | :round_fixed_advances | :review_escalated

  @typedoc "Loop decision atoms."
  @type decision :: :continue | :pass | :escalate

  @typedoc "One reviewer finding."
  @type finding :: %{
          required(:file) => String.t(),
          required(:class) => atom(),
          optional(:hunk_id) => String.t(),
          optional(:message) => String.t()
        }

  @typedoc "One per-round record (also the `rounds.jsonl` JSON-line shape)."
  @type round_record :: %{
          required(:sha) => String.t(),
          required(:round) => pos_integer(),
          required(:state) => round_state(),
          required(:decision) => decision(),
          required(:reviewed_scope) => :full | :diff_only,
          required(:hunks_reviewed) => [%{required(String.t()) => String.t()}],
          required(:findings_open) => [finding()],
          required(:findings_carried) => [finding()],
          required(:findings_new) => [finding()],
          required(:findings_cleared) => [finding()],
          required(:class_fixed_globally) => [atom()],
          required(:rounds_to_pass) => pos_integer() | nil,
          required(:receipt_hash) => String.t() | nil,
          required(:ts) => String.t()
        }

  @doc "The round cap. Overridable ONLY via the `:max_rounds` opt (tests); never config."
  @spec max_rounds() :: pos_integer()
  def max_rounds, do: @max_rounds

  @doc "The closed set of round-state atoms."
  @spec round_states() :: [round_state(), ...]
  def round_states, do: @round_states

  @doc "The closed set of terminal round states (`:round_passed`, `:review_escalated`)."
  @spec terminal_states() :: [round_state(), ...]
  def terminal_states, do: @terminal_states

  @doc "The closed set of decision atoms."
  @spec decisions() :: [decision(), ...]
  def decisions, do: @decisions

  @doc """
  Total decision fn: `(round, findings)` -> `{:ok, decision, record}`.

  - no findings -> `:pass` (`ROUND_PASSED`, `rounds_to_pass` written ONCE).
  - findings at/over cap -> `:escalate` (`REVIEW_ESCALATED`, receipt attached).
  - findings under cap -> `:continue` (`ROUND_FIXED_ADVANCES`).

  `opts[:max_rounds]` overrides the cap for tests only. `opts[:sha]` and
  `opts[:reviewed_scope]` populate the record's identity fields; `opts[:ts]`
  pins the timestamp (tests), defaulting to now. `opts[:findings_new]`
  defaults to `findings -- findings_carried` (when `:findings_new` is not
  passed, the caller's `:findings_carried` are never misrecorded as newly
  discovered); `opts[:findings_carried]` defaults to `[]`.
  """
  @spec decide(pos_integer(), [finding()], keyword()) :: {:ok, decision(), map()}
  def decide(round, findings, opts \\ [])

  def decide(round, findings, opts) when is_integer(round) and round >= 1 and is_list(findings) do
    max = Keyword.get(opts, :max_rounds, @max_rounds)
    sha = Keyword.get(opts, :sha, "unknown")
    scope = Keyword.get(opts, :reviewed_scope, :full)
    ts = Keyword.get(opts, :ts, DateTime.utc_now() |> DateTime.to_iso8601())

    {state, decision, rounds_to_pass, receipt_hash} =
      cond do
        max <= 0 ->
          # A non-positive cap refuses: there is no lawful round budget, so
          # never a bypass "pass" — escalate typed.
          {:review_escalated, :escalate, nil, nil}

        findings == [] ->
          {:round_passed, :pass, round, nil}

        round >= max ->
          receipt =
            GgenIgniter.Receipt.new(%{
              standing: :refused,
              recipe_key: "review_convergence",
              metadata: %{
                "review_sha" => to_string(sha),
                "round" => round,
                "decision" => "escalate"
              }
            })

          {:review_escalated, :escalate, nil, receipt.receipt_hash}

        true ->
          {:round_fixed_advances, :continue, nil, nil}
      end

    record = %{
      sha: to_string(sha),
      round: round,
      state: state,
      decision: decision,
      reviewed_scope: scope,
      hunks_reviewed: Keyword.get(opts, :hunks_reviewed, []),
      findings_open: findings,
      findings_carried: Keyword.get(opts, :findings_carried, []),
      # Default: newly discovered = open minus what the caller declared as
      # carried — a caller passing findings_carried but not findings_new must
      # NOT have carried findings misrecorded as newly discovered.
      findings_new:
        Keyword.get_lazy(opts, :findings_new, fn ->
          carried = Keyword.get(opts, :findings_carried, [])
          Enum.reject(findings, &(&1 in carried))
        end),
      findings_cleared: Keyword.get(opts, :findings_cleared, []),
      class_fixed_globally: Keyword.get(opts, :class_fixed_globally, []),
      rounds_to_pass: rounds_to_pass,
      receipt_hash: receipt_hash,
      ts: ts
    }

    {:ok, decision, record}
  end

  def decide(round, findings, _opts) do
    # Total: every non-round/non-findings input still yields a typed decision
    # record rather than a raise — an invocation-shape refusal, not a crash.
    {:ok, :escalate,
     %{
       sha: "unknown",
       round: round,
       state: :review_escalated,
       decision: :escalate,
       reviewed_scope: :full,
       hunks_reviewed: [],
       findings_open: [],
       findings_carried: [],
       findings_new: [],
       findings_cleared: [],
       class_fixed_globally: [],
       rounds_to_pass: nil,
       receipt_hash: nil,
       ts: DateTime.utc_now() |> DateTime.to_iso8601(),
       refusal: {:bad_invocation, round: round, findings: findings}
     }}
  end

  @doc """
  The loop driver. `subject` = `%{sha: sha, base_dir: dir, diff: diff_text |
  nil}`; opts: `:reviewer` (critic fn; DEFAULT
  `GgenIgniter.Convergence.Critic.review/1`), `:max_rounds` (tests only),
  `:initial_findings` (round-1 findings to seed, e.g. from a prior full
  review).

  Per round, in order: cap check (BEFORE reviewer dispatch — a capped round
  never calls the reviewer), scope computation (round 1 full; rounds 2+
  diff-only over new/changed hunk_ids), reviewer dispatch, `decide/3`,
  `ReviewStore.append_round!/4` (+ diff snapshot + telemetry), and on
  `:continue` the class-fix pass (`Classes.apply_class_fix/3`) before the
  next round. Terminal rounds write `summary.json` and return
  `{:ok, final_record}`.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, :bad_subject | :bad_reviewer}
  def run(subject, opts) when is_map(subject) and is_list(opts) do
    with true <- is_binary(Map.get(subject, :sha)),
         true <- is_binary(Map.get(subject, :base_dir)),
         true <- is_function(Keyword.get(opts, :reviewer, &Critic.review/1)) do
      do_run(subject, opts)
    else
      false -> {:error, :bad_subject}
    end
  end

  def run(_subject, _opts), do: {:error, :bad_subject}

  defp do_run(subject, opts) do
    reviewer = Keyword.get(opts, :reviewer, &Critic.review/1)
    max_rounds = Keyword.get(opts, :max_rounds, @max_rounds)
    base_dir = Map.fetch!(subject, :base_dir)
    sha = Map.fetch!(subject, :sha)
    diff = Map.get(subject, :diff)

    _ = ReviewStore.new(base_dir: base_dir, sha: sha)

    hunks_by_file =
      if is_binary(diff), do: Hunks.parse_unified(diff), else: []

    # Round-1 full review sees every hunk; diff-only rounds see only the
    # hunk_ids that are new or changed relative to the previous round.
    state = %{
      sha: sha,
      base_dir: base_dir,
      diff: diff,
      hunks: hunks_by_file,
      max_rounds: max_rounds,
      prior_hunk_ids: MapSet.new(),
      open_findings: Keyword.get(opts, :initial_findings, []),
      class_fixed: [],
      acc: [],
      diff_snapshotter: Keyword.get(opts, :diff_snapshotter, &ReviewStore.snapshot_diff!/4),
      classes_module: Keyword.get(opts, :classes_module, Classes)
    }

    # loop/finalize already merge rounds_executed + all_records into the
    # terminal record; do NOT re-merge here (outer state.acc is stale).
    last_record = loop(reviewer, state)
    {:ok, last_record}
  end

  defp loop(reviewer, state) do
    round = map_size_round(state)

    # CAP CHECK — before any reviewer dispatch for this round.
    if round > state.max_rounds do
      # Fail-closed guard (escalation normally fires at round == max): a
      # capped round never dispatches a reviewer.
      {:ok, _decision, record} = decide(round, [], max_rounds: state.max_rounds, sha: state.sha)
      record
    else
      step(reviewer, state, round)
    end
  end

  defp map_size_round(state), do: length(state.acc) + 1

  defp step(reviewer, state, round) do
    hunks = state.hunks
    prior_ids = state.prior_hunk_ids
    open = state.open_findings
    sha = state.sha
    base_dir = state.base_dir

    scope = if round == 1, do: :full, else: :diff_only

    # Diff-only re-review: rounds 2+ review ONLY new/changed hunk_ids.
    {hunks_this_round, prior_ids_this_round} =
      if scope == :full do
        # Round 1 saw every hunk: all ids count as already-reviewed going in.
        {hunks, MapSet.new(Enum.map(hunks, & &1.hunk_id))}
      else
        changed = Enum.filter(hunks, fn h -> h.hunk_id not in prior_ids end)
        {changed, MapSet.union(prior_ids, MapSet.new(Enum.map(hunks, & &1.hunk_id)))}
      end

    current_ids = MapSet.new(Enum.map(hunks, & &1.hunk_id))

    # Carried findings: open findings whose hunk is unchanged (same id still
    # present) and whose class is NOT already fixed globally — NOT re-posted
    # to the reviewer. A finding WITHOUT a hunk_id is carried unconditionally
    # (conservative): it has no hunk to disappear, so per the carry/clear law
    # it is never silently cleared — it exits only via a global class fix.
    # Cleared: hunk disappeared OR class fixed globally.
    {carried, cleared} =
      Enum.split_with(open, fn f ->
        hunk_id = Map.get(f, :hunk_id)

        (hunk_id == nil or MapSet.member?(current_ids, hunk_id)) and
          f.class not in state.class_fixed
      end)

    # Always dispatch: the reviewer sees ONLY this round's new/changed hunks
    # (possibly [] on a settled diff); carried findings are NOT re-posted.
    reviewer_findings =
      reviewer.(%{scope: scope, hunks: hunks_this_round, round: round})

    findings = reviewer_findings ++ carried

    opts =
      [
        sha: sha,
        max_rounds: state.max_rounds,
        reviewed_scope: scope,
        hunks_reviewed:
          Enum.map(hunks_this_round, &%{"file" => &1.file, "hunk_id" => &1.hunk_id}),
        findings_carried: carried,
        findings_new: reviewer_findings,
        findings_cleared: cleared,
        class_fixed_globally: state.class_fixed
      ]

    {:ok, decision, record} = decide(round, findings, opts)

    # Persist side-effects for this round.
    if is_binary(state.diff) do
      state.diff_snapshotter.(base_dir, sha, round, state.diff)
    end

    ReviewStore.append_round!(base_dir, sha, record)
    emit_round_event(record)

    case decision do
      :pass ->
        finalize(state, record)

      :escalate ->
        finalize(state, record)

      :continue ->
        # Class-fix pass: close all same-class findings across files.
        {fixed_findings, newly_fixed_classes} = apply_class_fixes(findings, state.classes_module)

        loop(
          reviewer,
          %{
            state
            | prior_hunk_ids: prior_ids_this_round,
              open_findings: fixed_findings,
              class_fixed: state.class_fixed ++ newly_fixed_classes,
              acc: [record | state.acc]
          }
        )
    end
  end

  defp apply_class_fixes(findings, classes_module) do
    findings
    |> Enum.map(& &1.class)
    |> Enum.uniq()
    |> Enum.reduce({findings, []}, fn class, {acc_findings, fixed} ->
      case classes_module.apply_class_fix(acc_findings, class, reason: "class_fixed") do
        {:ok, fixed_findings, _count} -> {fixed_findings, fixed ++ [class]}
        {:error, _} -> {acc_findings, fixed}
      end
    end)
  end

  defp finalize(state, record) do
    summary = %{
      sha: state.sha,
      final_state: Atom.to_string(record.state),
      decision: Atom.to_string(record.decision),
      rounds: length(state.acc) + 1,
      rounds_to_pass: record.rounds_to_pass,
      class_fixed_globally: Enum.map(state.class_fixed, &Atom.to_string/1),
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    ReviewStore.write_summary!(state.base_dir, state.sha, summary)

    Map.merge(record, %{
      rounds_executed: length(state.acc) + 1,
      all_records: Enum.reverse([record | state.acc]),
      summary: summary
    })
  end

  defp emit_round_event(record) do
    GgenIgniter.Telemetry.OcelEmitter.emit_review_round(nil, %{
      sha: record.sha,
      round: record.round,
      state: record.state,
      decision: record.decision,
      reviewed_scope: record.reviewed_scope
    })
  end
end
