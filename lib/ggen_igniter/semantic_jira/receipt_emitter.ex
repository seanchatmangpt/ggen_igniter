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

    * parse: `normalize_plan/2` (steps, seed files, watched files) -- executed.
    * route: UNSUPPORTED(single-route) -- one route only, local `sh` subprocess.
    * admit/refuse: `emit/4` admits the WorkOrder (`SemanticJira.admit_work_order/1`),
      the `RuntimeShape` execution package (digest + `work_order_digest`/`subject`
      binding), the plan (bindings must name real acceptance/falsifier/court/
      evidence ids of the WorkOrder) and authority (a non-`NONE`
      `authority_requirement` needs a matching prepared authority receipt) BEFORE
      anything runs; any failure is `{:error, {:refused, reason}}`.
    * diagnose/repair: UNSUPPORTED -- a failing run yields a non-success
      receipt; `SemanticJira.repair_work_order/2` lineage is not driven from here.
    * construct: a fresh scratch dir under `System.tmp_dir!/0`, seeded with the
      plan's `seed_files` -- executed.
    * actuate: each step is a real `System.cmd("sh", ...)` subprocess in the
      scratch dir (`exec "$0" "$@"` wrapper so stdout and stderr are captured
      separately; POSIX `sh` required). Fail-fast: steps after a failed step are
      recorded `ran: false`. Only cwd is scoped -- there is no filesystem
      sandbox and a timeout kills the Elixir task, not the OS process group
      (UNSUPPORTED(isolation)).
    * receipt: `emit/4` builds a digest-sealed map (`"receipt_digest"`, the same
      `SemanticJira.digest/1` the log uses) with `identity`, `authority`,
      `requirements`, `consequence` (per-step exit code, stdout/stderr digests,
      watched-file before/after content digests plus
      `GgenIgniter.Receipt.hash_files/1` and a portable
      `GgenIgniter.Receipt.hash_entries/1` digest), `replay` (the normalized plan,
      toolchain/environment identity, replay verdict), `evidence` (DERIVED from
      the consequence, never asserted) and `standing` (the target the receipt
      supports; `transition_applied` is always false).
    * replay: `replay/2` re-runs a trusted plan in a fresh scratch dir and
      compares the comparable consequence via `SemanticJira.replay_check/2`;
      `emit/4` does it inline when `replay: true` or the WorkOrder has
      `replay_required`.
    * standing: not applied here -- `Reconciler.reconcile/4` owns the transition.

  ## Verification

  `verify/2` refuses a receipt whose seal does not match its body, whose
  derived fields (per-step `passed`, `success`, `exit_code`,
  `consequence_digest`, `evidence`, `standing.proposed`) do not re-derive from
  its consequence, or (with a WorkOrder) whose requirements/identity do not
  match. `check_success/1` refuses a sealed receipt of a run that did not
  succeed. `Reconciler.reconcile/4` calls both for any emitted/sealed receipt
  and, with `require_sealed: true`, refuses hand-built receipts.

  ## Disclosed limits

    * The seal is a content digest (integrity), not a signature: a forger who
      recomputes seal and every derived field yields a self-consistent receipt.
      `replay/2` (and `Reconciler` option `replay_plan: plan`, which replays a
      TRUSTED plan whose digest must equal the receipt's, never the receipt's own
      embedded argv) is the mitigation for deterministic plans: a forged
      consequence will not reproduce. Nondeterministic plans (timestamps, pids in
      stdout) fail replay.
    * A failing run cannot lawfully move standing to BLOCKED/BUILD_BROKEN:
      `SemanticJira.promote/3` requires every check for every target. The
      receipt is refused for transition and standing stays.
    * The only evidence ceiling this emitter can attest is `"observed"`; for a
      WorkOrder with another ceiling the receipt proposes `PARTIAL_ALIVE`.
    * Authority stays NONE; the emitter grants nothing.
  """

  alias GgenIgniter.{Digest, Receipt, RuntimeShape, SemanticJira}

  @kind "brce_receipt"
  @schema "semantic-jira/brce-receipt/v1"
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
  `:seed_files` (`%{relative_path => text}`), `:watch` (relative paths).
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
       }}
    end
  end

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
  `evidence`), optional `seed_files` and `watch`.

  Options: `:target` (default derived), `:replay` (default: WorkOrder's
  `replay_required`), `:authority_receipt` (prepared authority receipt for a
  WorkOrder whose `authority_requirement` is not `NONE`), `:emitter_identity`.

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
         :ok <- admit_package(admitted, package),
         {:ok, authority} <- admit_authority(admitted, opts),
         {:ok, plan} <- normalize_plan(plan, admitted),
         {:ok, run} <- execute(plan) do
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
         {:ok, run} <- execute(plan) do
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

  defp admit(work_order) do
    case SemanticJira.admit_work_order(work_order) do
      {:ok, admitted} -> {:ok, admitted}
      {:error, reason} -> {:error, {:refused, {:work_order, reason}}}
    end
  end

  defp refuse({:ok, v}), do: {:ok, v}
  defp refuse({:error, reason}), do: {:error, {:refused, {:work_order, reason}}}

  defp admit_package(admitted, %RuntimeShape{} = package) do
    cond do
      RuntimeShape.digest(package) != package.shape_digest ->
        {:error, {:refused, :package_digest_mismatch}}

      package.admission["work_order_digest"] != admitted["work_order_digest"] ->
        {:error, {:refused, :package_work_order_mismatch}}

      package.subject_id != admitted["subject"] ->
        {:error, {:refused, :package_subject_mismatch}}

      true ->
        :ok
    end
  end

  defp admit_package(_admitted, _other), do: {:error, {:refused, :package_not_runtime_shape}}

  defp admit_authority(%{"authority_requirement" => "NONE"}, _opts),
    do: {:ok, %{"requirement" => "NONE", "prepared_receipt" => nil}}

  defp admit_authority(admitted, opts) do
    prepared = opts |> Keyword.get(:authority_receipt) |> stringify()

    if is_map(prepared) and prepared["status"] == "prepared" and
         prepared["work_order_digest"] == admitted["work_order_digest"] and
         prepared["subject"] == admitted["subject"] and
         prepared["replay_identity"] == admitted["replay_identity"] do
      {:ok, %{"requirement" => admitted["authority_requirement"], "prepared_receipt" => prepared}}
    else
      {:error, {:refused, :authority_not_prepared}}
    end
  end

  defp normalize_plan(plan, admitted) when is_map(plan) do
    plan = stringify(plan)

    with {:ok, steps} <- normalize_steps(plan["steps"], admitted),
         {:ok, seed} <- normalize_seed(plan["seed_files"] || %{}),
         {:ok, watch} <- normalize_watch(plan["watch"] || []) do
      {:ok, %{"steps" => steps, "seed_files" => seed, "watch" => watch}}
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

  # -- construct + actuate ---------------------------------------------------

  defp execute(plan) do
    root =
      Path.join(
        System.tmp_dir!(),
        "brce_run_#{System.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
      )

    with :ok <- mkdir(root),
         :ok <- seed(root, plan["seed_files"]) do
      try do
        {:ok, observe(root, plan)}
      after
        File.rm_rf(root)
      end
    else
      {:error, reason} ->
        File.rm_rf(root)
        {:error, {:construct_failed, reason}}
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

  defp observe(root, plan) do
    before_state = file_state(root, plan["watch"])
    steps = run_steps(root, plan["steps"])
    after_state = file_state(root, plan["watch"])

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
      "files_after_digest" => files_after_digest(root, plan["watch"]),
      "portable_files_digest" => portable_files_digest(root, plan["watch"])
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

  defp run_steps(root, steps) do
    {records, _halted} =
      Enum.map_reduce(steps, false, fn step, halted ->
        if halted do
          {skipped(step), true}
        else
          record = run_step(root, step)
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

  defp run_step(root, %{"argv" => [exe | args]} = step) do
    err = Path.join(System.tmp_dir!(), "brce_err_#{System.unique_integer([:positive])}")

    try do
      {status, out} = exec(root, exe, args, err, step["timeout_ms"])
      stderr = err |> File.read() |> read_or_empty()
      step_record(step, status, out, stderr)
    after
      File.rm(err)
    end
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

    requirements = %{
      "acceptance" => admitted["acceptance"],
      "falsifiers" => admitted["falsifiers"],
      "courts" => admitted["required_courts"],
      "evidence" => admitted["required_evidence"],
      "receipt_classes" => admitted["required_receipt_classes"],
      "replay_required" => admitted["replay_required"],
      "evidence_ceiling" => admitted["evidence_ceiling"]
    }

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
      "exit_code" => aggregate_exit(steps),
      "success" => success,
      "consequence_digest" => SemanticJira.digest(comparable(steps, run["files"]))
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
      "target" => Keyword.get(opts, :target) || default_target(admitted),
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

  defp default_target(admitted),
    do:
      if(admitted["evidence_ceiling"] in @attainable_ceilings, do: "ALIVE", else: "PARTIAL_ALIVE")

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
    observed = Enum.any?(steps, & &1["ran"])

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
      "replay_passed" => replay_passed,
      "replay_identity" => if(replay_passed, do: id["replay_identity"], else: nil)
    }

    case receipt["authority"]["prepared_receipt"] do
      nil -> evidence
      prepared -> Map.put(evidence, "authority_receipt", prepared)
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

      case execute(plan) do
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

  defp consequence_digest(run), do: SemanticJira.digest(comparable(run["steps"], run["files"]))

  # Comparable = what a faithful re-run must reproduce. stderr and excerpts are
  # recorded but not compared (they may carry scratch paths).
  defp comparable(steps, files) do
    %{
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
             c["consequence_digest"] == SemanticJira.digest(comparable(steps, c["files"] || [])),
             :consequence_digest_mismatch
           ) do
      check(r["evidence"] == derive_evidence(r), :evidence_not_derived_from_consequence)
    end
  end

  defp check_work_order(_receipt, nil), do: :ok

  defp check_work_order(receipt, work_order) do
    with {:ok, admitted} <- SemanticJira.admit_work_order(work_order),
         {:ok, def_digest} <- SemanticJira.definition_digest(work_order),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch) do
      check(
        receipt["requirements"] ==
          %{
            "acceptance" => admitted["acceptance"],
            "falsifiers" => admitted["falsifiers"],
            "courts" => admitted["required_courts"],
            "evidence" => admitted["required_evidence"],
            "receipt_classes" => admitted["required_receipt_classes"],
            "replay_required" => admitted["replay_required"],
            "evidence_ceiling" => admitted["evidence_ceiling"]
          },
        :requirements_mismatch
      )
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
