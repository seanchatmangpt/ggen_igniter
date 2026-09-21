defmodule GgenIgniter.SemanticJira.ReceiptEmitter do
  @moduledoc """
  Produces the receipt `GgenIgniter.SemanticJira.Reconciler.reconcile/4`
  consumes from a REAL run, instead of a caller-built map.

  Smallest faithful subset of the BRCE path that exists as code in this repo
  (`parse -> route -> admit/refuse -> diagnose/repair -> construct -> actuate
  -> receipt -> replay -> standing`). The external BRCE/CommandBus named in
  `SemanticJira.do_intent/2` is not vendored here, so the stages below are
  marked in every receipt's `"stages"` ledger as `executed`, `skipped` or
  `UNSUPPORTED(...)`, never narrated:

    * parse: `normalize_plan/2` (steps, seed files, watched files, optional
      subject source) -- executed.
    * route: UNSUPPORTED(single-route) -- one route only, local `sh` subprocess.
    * admit/refuse: `emit/4` admits, BEFORE anything runs and with every value
      proven JSON-encodable (invalid UTF-8 or non-JSON terms anywhere in the
      WorkOrder, package, plan, authority receipt or options are a refusal,
      never a post-run crash): the WorkOrder (`SemanticJira.admit_work_order/1`);
      the `RuntimeShape` execution package (digest, `work_order_digest`,
      subject, and its `bindings`/`policies`/`actions`/`provenance` content
      against the WorkOrder: `worker_not_verifier`, `base_must_not_move`,
      repository/base binding); the plan (bindings must name real acceptance/
      falsifier/court/evidence ids; when the WorkOrder pins commands in
      `expected_consequence.commands` the plan must be exactly those commands);
      the subject source (the WorkOrder's exact commit must exist there); and
      authority (a non-`NONE` `authority_requirement` needs a matching prepared
      authority receipt). Any failure is `{:error, {:refused, reason}}`.
    * diagnose/repair: UNSUPPORTED -- a failing run yields a non-success
      receipt; `SemanticJira.repair_work_order/2` lineage is not driven from here.
    * construct: a fresh PRIVATE run directory (exclusive `mkdir`, mode 0700,
      name carrying the OS pid and random bytes) under `System.tmp_dir!/0`. Its
      `work/` subdirectory is the command cwd, seeded with the plan's
      `seed_files` or with `git archive` of the WorkOrder's exact commit from the
      plan's `subject_source` -- executed.
    * actuate: each step is a real `System.cmd("sh", ...)` subprocess in `work/`
      (`exec "$0" "$@"` wrapper so stdout and stderr are captured separately;
      each step's stderr file lives in the private run directory, outside the
      command's cwd; POSIX `sh` required). Fail-fast: steps after a failed step
      are recorded `ran: false`. Only cwd is scoped -- there is no filesystem
      sandbox and a timeout kills the Elixir task, not the OS process group
      (UNSUPPORTED(isolation)).
    * receipt: `emit/4` builds a digest-sealed map (`"receipt_digest"`, the same
      `SemanticJira.digest/1` the log uses) with `identity`, `authority`,
      `requirements`, `consequence` (per-step exit code, stdout/stderr digests,
      watched-file before/after content digests plus
      `GgenIgniter.Receipt.hash_files/1` and a portable
      `GgenIgniter.Receipt.hash_entries/1` digest, the materialized `subject`),
      `replay` (the normalized plan, toolchain/environment identity, replay
      verdict), `evidence` (DERIVED from the consequence, never asserted) and
      `standing` (the target the receipt supports; `transition_applied` is
      always false).
    * replay: `replay/2` re-runs a trusted plan in a fresh run directory and
      compares the comparable consequence via `SemanticJira.replay_check/2`;
      `emit/4` does it inline when `replay: true` or the WorkOrder has
      `replay_required`.
    * standing: not applied here -- `Reconciler.reconcile/4` owns the transition.

  ## What an ALIVE proposal means

  ALIVE is proposed (and `evidence.observed_execution` / `evidence_ceiling`
  `"observed"` derived) only when ALL of these hold; otherwise the target is
  `PARTIAL_ALIVE` and the evidence ceiling is `"none"`, so `SemanticJira.promote/3`
  refuses a forced `ALIVE` with `[:ceiling]`:

    1. Subject bound: the plan named a `subject_source` (a local git repository)
       and the command ran against a checkout of exactly the WorkOrder's
       `candidate_sha` (else `base_sha`), `consequence.subject.bound == true`.
    2. Commands pinned: the WorkOrder's `expected_consequence` is
       `%{"commands" => [%{"argv" => [...], "expect_exit" => 0}]}` and the plan's
       steps are exactly those commands. The WorkOrder (part of its definition
       digest) says what the acceptance commands are; the plan cannot choose.
    3. Authority: `authority_requirement` is `NONE`, or the prepared authority
       receipt passed the caller-supplied `:authority_verifier`.
    4. The WorkOrder's own `evidence_ceiling` is `observed` (the only ceiling a
       local run can attest).

  ## Verification

  `verify/2` refuses a receipt whose seal does not match its body, whose
  derived fields (per-step `passed`, `success`, `exit_code`,
  `consequence_digest`, `evidence`, `standing.proposed`) do not re-derive from
  its consequence, or (with a WorkOrder) whose requirements/identity/pinned
  steps do not match. `check_success/1` refuses a sealed receipt of a run that
  did not succeed. `Reconciler.reconcile/4` calls both for any emitted/sealed
  receipt, refuses an emitter-shaped receipt whose seal was stripped, and with
  `require_sealed: true` refuses hand-built receipts.

  ## Disclosed limits

    * The seal is a content digest (integrity), not a signature: a forger who
      recomputes seal and every derived field yields a self-consistent receipt.
      `replay/2` (and `Reconciler` option `replay_plan: plan`, which replays a
      TRUSTED plan whose digest must equal the receipt's, never the receipt's own
      embedded argv) is the mitigation for deterministic plans: a forged
      consequence will not reproduce. Nondeterministic plans (timestamps, pids in
      stdout) fail replay.
    * A hand-built receipt with NONE of the emitter's fields is still admitted
      by default (it is indistinguishable from the pre-emitter caller-supplied
      shape). `require_sealed: true` is what eliminates caller-supplied receipts.
    * Repository identity is UNSUPPORTED: the subject is bound by commit sha
      (content-addressed) from a caller-named local git repository; the
      WorkOrder's `repository` name is copied, not verified against it.
    * A WorkOrder that does not pin `expected_consequence.commands` gets
      `PARTIAL_ALIVE` at most: which command backs which claim is then asserted
      by the plan author (UNSUPPORTED(acceptance-relevance)).
    * Authority provenance is UNSUPPORTED(authority-issuer): the emitter has no
      claim store or signer. A prepared authority receipt is only structurally
      matched unless the caller supplies `:authority_verifier`; an unverified one
      is recorded but never enters `evidence`, so promotion is refused with
      `[:authority]`.
    * A failing run cannot lawfully move standing to BLOCKED/BUILD_BROKEN:
      `SemanticJira.promote/3` requires every check for every target. The
      receipt is refused for transition and standing stays.
    * Authority stays NONE; the emitter grants nothing.
  """

  alias GgenIgniter.{Digest, Receipt, RuntimeShape, SemanticJira}

  @kind "brce_receipt"
  @schema "semantic-jira/brce-receipt/v2"
  @emitter "GgenIgniter.SemanticJira.ReceiptEmitter"
  @attainable_ceilings ["observed"]
  @default_timeout_ms 60_000
  @excerpt_bytes 512
  @bind_kinds ~w(acceptance falsifiers courts evidence)
  @sh_wrapper ~S(exec "$0" "$@" 2>"$GGEN_BRCE_STDERR")

  @type receipt :: %{optional(String.t()) => term()}
  @type reason :: term()

  @doc "The `\"kind\"` value every emitted receipt carries."
  @spec kind() :: String.t()
  def kind, do: @kind

  @doc "The receipt schema identifier."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc """
  Convenience plan: ONE acceptance command bound to everything the WorkOrder
  requires (all acceptance ids, falsifiers, courts and evidence types). The
  binding is part of the sealed plan, so a reader sees exactly which command
  backs which claim. Options: `:expect_exit` (default 0), `:timeout_ms`,
  `:seed_files` (`%{relative_path => text}`), `:watch` (relative paths),
  `:subject_source` (absolute path of a local git repository holding the
  WorkOrder's exact commit; see the moduledoc's ALIVE conditions).
  """
  @spec command_plan(map(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, {:refused, reason()}}
  def command_plan(work_order, argv, opts \\ []) do
    with {:ok, admitted} <- admit(work_order) do
      {:ok,
       %{
         "steps" => [
           %{
             "id" => "acceptance-command",
             "argv" => argv,
             "expect_exit" => Keyword.get(opts, :expect_exit, 0),
             "timeout_ms" => Keyword.get(opts, :timeout_ms, @default_timeout_ms),
             "binds" => %{
               "acceptance" => admitted["acceptance"],
               "falsifiers" => admitted["falsifiers"],
               "courts" => admitted["required_courts"],
               "evidence" => admitted["required_evidence"]
             }
           }
         ],
         "seed_files" => Keyword.get(opts, :seed_files, %{}),
         "watch" => Keyword.get(opts, :watch, [])
       }
       |> put_subject_source(Keyword.get(opts, :subject_source))}
    end
  end

  defp put_subject_source(plan, nil), do: plan
  defp put_subject_source(plan, source), do: Map.put(plan, "subject_source", source)

  @doc "`command_plan/3` then `emit/4`: run one real acceptance command and seal the receipt."
  @spec emit_command(map(), RuntimeShape.t(), [String.t()], keyword()) ::
          {:ok, receipt()} | {:error, term()}
  def emit_command(work_order, package, argv, opts \\ []) do
    with {:ok, plan} <- command_plan(work_order, argv, opts) do
      emit(work_order, package, plan, opts)
    end
  end

  @doc """
  Admits, runs and seals.

  `work_order` is the raw WorkOrder map, `package` the
  `SemanticJira.execution_package/2` result for it, `plan` a map with string
  or atom keys: `steps` (each `id`, `argv`, optional `expect_exit`,
  `timeout_ms`, `binds` with any of `acceptance`/`falsifiers`/`courts`/
  `evidence`), optional `seed_files` (refused together with `subject_source`),
  `watch` and `subject_source`.

  Options: `:target` (default derived), `:replay` (default: WorkOrder's
  `replay_required`), `:authority_receipt` (prepared authority receipt for a
  WorkOrder whose `authority_requirement` is not `NONE`), `:authority_verifier`
  (`(prepared_receipt, admitted_work_order -> :ok | {:error, reason})`, the
  caller's trust anchor for that receipt), `:emitter_identity`.

  Returns `{:ok, receipt}` for every admitted run (a failing command yields a
  valid, sealed, non-success receipt), `{:error, {:refused, reason}}` when
  admission fails before anything ran, `{:error, {:construct_failed, reason}}`
  on scratch-dir I/O failure.
  """
  @spec emit(map(), RuntimeShape.t(), map(), keyword()) ::
          {:ok, receipt()} | {:error, {:refused, reason()} | {:construct_failed, reason()}}
  def emit(work_order, package, plan, opts \\ []) do
    with {:ok, admitted} <- admit(work_order),
         {:ok, def_digest} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <- admit_options(opts),
         :ok <- admit_package(admitted, package),
         {:ok, authority} <- admit_authority(admitted, opts),
         {:ok, plan} <- normalize_plan(plan, admitted),
         :ok <- admit_subject(admitted, plan),
         {:ok, run} <- execute(plan, subject_sha(admitted)) do
      replay = replay_section(plan, run, admitted, package, opts)
      {:ok, seal(build(admitted, def_digest, package, plan, run, replay, authority, opts))}
    end
  end

  @doc """
  Re-runs a plan in a fresh scratch dir and compares the comparable consequence
  (per-step exit code and stdout digest, watched-file content) and the
  toolchain/environment identity against the receipt through
  `SemanticJira.replay_check/2`.

  A receipt is DATA, and a seal-valid receipt can be forged, so its embedded
  plan is never executed by default. Either pass the trusted plan
  (`work_order: wo, plan: plan`; it is normalized and its digest must equal the
  receipt's `replay.plan_digest`) or opt in explicitly with
  `trust_receipt_plan: true`.

  `{:ok, replay_receipt}` when identical; `{:error, {:replay_refused, ...}}` on
  a mismatch (including a forged consequence), untrusted plan or bad seal.
  """
  @spec replay(receipt(), keyword()) :: {:ok, map()} | {:error, term()}
  def replay(receipt, opts \\ []) do
    receipt = stringify(receipt)

    with :ok <- verify(receipt),
         {:ok, plan} <- replay_plan(receipt, opts),
         {:ok, run} <- execute(plan, identity_sha(receipt["identity"])) do
      compare(receipt_context(receipt), run)
    end
  end

  defp replay_plan(receipt, opts) do
    cond do
      Keyword.has_key?(opts, :plan) and Keyword.has_key?(opts, :work_order) ->
        trusted_plan(receipt, opts[:work_order], opts[:plan])

      Keyword.get(opts, :trust_receipt_plan) == true ->
        {:ok, receipt["replay"]["plan"]}

      true ->
        {:error, {:replay_refused, :untrusted_plan}}
    end
  end

  # The caller's plan is normalized against the caller's WorkOrder and must be
  # the exact plan the receipt sealed.
  defp trusted_plan(receipt, work_order, plan) do
    with {:ok, admitted} <- admit(work_order),
         {:ok, plan} <- normalize_plan(plan, admitted) do
      if SemanticJira.digest(plan) == receipt["replay"]["plan_digest"],
        do: {:ok, plan},
        else: {:error, {:replay_refused, :plan_digest_mismatch}}
    end
  end

  @doc """
  Verifies seal and internal coherence; with a WorkOrder also that the
  receipt's requirements and definition identity match it.
  """
  @spec verify(receipt(), map() | nil) :: :ok | {:error, reason()}
  def verify(receipt, work_order \\ nil) do
    receipt = stringify(receipt)

    with :ok <- check(receipt["kind"] == @kind, :not_an_emitted_receipt),
         :ok <- check(digest?(receipt["receipt_digest"]), :missing_seal),
         :ok <- check(SemanticJira.digest(receipt) == receipt["receipt_digest"], :seal_mismatch),
         :ok <- check(receipt["schema"] == @schema, :unknown_schema),
         :ok <- check_binding(receipt),
         :ok <- check_derivation(receipt) do
      check_work_order(receipt, work_order)
    end
  rescue
    # A resealed but structurally malformed receipt is refused, never a crash.
    _ -> {:error, :malformed_receipt}
  end

  @doc "Refuses a (valid, sealed) receipt of a run that did not succeed."
  @spec check_success(receipt()) :: :ok | {:error, {:non_success_receipt, term()}}
  def check_success(receipt) do
    consequence = stringify(receipt)["consequence"] || %{}

    if consequence["success"] == true,
      do: :ok,
      else: {:error, {:non_success_receipt, consequence["exit_code"]}}
  end

  @doc "Writes the receipt content-addressed as `<dir>/<hex>.json`; idempotent."
  @spec persist(receipt(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def persist(receipt, dir) do
    receipt = stringify(receipt)

    with :ok <- verify(receipt),
         :ok <- File.mkdir_p(dir) do
      path =
        Path.join(dir, String.replace_prefix(receipt["receipt_digest"], "sha256:", "") <> ".json")

      with :ok <- File.write(path, Jason.encode!(receipt)), do: {:ok, path}
    end
  end

  @doc "Reads a persisted receipt and verifies its seal."
  @spec load(Path.t()) :: {:ok, receipt()} | {:error, term()}
  def load(path) do
    with {:ok, body} <- File.read(path),
         {:ok, receipt} <- Jason.decode(body),
         :ok <- verify(receipt) do
      {:ok, receipt}
    end
  end

  # -- admission -------------------------------------------------------------

  # `SemanticJira.digest/1` (used for the WorkOrder and, later, to seal) is
  # `Jason.encode!/1`: a value with no JSON encoding must be refused HERE, never
  # discovered after a command ran.
  defp admit(work_order) do
    if json_safe?(work_order) do
      case SemanticJira.admit_work_order(work_order) do
        {:ok, admitted} -> {:ok, admitted}
        {:error, reason} -> {:error, {:refused, {:work_order, reason}}}
      end
    else
      {:error, {:refused, {:work_order, :not_json_safe}}}
    end
  end

  defp admit_options(opts) do
    with :ok <- check(Keyword.keyword?(opts), {:refused, :invalid_options}),
         :ok <-
           check(
             is_nil(opts[:target]) or opts[:target] in SemanticJira.standings(),
             {:refused, {:invalid_target, opts[:target]}}
           ),
         :ok <-
           check(
             is_nil(opts[:emitter_identity]) or
               (is_binary(opts[:emitter_identity]) and opts[:emitter_identity] != "" and
                  String.valid?(opts[:emitter_identity])),
             {:refused, :invalid_emitter_identity}
           ) do
      check(
        is_nil(opts[:replay]) or is_boolean(opts[:replay]),
        {:refused, :invalid_replay_option}
      )
    end
  end

  defp refuse({:ok, v}), do: {:ok, v}
  defp refuse({:error, reason}), do: {:error, {:refused, {:work_order, reason}}}

  defp admit_package(admitted, %RuntimeShape{} = package) do
    with :ok <-
           check(
             json_safe?(RuntimeShape.semantic_map(package)),
             {:refused, :package_not_json_safe}
           ),
         :ok <-
           check(
             RuntimeShape.digest(package) == package.shape_digest,
             {:refused, :package_digest_mismatch}
           ),
         :ok <-
           check(
             package.admission["work_order_digest"] == admitted["work_order_digest"],
             {:refused, :package_work_order_mismatch}
           ),
         :ok <-
           check(package.subject_id == admitted["subject"], {:refused, :package_subject_mismatch}),
         :ok <- check(package.admission["admitted"] == true, {:refused, :package_not_admitted}),
         :ok <- admit_package_bindings(admitted, package),
         :ok <- admit_package_policies(admitted, package),
         :ok <- admit_package_actions(admitted, package) do
      check(
        package.provenance["replay_identity"] == admitted["replay_identity"] and
          package.relationships == admitted["dependencies"],
        {:refused, :package_content_mismatch}
      )
    end
  end

  defp admit_package(_admitted, _other), do: {:error, {:refused, :package_not_runtime_shape}}

  # The package's digest only proves it is self-consistent. Its CONTENT must
  # also say what the WorkOrder says: one repository/base binding, exactly the
  # WorkOrder's, and no binding naming another repository or base.
  defp admit_package_bindings(admitted, package) do
    bindings =
      Enum.filter(package.bindings, &(is_map(&1) and (&1["repository"] || &1["base_sha"])))

    check(
      bindings != [] and
        Enum.all?(
          bindings,
          &(&1["repository"] == admitted["repository"] and &1["base_sha"] == admitted["base_sha"])
        ),
      {:refused, :package_binding_mismatch}
    )
  end

  # `base_must_not_move` and `worker_not_verifier` are enforced, not merely
  # carried: both must be present, the base must be the WorkOrder's, and worker
  # and verifier must be distinct non-empty identities.
  defp admit_package_policies(admitted, package) do
    policies = Enum.filter(package.policies, &is_map/1)
    base_rules = Enum.filter(policies, &(&1["rule"] == "base_must_not_move"))
    separation_rules = Enum.filter(policies, &(&1["rule"] == "worker_not_verifier"))

    with :ok <-
           check(
             base_rules != [] and Enum.all?(base_rules, &(&1["base_sha"] == admitted["base_sha"])),
             {:refused, :package_base_policy_mismatch}
           ) do
      check(
        separation_rules != [] and Enum.all?(separation_rules, &separated?/1),
        {:refused, :package_worker_not_verifier_violated}
      )
    end
  end

  defp separated?(%{"worker" => worker, "verifier" => verifier}),
    do: identity?(worker) and identity?(verifier) and worker != verifier

  defp separated?(_), do: false

  defp identity?(v), do: is_binary(v) and v != ""

  defp admit_package_actions(admitted, package) do
    actions = Enum.filter(package.actions, &is_map/1)

    check(
      Enum.any?(actions, &(&1["kind"] == "bounded_transition")) and
        Enum.all?(
          actions,
          &(&1["work_order_id"] == admitted["identity"] and &1["authority"] == "NONE")
        ),
      {:refused, :package_action_mismatch}
    )
  end

  defp admit_authority(%{"authority_requirement" => "NONE"}, _opts),
    do: {:ok, %{"requirement" => "NONE", "prepared_receipt" => nil, "verified" => true}}

  defp admit_authority(admitted, opts) do
    prepared = opts |> Keyword.get(:authority_receipt) |> stringify()

    if prepared?(prepared, admitted) do
      with {:ok, verified} <- verify_authority(prepared, admitted, opts[:authority_verifier]) do
        {:ok,
         %{
           "requirement" => admitted["authority_requirement"],
           "prepared_receipt" => prepared,
           "verified" => verified
         }}
      end
    else
      {:error, {:refused, :authority_not_prepared}}
    end
  end

  defp prepared?(prepared, admitted) do
    is_map(prepared) and json_safe?(prepared) and prepared["status"] == "prepared" and
      prepared["work_order_digest"] == admitted["work_order_digest"] and
      prepared["subject"] == admitted["subject"] and
      prepared["replay_identity"] == admitted["replay_identity"] and
      identity?(prepared["authority_identity"])
  end

  # The emitter has no claim store or signer (UNSUPPORTED(authority-issuer)), so
  # the trust anchor is the caller's verifier. Without one the prepared receipt
  # is recorded but `verified` is false and it never enters `evidence`.
  defp verify_authority(_prepared, _admitted, nil), do: {:ok, false}

  defp verify_authority(prepared, admitted, verifier) when is_function(verifier, 2) do
    case verifier.(prepared, admitted) do
      :ok -> {:ok, true}
      {:error, reason} -> {:error, {:refused, {:authority_unverified, inspect(reason)}}}
      other -> {:error, {:refused, {:authority_verifier_invalid, inspect(other)}}}
    end
  rescue
    error -> {:error, {:refused, {:authority_verifier_failed, Exception.message(error)}}}
  end

  defp verify_authority(_prepared, _admitted, other),
    do: {:error, {:refused, {:authority_verifier_invalid, inspect(other)}}}

  defp normalize_plan(plan, admitted) when is_map(plan) do
    plan = stringify(plan)

    with {:ok, pinned} <- pinned_commands(admitted),
         {:ok, steps} <- normalize_steps(plan["steps"], admitted),
         {:ok, steps} <- apply_pin(steps, pinned, admitted),
         {:ok, seed} <- normalize_seed(plan["seed_files"] || %{}),
         {:ok, watch} <- normalize_watch(plan["watch"] || []),
         {:ok, source} <- normalize_subject_source(plan["subject_source"], seed) do
      normalized =
        put_subject_source(%{"steps" => steps, "seed_files" => seed, "watch" => watch}, source)

      # Every byte that will later be JSON-encoded to seal the receipt (step
      # ids, argv, seed paths and content, watched paths, the subject source)
      # must have an encoding NOW. Invalid UTF-8 has none, and discovering that
      # after `execute/3` would be an actuation with neither receipt nor refusal.
      with :ok <- check(json_safe?(normalized), {:refused, :plan_not_utf8}), do: {:ok, normalized}
    end
  end

  defp normalize_plan(_, _), do: {:error, {:refused, :plan_not_a_map}}

  defp normalize_steps([_ | _] = steps, admitted) do
    steps
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      case normalize_step(raw, admitted) do
        {:ok, step} -> {:cont, {:ok, [step | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rev} -> unique_ids(Enum.reverse(rev))
      error -> error
    end
  end

  defp normalize_steps(_, _), do: {:error, {:refused, :plan_requires_steps}}

  defp unique_ids(steps) do
    ids = Enum.map(steps, & &1["id"])

    if length(ids) == length(Enum.uniq(ids)),
      do: {:ok, steps},
      else: {:error, {:refused, :duplicate_step_id}}
  end

  defp normalize_step(raw, admitted) when is_map(raw) do
    step =
      raw
      |> stringify()
      |> Map.put_new("expect_exit", 0)
      |> Map.put_new("timeout_ms", @default_timeout_ms)

    with :ok <- validate_step(step),
         {:ok, binds} <- normalize_binds(step["binds"] || %{}, admitted) do
      {:ok, step |> Map.take(~w(id argv expect_exit timeout_ms)) |> Map.put("binds", binds)}
    end
  end

  defp normalize_step(_, _), do: {:error, {:refused, :invalid_step}}

  defp validate_step(step) do
    argv = step["argv"]
    id = step["id"]

    cond do
      not (is_binary(id) and id != "") -> {:error, {:refused, :invalid_step_id}}
      not valid_argv?(argv) -> {:error, {:refused, {:invalid_argv, id}}}
      not is_integer(step["expect_exit"]) -> {:error, {:refused, {:invalid_expect_exit, id}}}
      not valid_timeout?(step["timeout_ms"]) -> {:error, {:refused, {:invalid_timeout, id}}}
      true -> :ok
    end
  end

  defp valid_argv?(argv),
    do: is_list(argv) and argv != [] and Enum.all?(argv, &(is_binary(&1) and &1 != ""))

  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout > 0

  defp normalize_binds(binds, admitted) when is_map(binds) do
    known = %{
      "acceptance" => admitted["acceptance"],
      "falsifiers" => admitted["falsifiers"],
      "courts" => admitted["required_courts"],
      "evidence" => admitted["required_evidence"]
    }

    with :ok <-
           check(Enum.all?(Map.keys(binds), &(&1 in @bind_kinds)), {:refused, :unknown_bind_kind}) do
      bind_each(@bind_kinds, binds, known, %{})
    end
  end

  defp normalize_binds(_, _), do: {:error, {:refused, :invalid_binds}}

  defp bind_each([], _binds, _known, acc), do: {:ok, acc}

  defp bind_each([kind | rest], binds, known, acc) do
    with {:ok, ids} <- normalize_bind(kind, Map.get(binds, kind, []), known[kind]) do
      bind_each(rest, binds, known, Map.put(acc, kind, ids))
    end
  end

  defp normalize_bind(kind, ids, known) do
    cond do
      not (is_list(ids) and Enum.all?(ids, &is_binary/1)) ->
        {:error, {:refused, {:invalid_binds, kind}}}

      unknown = Enum.find(ids, &(&1 not in known)) ->
        {:error, {:refused, {:unknown_binding, kind, unknown}}}

      true ->
        {:ok, ids |> Enum.uniq() |> Enum.sort()}
    end
  end

  defp normalize_seed(seed) when is_map(seed) do
    if Enum.all?(seed, fn {path, content} -> safe_rel?(path) and is_binary(content) end),
      do: {:ok, seed},
      else: {:error, {:refused, :invalid_seed_files}}
  end

  defp normalize_seed(_), do: {:error, {:refused, :invalid_seed_files}}

  defp normalize_watch(watch) when is_list(watch) do
    if Enum.all?(watch, &safe_rel?/1),
      do: {:ok, watch |> Enum.uniq() |> Enum.sort()},
      else: {:error, {:refused, :invalid_watch_path}}
  end

  defp normalize_watch(_), do: {:error, {:refused, :invalid_watch_path}}

  defp safe_rel?(path) do
    is_binary(path) and path != "" and Path.type(path) == :relative and
      ".." not in Path.split(path)
  end

  # -- pinned commands (WorkOrder-declared acceptance commands) --------------

  # `expected_consequence` is free-form in the kernel. Only the shape
  # `%{"commands" => [%{"argv" => [...], "expect_exit" => int}]}` pins commands;
  # any other shape leaves them unpinned; a malformed `commands` is refused.
  defp pinned_commands(%{"expected_consequence" => %{"commands" => [_ | _] = commands}}) do
    pinned =
      Enum.map(commands, fn
        %{"argv" => argv} = command ->
          %{"argv" => argv, "expect_exit" => Map.get(command, "expect_exit", 0)}

        _ ->
          :invalid
      end)

    if Enum.all?(
         pinned,
         &(&1 != :invalid and valid_argv?(&1["argv"]) and is_integer(&1["expect_exit"]))
       ),
       do: {:ok, pinned},
       else: {:error, {:refused, :invalid_expected_consequence}}
  end

  defp pinned_commands(%{"expected_consequence" => %{"commands" => _}}),
    do: {:error, {:refused, :invalid_expected_consequence}}

  defp pinned_commands(_), do: {:ok, nil}

  # A pinned WorkOrder decides the commands AND which claims they back: the
  # plan may not add, drop, reorder or edit steps, and may not choose bindings.
  defp apply_pin(steps, nil, _admitted), do: {:ok, steps}

  defp apply_pin(steps, pinned, admitted) do
    all = all_binds(admitted)

    cond do
      Enum.map(steps, &Map.take(&1, ~w(argv expect_exit))) != pinned ->
        {:error, {:refused, :plan_not_pinned}}

      not Enum.all?(steps, &(&1["binds"] in [all, empty_binds()])) ->
        {:error, {:refused, :pinned_binds_mismatch}}

      true ->
        {:ok, Enum.map(steps, &Map.put(&1, "binds", all))}
    end
  end

  defp all_binds(admitted) do
    %{
      "acceptance" => admitted["acceptance"] |> Enum.uniq() |> Enum.sort(),
      "falsifiers" => admitted["falsifiers"] |> Enum.uniq() |> Enum.sort(),
      "courts" => admitted["required_courts"] |> Enum.uniq() |> Enum.sort(),
      "evidence" => admitted["required_evidence"] |> Enum.uniq() |> Enum.sort()
    }
  end

  defp empty_binds, do: Map.new(@bind_kinds, &{&1, []})

  # -- subject (the WorkOrder's exact commit, materialized) -------------------

  defp normalize_subject_source(nil, _seed), do: {:ok, nil}

  defp normalize_subject_source(source, seed) do
    cond do
      not (is_binary(source) and Path.type(source) == :absolute and String.valid?(source)) ->
        {:error, {:refused, :invalid_subject_source}}

      seed != %{} ->
        {:error, {:refused, :seed_files_with_subject}}

      true ->
        {:ok, source}
    end
  end

  # The WorkOrder names one commit: `candidate_sha` when set, else `base_sha`.
  defp subject_sha(admitted), do: admitted["candidate_sha"] || admitted["base_sha"]
  defp identity_sha(identity), do: identity["candidate_sha"] || identity["base_sha"]

  # Before anything runs: the WorkOrder's exact commit must exist in the named
  # repository, so a run against a subject that is not there is a refusal.
  defp admit_subject(admitted, %{"subject_source" => source}) do
    sha = subject_sha(admitted)

    case resolve_commit(source, sha) do
      {:ok, ^sha} -> :ok
      _ -> {:error, {:refused, {:subject_unavailable, sha}}}
    end
  end

  defp admit_subject(_admitted, _plan), do: :ok

  # `false` for anything that has no JSON encoding: invalid UTF-8 binaries,
  # tuples, pids, refs, functions, structs. Atoms and numbers encode.
  defp json_safe?(v) when is_binary(v), do: String.valid?(v)
  defp json_safe?(v) when is_number(v) or is_boolean(v) or is_nil(v) or is_atom(v), do: true
  defp json_safe?(v) when is_list(v), do: Enum.all?(v, &json_safe?/1)

  defp json_safe?(v) when is_map(v) and not is_struct(v),
    do:
      Enum.all?(v, fn {k, x} ->
        (is_binary(k) or is_atom(k)) and json_safe?(k) and json_safe?(x)
      end)

  defp json_safe?(_), do: false

  # -- construct + actuate ---------------------------------------------------

  # One PRIVATE run directory per execution: created with an exclusive `mkdir`
  # (an existing name is `:eexist`, never shared), mode 0700, named with the OS
  # pid and random bytes because `System.unique_integer/1` is unique per VM only
  # and concurrent VMs share `System.tmp_dir!/0`. `work/` is the command's cwd;
  # per-step stderr files live beside it, outside the command's cwd, and die
  # with the run directory, so no run can read, truncate or delete another's.
  defp execute(plan, sha) do
    case make_run_root(16) do
      {:ok, run_root} ->
        try do
          construct_and_observe(run_root, plan, sha)
        after
          File.rm_rf(run_root)
        end

      {:error, reason} ->
        {:error, {:construct_failed, reason}}
    end
  end

  defp construct_and_observe(run_root, plan, sha) do
    work = Path.join(run_root, "work")

    with :ok <- mkdir(work),
         :ok <- seed(work, plan["seed_files"]),
         {:ok, subject} <- materialize(plan["subject_source"], sha, run_root, work) do
      {:ok, observe(run_root, work, plan, subject)}
    else
      {:error, reason} -> {:error, {:construct_failed, reason}}
    end
  end

  defp make_run_root(0), do: {:error, {:mkdir, :no_unique_run_dir}}

  defp make_run_root(attempts) do
    unique = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    root =
      Path.join(
        System.tmp_dir!(),
        "brce_run_#{System.pid()}_#{System.unique_integer([:positive])}_#{unique}"
      )

    case File.mkdir(root) do
      :ok ->
        case File.chmod(root, 0o700) do
          :ok ->
            {:ok, root}

          {:error, reason} ->
            File.rm_rf(root)
            {:error, {:mkdir, reason}}
        end

      {:error, :eexist} ->
        make_run_root(attempts - 1)

      {:error, reason} ->
        {:error, {:mkdir, reason}}
    end
  end

  defp mkdir(root) do
    case File.mkdir_p(root) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir, reason}}
    end
  end

  defp seed(root, files) do
    Enum.reduce_while(files, :ok, fn {rel, content}, :ok ->
      path = Path.join(root, rel)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, content) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:seed, rel, reason}}}
      end
    end)
  end

  # -- subject materialization (real `git`, real `tar`) ----------------------

  defp materialize(nil, _sha, _run_root, _work), do: {:ok, %{"bound" => false}}

  defp materialize(source, sha, run_root, work) do
    tar = Path.join(run_root, "subject.tar")

    with {:ok, commit} <- resolve_commit(source, sha),
         {:ok, tree} <- git(source, ["rev-parse", "--verify", "--quiet", sha <> "^{tree}"]),
         {:ok, _} <- git(source, ["archive", "--format=tar", "-o", tar, sha]),
         {:ok, _} <- untar(tar, work) do
      {:ok, %{"bound" => commit == sha, "sha" => commit, "tree" => tree, "source" => source}}
    end
  end

  defp resolve_commit(source, sha),
    do: git(source, ["rev-parse", "--verify", "--quiet", sha <> "^{commit}"])

  defp git(source, args) do
    case System.find_executable("git") do
      nil ->
        {:error, {:subject, :git_unavailable}}

      git ->
        # Ambient repository selection would silently point `-C` at another repo.
        env = [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}]

        case System.cmd(git, ["-C", source | args], stderr_to_stdout: true, env: env) do
          {out, 0} -> {:ok, String.trim(out)}
          {out, status} -> {:error, {:subject, hd(args), status, excerpt(out)}}
        end
    end
  end

  defp untar(tar, work) do
    case System.find_executable("tar") do
      nil ->
        {:error, {:subject, :tar_unavailable}}

      tar_exe ->
        case System.cmd(tar_exe, ["-xf", tar, "-C", work], stderr_to_stdout: true) do
          {out, 0} -> {:ok, out}
          {out, status} -> {:error, {:subject, :untar, status, excerpt(out)}}
        end
    end
  end

  defp observe(run_root, work, plan, subject) do
    before_state = file_state(work, plan["watch"])
    steps = run_steps(run_root, work, plan["steps"])
    after_state = file_state(work, plan["watch"])

    files =
      Enum.map(plan["watch"], fn rel ->
        %{
          "path" => rel,
          "before" => before_state[rel],
          "after" => after_state[rel],
          "changed" => before_state[rel] != after_state[rel]
        }
      end)

    %{
      "steps" => steps,
      "files" => files,
      "files_after_digest" => files_after_digest(work, plan["watch"]),
      "portable_files_digest" => portable_files_digest(work, plan["watch"]),
      "subject" => subject
    }
  end

  defp file_state(root, watch) do
    Map.new(watch, fn rel ->
      case File.read(Path.join(root, rel)) do
        {:ok, content} -> {rel, Digest.sha256(content)}
        {:error, _} -> {rel, "absent"}
      end
    end)
  end

  # `Receipt.hash_files/1` hashes the on-disk content but bakes the path it is
  # given into the digest, so this one is specific to this run's scratch dir.
  defp files_after_digest(_root, []), do: nil

  defp files_after_digest(root, watch),
    do: watch |> Enum.map(&Path.join(root, &1)) |> Receipt.hash_files()

  # Same primitive over scratch-relative paths: comparable across runs.
  defp portable_files_digest(_root, []), do: nil

  defp portable_files_digest(root, watch) do
    watch
    |> Enum.map(fn rel ->
      case File.read(Path.join(root, rel)) do
        {:ok, content} -> {rel, content}
        {:error, _} -> {rel, nil}
      end
    end)
    |> Receipt.hash_entries()
  end

  defp run_steps(run_root, work, steps) do
    {records, _halted} =
      steps
      |> Enum.with_index()
      |> Enum.map_reduce(false, fn {step, index}, halted ->
        if halted do
          {skipped(step), true}
        else
          record = run_step(work, Path.join(run_root, "stderr_#{index}"), step)
          {record, not record["passed"]}
        end
      end)

    records
  end

  defp skipped(step) do
    step
    |> Map.take(~w(id argv expect_exit binds))
    |> Map.merge(%{
      "ran" => false,
      "exit_code" => nil,
      "timed_out" => false,
      "passed" => false,
      "stdout_digest" => nil,
      "stderr_digest" => nil,
      "stdout_bytes" => 0,
      "stderr_bytes" => 0,
      "stdout_excerpt" => "",
      "stderr_excerpt" => ""
    })
  end

  defp run_step(work, err, %{"argv" => [exe | args]} = step) do
    {status, out} = exec(work, exe, args, err, step["timeout_ms"])
    stderr = err |> File.read() |> read_or_empty()
    step_record(step, status, out, stderr)
  end

  defp read_or_empty({:ok, body}), do: body
  defp read_or_empty(_), do: ""

  defp exec(root, exe, args, err, timeout) do
    task =
      Task.async(fn ->
        try do
          System.cmd("sh", ["-c", @sh_wrapper, exe | args],
            cd: root,
            env: [{"GGEN_BRCE_STDERR", err}]
          )
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, code}} when is_integer(code) -> {{:exit, code}, out}
      {:ok, {:error, message}} -> {{:error, message}, ""}
      _ -> {:timeout, ""}
    end
  end

  defp step_record(step, status, out, stderr) do
    {exit_code, timed_out} =
      case status do
        {:exit, code} -> {code, false}
        :timeout -> {nil, true}
        {:error, _} -> {nil, false}
      end

    %{
      "id" => step["id"],
      "argv" => step["argv"],
      "expect_exit" => step["expect_exit"],
      "binds" => step["binds"],
      "ran" => true,
      "exit_code" => exit_code,
      "timed_out" => timed_out,
      "passed" => step_passed?(exit_code, step["expect_exit"], timed_out),
      "stdout_digest" => Digest.sha256(out),
      "stderr_digest" => Digest.sha256(stderr),
      "stdout_bytes" => byte_size(out),
      "stderr_bytes" => byte_size(stderr),
      "stdout_excerpt" => excerpt(out),
      "stderr_excerpt" => excerpt(stderr)
    }
  end

  defp step_passed?(exit_code, expect, timed_out),
    do: timed_out != true and is_integer(exit_code) and exit_code == expect

  defp excerpt(bin) do
    bin
    |> binary_part(0, min(byte_size(bin), @excerpt_bytes))
    |> String.replace_invalid()
  end

  # -- receipt ---------------------------------------------------------------

  defp build(admitted, def_digest, package, plan, run, replay, authority, opts) do
    steps = run["steps"]
    success = steps != [] and Enum.all?(steps, & &1["passed"])
    requirements = requirements(admitted)

    identity = %{
      "work_order_id" => admitted["identity"],
      "work_order_digest" => admitted["work_order_digest"],
      "definition_digest" => def_digest,
      "subject" => admitted["subject"],
      "repository" => admitted["repository"],
      "base_sha" => admitted["base_sha"],
      "candidate_sha" => admitted["candidate_sha"],
      "replay_identity" => admitted["replay_identity"],
      "dependencies" => admitted["dependencies"],
      "package_digest" => package.shape_digest,
      "graph_digest" => package.graph_digest,
      "source_digest" => package.source_digest
    }

    consequence = %{
      "steps" => steps,
      "files" => run["files"],
      "files_after_digest" => run["files_after_digest"],
      "portable_files_digest" => run["portable_files_digest"],
      "subject" => run["subject"],
      "exit_code" => aggregate_exit(steps),
      "success" => success,
      "consequence_digest" => SemanticJira.digest(comparable(steps, run["files"], run["subject"]))
    }

    replay_block =
      Map.merge(replay, %{
        "plan" => plan,
        "plan_digest" => SemanticJira.digest(plan),
        "replay_identity" => admitted["replay_identity"],
        "toolchain_identity" => toolchain_identity(),
        "environment_identity" => environment_identity()
      })

    body = %{
      "kind" => @kind,
      "schema" => @schema,
      "receipt_class" => "verification",
      "emitted_by" => Keyword.get(opts, :emitter_identity, @emitter),
      "emitted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "definition_digest" => def_digest,
      "snapshot_digest" => admitted["work_order_digest"],
      "candidate_sha" => admitted["candidate_sha"],
      "target" =>
        Keyword.get(opts, :target) ||
          default_target(admitted, binding_of(identity, requirements, consequence, authority)),
      "identity" => identity,
      "authority" => Map.put(authority, "level", "NONE"),
      "requirements" => requirements,
      "consequence" => consequence,
      "replay" => replay_block,
      "stages" => stages(replay),
      "standing" => %{
        "from" => admitted["standing"],
        "authority" => "NONE",
        "transition_applied" => false
      }
    }

    body
    |> put_in(["standing", "proposed"], body["target"])
    |> then(&Map.put(&1, "evidence", derive_evidence(&1)))
  end

  defp seal(body), do: Map.put(body, "receipt_digest", SemanticJira.digest(body))

  # What a receipt binds the WorkOrder's claims to (see the moduledoc). ALIVE
  # needs every binding; a local run without them is at most PARTIAL_ALIVE.
  defp default_target(admitted, binding) do
    if admitted["evidence_ceiling"] in @attainable_ceilings and exact?(binding),
      do: "ALIVE",
      else: "PARTIAL_ALIVE"
  end

  defp requirements(admitted) do
    %{
      "acceptance" => admitted["acceptance"],
      "falsifiers" => admitted["falsifiers"],
      "courts" => admitted["required_courts"],
      "evidence" => admitted["required_evidence"],
      "receipt_classes" => admitted["required_receipt_classes"],
      "replay_required" => admitted["replay_required"],
      "evidence_ceiling" => admitted["evidence_ceiling"],
      "pinned_commands" =>
        case pinned_commands(admitted) do
          {:ok, pinned} -> pinned
          {:error, _} -> :invalid
        end
    }
  end

  # Derived ONLY from the consequence, identity, requirements and authority
  # sections, so `verify/2` re-derives the same answer.
  defp binding_of(identity, requirements, consequence, authority) do
    subject = consequence["subject"]

    %{
      "subject" =>
        is_map(subject) and subject["bound"] == true and
          subject["sha"] == identity_sha(identity),
      "commands_pinned" => is_list(requirements["pinned_commands"]),
      "authority" => authority["requirement"] == "NONE" or authority["verified"] == true
    }
  end

  defp exact?(binding), do: Enum.all?(Map.values(binding), &(&1 == true))

  defp aggregate_exit(steps) do
    case Enum.find(steps, &(not &1["passed"])) do
      nil -> 0
      %{"exit_code" => nil} -> -1
      %{"exit_code" => code} -> if code == 0, do: -1, else: code
    end
  end

  defp stages(replay) do
    %{
      "parse" => "executed",
      "route" => "UNSUPPORTED(single-route)",
      "admit" => "executed",
      "diagnose_repair" => "UNSUPPORTED",
      "construct" => "executed",
      "actuate" => "executed",
      "receipt" => "executed",
      "replay" => if(replay["requested"], do: "executed", else: "skipped"),
      "standing" => "not_applied(reconciler-owned)"
    }
  end

  # Only what a step observed and the WorkOrder names can be evidence.
  defp derive_evidence(receipt) do
    steps = receipt["consequence"]["steps"]
    req = receipt["requirements"]
    id = receipt["identity"]
    success = receipt["consequence"]["success"] == true
    replay_passed = success and receipt["replay"]["passed"] == true

    binding =
      binding_of(id, req, receipt["consequence"], receipt["authority"])

    # `observed_execution` means an observed run of the exact admitted subject
    # under the WorkOrder's own commands and authority, not merely a run.
    observed = Enum.any?(steps, & &1["ran"]) and exact?(binding)

    bound = fn kind ->
      steps |> Enum.filter(& &1["passed"]) |> Enum.flat_map(&(&1["binds"][kind] || []))
    end

    evidence = %{
      "subject" => id["subject"],
      "repository" => id["repository"],
      "base_sha" => id["base_sha"],
      "evidence_types" => bound.("evidence") |> Enum.uniq() |> Enum.sort(),
      "court_results" => Map.new(req["courts"], &{&1, %{"passed" => &1 in bound.("courts")}}),
      "acceptance_results" => Map.new(req["acceptance"], &{&1, &1 in bound.("acceptance")}),
      "falsifier_results" =>
        Map.new(req["falsifiers"], &{&1, survived(&1 in bound.("falsifiers"))}),
      "receipt_classes" => receipt_classes(success, replay_passed),
      "evidence_ceiling" => if(observed, do: "observed", else: "none"),
      "observed_execution" => observed,
      "binding" => binding,
      "replay_passed" => replay_passed,
      "replay_identity" => if(replay_passed, do: id["replay_identity"], else: nil)
    }

    # An authority receipt nobody verified is recorded in `authority` but is not
    # evidence: promotion then fails its `authority` check.
    case {receipt["authority"]["prepared_receipt"], receipt["authority"]["verified"]} do
      {nil, _} -> evidence
      {prepared, true} -> Map.put(evidence, "authority_receipt", prepared)
      {_, _} -> evidence
    end
  end

  defp survived(true), do: "survived"
  defp survived(false), do: "failed"

  defp receipt_classes(success, replay_passed) do
    if(success, do: ["verification"], else: []) ++ if(replay_passed, do: ["replay"], else: [])
  end

  # -- replay ----------------------------------------------------------------

  defp replay_section(plan, run, admitted, package, opts) do
    if Keyword.get(opts, :replay, admitted["replay_required"]) == true do
      context = %{
        "subject" => admitted["subject"],
        "dependencies" => admitted["dependencies"],
        "graph_digest" => package.graph_digest,
        "replay_identity" => admitted["replay_identity"],
        "consequence_digest" => consequence_digest(run),
        "toolchain_identity" => toolchain_identity(),
        "environment_identity" => environment_identity()
      }

      case execute(plan, subject_sha(admitted)) do
        {:ok, again} -> replay_verdict(compare(context, again))
        {:error, reason} -> %{"requested" => true, "passed" => false, "error" => inspect(reason)}
      end
    else
      %{"requested" => false, "passed" => nil}
    end
  end

  defp replay_verdict({:ok, replay_receipt}),
    do: %{
      "requested" => true,
      "passed" => true,
      "replay_receipt_digest" => replay_receipt["receipt_digest"]
    }

  defp replay_verdict({:error, {:replay_refused, {:identity_mismatch, mismatches}}}),
    do: %{
      "requested" => true,
      "passed" => false,
      "mismatched_fields" => Enum.map(mismatches, & &1["field"])
    }

  defp replay_verdict({:error, {:replay_refused, reason}}),
    do: %{"requested" => true, "passed" => false, "error" => inspect(reason)}

  # What the receipt recorded, as the expected side of `replay_check/2`.
  defp receipt_context(receipt) do
    id = receipt["identity"]

    %{
      "subject" => id["subject"],
      "dependencies" => id["dependencies"],
      "graph_digest" => id["graph_digest"],
      "replay_identity" => id["replay_identity"],
      "consequence_digest" => receipt["consequence"]["consequence_digest"],
      "toolchain_identity" => receipt["replay"]["toolchain_identity"],
      "environment_identity" => receipt["replay"]["environment_identity"]
    }
  end

  # Expected = `context` (recorded). Observed = the fresh run under THIS
  # process's toolchain/environment identity. Every value is a non-blank
  # string because `replay_check/2` treats blank/empty values as missing.
  defp compare(context, run) do
    expected = replay_subject(context)

    observed =
      replay_subject(%{
        context
        | "consequence_digest" => consequence_digest(run),
          "toolchain_identity" => toolchain_identity(),
          "environment_identity" => environment_identity()
      })

    SemanticJira.replay_check(expected, observed)
  end

  defp replay_subject(context) do
    %{
      "pack_subject" => context["subject"],
      "dependency_set" => SemanticJira.digest(%{"dependencies" => context["dependencies"]}),
      "graph_digest" => context["graph_digest"],
      "consequence_set" => context["consequence_digest"],
      "toolchain_identity" => context["toolchain_identity"],
      "environment_identity" => context["environment_identity"],
      "replay_identity" => context["replay_identity"]
    }
  end

  defp consequence_digest(run),
    do: SemanticJira.digest(comparable(run["steps"], run["files"], run["subject"]))

  # Comparable = what a faithful re-run must reproduce. stderr and excerpts are
  # recorded but not compared (they may carry scratch paths).
  defp comparable(steps, files, subject) do
    %{
      "subject" => Map.take(subject || %{}, ~w(bound sha tree)),
      "steps" =>
        Enum.map(
          steps,
          &Map.take(&1, ~w(id ran exit_code timed_out passed stdout_digest))
        ),
      "files" => Enum.map(files, &Map.take(&1, ~w(path after)))
    }
  end

  defp toolchain_identity, do: "elixir:#{System.version()}-otp-#{System.otp_release()}"

  defp environment_identity do
    {family, name} = :os.type()
    "#{family}:#{name}"
  end

  # -- verification ----------------------------------------------------------

  defp check_binding(r) do
    id = r["identity"] || %{}
    ev = r["evidence"] || %{}

    with :ok <-
           check(id["work_order_digest"] == r["snapshot_digest"], :snapshot_identity_mismatch),
         :ok <-
           check(id["definition_digest"] == r["definition_digest"], :definition_identity_mismatch),
         :ok <- check(id["candidate_sha"] == r["candidate_sha"], :candidate_identity_mismatch),
         :ok <-
           check(
             ev["subject"] == id["subject"] and ev["repository"] == id["repository"] and
               ev["base_sha"] == id["base_sha"],
             :evidence_subject_mismatch
           ) do
      check(r["standing"]["proposed"] == r["target"], :standing_target_mismatch)
    end
  end

  defp check_derivation(r) do
    c = r["consequence"] || %{}
    steps = c["steps"]

    with :ok <- check(is_list(steps) and steps != [], :missing_steps),
         :ok <-
           check(
             Enum.all?(steps, fn s ->
               s["passed"] ==
                 (s["ran"] == true and
                    step_passed?(s["exit_code"], s["expect_exit"], s["timed_out"]))
             end),
             :step_result_mismatch
           ),
         :ok <- check(c["success"] == Enum.all?(steps, & &1["passed"]), :success_mismatch),
         :ok <- check(c["exit_code"] == aggregate_exit(steps), :exit_code_mismatch),
         :ok <-
           check(
             c["consequence_digest"] ==
               SemanticJira.digest(comparable(steps, c["files"] || [], c["subject"])),
             :consequence_digest_mismatch
           ) do
      check(r["evidence"] == derive_evidence(r), :evidence_not_derived_from_consequence)
    end
  end

  defp check_work_order(_receipt, nil), do: :ok

  defp check_work_order(receipt, work_order) do
    with {:ok, admitted} <- SemanticJira.admit_work_order(work_order),
         {:ok, def_digest} <- SemanticJira.definition_digest(work_order),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch),
         :ok <- check(receipt["requirements"] == requirements(admitted), :requirements_mismatch) do
      check_pinned_steps(receipt, admitted)
    end
  end

  # A pinned WorkOrder's receipt must have run exactly the pinned commands.
  defp check_pinned_steps(receipt, admitted) do
    case pinned_commands(admitted) do
      {:ok, nil} ->
        :ok

      {:ok, pinned} ->
        ran = Enum.map(receipt["consequence"]["steps"], &Map.take(&1, ~w(argv expect_exit)))
        check(ran == pinned, :steps_not_pinned)

      {:error, _} ->
        {:error, :requirements_mismatch}
    end
  end

  defp check(true, _), do: :ok
  defp check(_, reason), do: {:error, reason}

  defp digest?(v), do: is_binary(v) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, v)

  defp stringify(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {to_string(k), stringify(x)} end)

  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v
end
