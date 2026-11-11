defmodule GgenIgniter.LandingPipeline do
  @moduledoc """
  One candidate landing driven through the FIXED ordered stage registry, in
  process, mirroring `GgenIgniter.SemanticJira.Execute`'s
  invocation-boundary/typed-refusal/receipt discipline.

      LandingPipeline.run(base: "HEAD", worktree_sha: sha, paths: [...], opts: [...])

  Stages are real behaviour implementations of
  `GgenIgniter.LandingPipeline.Stage`. The registry is FIXED and ORDERED —
  the order is load-bearing: **risk tier (order 2) precedes fan-out review
  (order 4)**, so the review width is chosen only after the change has been
  classified, and a high-risk diff can never select its own reviewers.
  `Enum.reduce_while/3` short-circuits on the FIRST `:block`/`:refused` —
  later stages never run once an earlier gate refuses.

  Stage resolution is fail-closed: each registry module atom goes through
  `Code.ensure_loaded/1`, and a module that does not exist is the typed
  refusal `{:stage_module_missing, module}` — never a silent skip. This is
  what makes the pipeline independently landable while the individual stage
  modules are owned by other lanes: the pipeline is complete when its own
  tests pass, and a missing stage is a verdict, not a crash.

  ## Stage 0: base_integrity (implemented here, not in a stage module)

  Before any registry stage runs, the base premise is proven against real
  git: `git rev-parse --verify <base>` (the base exists),
  `git merge-base --is-ancestor <base> HEAD` (the base is on this history),
  and the worktree-drift check — `git rev-parse HEAD` must equal the
  caller-declared `worktree_sha` when one is given (drift = `:base_drift`,
  the same `mu_on_O` discipline as `SemanticJira.Execute`'s
  `base_head/2`). All git calls are `System.cmd/3` with list args; captured
  output is embedded in the stage-0 receipt. `worktree_sha` defaults to the
  observed HEAD when the caller declares none (observe-don't-guess).

  ## Receipts (never-a-single-boolean)

  Per-stage receipts are written to
  `<receipts_dir>/<run_id>/stage-<order>-<name>.json` and the final report
  to `<receipts_dir>/<run_id>/landing-receipt.json` (default `receipts_dir`:
  `.ggen_igniter/receipts/pipeline` under the cwd, overridable via
  `opts[:receipts_dir]`). The final `status` is `"ALIVE"` only when EVERY
  stage — including stage 0 — passed AND every embedded output is real
  (`GgenIgniter.LandingPipeline.Stage.capture/3`'s shape: non-empty
  `command`, integer `exit`, binary `stdout_tail`, non-negative
  `duration_ms`). Otherwise the status is `"BLOCKED"` naming the FIRST
  blocking stage plus the full per-stage list — the same
  never-a-single-boolean law as `GgenIgniter.GateVerify`. A `:pass` with an
  empty embedded output is INVALID: it is recorded and BLOCKS (reason
  `{:invalid_stage_output, name}`), so a vacuous pass can never mint ALIVE.

  ### Optional F2 measurement field

  `opts[:human_minutes]` — human implementation-minutes spent on the landed
  capability — is emitted into the landing receipt ONLY when set to an
  integer (`put_optional/3`). An unset value emits no key at all, so
  old-shape receipts rebuild byte-identical (the same stability law as
  `GgenIgniter.Receipt`'s optional risk fields).

  ## Return contract (the epoch.check exit law)

    * `{0, report}` — every stage passed with real output (`"ALIVE"`)
    * `{1, report}` — base drift, first-stage block/refusal, or any invalid
      stage output (`"BLOCKED"`)
    * `{2, %{"status" => "invalid_invocation", "reason" => ...}}` — missing
      or malformed invocation input (e.g. no `--base`)

  Disclosed follow-on: the seven concrete stage modules
  (`EpochCheck`, `RiskTier`, `BuildGate`, `FanoutReview`, `SecurityBlock`,
  `ConvergenceCap`, `IncidentEval`) are other lanes' files; until they land,
  real runs refuse `stage_module_missing` at the first absent one — by
  design. `opts[:stages]` is the test/injection seam (a list of real
  behaviour implementations replacing the fixed registry, run in the given
  order — the fixed registry is authored in `order/0` order — and still
  short-circuiting); production callers pass nothing.
  """

  alias GgenIgniter.LandingPipeline.Stage

  @fixed_registry [
    {1, :epoch_check, GgenIgniter.LandingPipeline.Stage.EpochCheck},
    {2, :risk_tier, GgenIgniter.LandingPipeline.Stage.RiskTier},
    {3, :build_gate, GgenIgniter.LandingPipeline.Stage.BuildGate},
    {4, :fanout_review, GgenIgniter.LandingPipeline.Stage.FanoutReview},
    {5, :security_block, GgenIgniter.LandingPipeline.Stage.SecurityBlock},
    {6, :convergence_cap, GgenIgniter.LandingPipeline.Stage.ConvergenceCap},
    {7, :incident_eval, GgenIgniter.LandingPipeline.Stage.IncidentEval}
  ]

  @default_receipts_dir ".ggen_igniter/receipts/pipeline"
  @base_stage %{"stage" => "base_integrity", "order" => 0}

  @spec run(keyword()) :: {0 | 1 | 2, map()}
  def run(opts) do
    case base_integrity(opts) do
      {:invalid, reason} ->
        {2, %{"status" => "invalid_invocation", "reason" => reason}}

      {:error, base_receipt} ->
        finish(opts, "BLOCKED", {:base_integrity, base_receipt["reason"]}, [base_receipt])

      {:ok, base_sha, worktree_sha, base_receipt} ->
        drive(opts, base_sha, worktree_sha, base_receipt)
    end
  end

  # ── stage 0: base integrity ─────────────────────────────────────────────────

  defp base_integrity(opts) do
    base = opts[:base]

    unless is_binary(base) and base != "" do
      throw_invalid("missing --base")
    end

    rev_parse = Stage.capture("git", ["rev-parse", "--verify", base])

    if rev_parse["exit"] != 0 do
      {:error, block_receipt(@base_stage, {:base_unresolvable, base}, [rev_parse])}
    else
      base_sha = String.trim(rev_parse["stdout_tail"])

      ancestor =
        Stage.capture("git", ["merge-base", "--is-ancestor", base, "HEAD"])

      cond do
        ancestor["exit"] != 0 ->
          {:error,
           block_receipt(@base_stage, {:base_not_ancestor, base}, [rev_parse, ancestor])}

        true ->
          head = Stage.capture("git", ["rev-parse", "HEAD"])
          head_sha = String.trim(head["stdout_tail"])
          declared = opts[:worktree_sha]

          cond do
            head["exit"] != 0 ->
              {:error, block_receipt(@base_stage, {:head_unresolvable, base}, [rev_parse, ancestor, head])}

            is_binary(declared) and declared != head_sha ->
              {:error,
               block_receipt(@base_stage, {:base_drift, declared, head_sha}, [
                 rev_parse,
                 ancestor,
                 head
               ])}

            true ->
              receipt =
                pass_receipt(@base_stage, [rev_parse, ancestor, head])
                |> Map.merge(%{"base_sha" => base_sha, "worktree_sha" => head_sha})

              {:ok, base_sha, declared || head_sha, receipt}
          end
      end
    end
  catch
    {:invalid, reason} -> {:invalid, reason}
  end

  # ── the fixed registry drive ────────────────────────────────────────────────

  defp drive(opts, base_sha, worktree_sha, base_receipt) do
    # The registry list is authored in order/0 order (the fixed registry is
    # written 1..7 top to bottom); order/0 LABELS receipts and reports, it is
    # never dereferenced for sorting — a stage module that does not load must
    # be refused AT ITS SLOT, not sorted to the end.
    stages = Keyword.get(opts, :stages, registry_modules())

    ctx = %Stage{
      base_sha: base_sha,
      worktree_sha: worktree_sha,
      paths: Keyword.get(opts, :paths, []),
      opts: opts
    }

    {halted, receipts_rev} =
      Enum.reduce_while(stages, {nil, []}, fn module, {_, acc} ->
        entry = run_stage(module, ctx)

        case entry["status"] do
          "pass" -> {:cont, {nil, [entry | acc]}}
          _ -> {:halt, {entry, [entry | acc]}}
        end
      end)

    receipts =
      [base_receipt | Enum.reverse(receipts_rev)]
      |> Enum.map(&Map.put(&1, "finished_at", iso8601_now()))

    case halted do
      nil ->
        finish(opts, "ALIVE", nil, receipts)

      entry ->
        finish(opts, "BLOCKED", {entry["stage"], entry["reason"]}, receipts)
    end
  end

  defp run_stage(module, ctx) do
    # Code.ensure_loaded BEFORE any function_exported?/name/order consult: in
    # every real CLI run this is a fresh VM, so a header built before loading
    # hits the fallback below and mislabels the stage's order slot (witnessed:
    # epoch_check receipted as `stage-0-epoch_check.json`, 0-based find_index,
    # while its order/0 says 1).
    case Code.ensure_loaded(module) do
      {:error, reason} ->
        %{"stage" => fallback_label(module), "order" => fallback_order(module)}
        |> Map.merge(%{
          "status" => "refused",
          "reason" => {:stage_module_missing, module, reason},
          "output" => nil
        })

      {:module, _} ->
        header = %{"stage" => to_string(module.name()), "order" => module.order()}

        case apply(module, :run, [ctx]) do
          {:pass, receipt} ->
            if real_output?(receipt["output"]) do
              header |> Map.merge(pass_receipt(header, nil) |> Map.merge(receipt)) |> Map.put("status", "pass")
            else
              block_receipt(
                header,
                {:invalid_stage_output, header["stage"]},
                receipt["output"]
              )
            end

          {:block, reason, receipt} ->
            block_receipt(header, reason, receipt["output"])

          {:refused, reason} ->
            header |> Map.merge(%{"status" => "refused", "reason" => reason, "output" => nil})

          other ->
            block_receipt(header, {:bad_stage_return, other}, nil)
        end
    end
  end

  # A missing stage module has no name/0 or order/0 to call: the receipt label
  # and order slot fall back to the MODULE NAME (underscored last segment) and
  # its 1-BASED fixed-registry slot (Enum.find_index is 0-based — the +1 keeps
  # the fallback numbering equal to the registry's own `order/0` contract; a
  # module outside the registry keeps the historical -1). The refusal is still
  # typed and still short-circuits.
  defp fallback_label(module),
    do: module |> Module.split() |> List.last() |> Macro.underscore()

  defp fallback_order(module) do
    case Enum.find_index(registry_modules(), &(&1 == module)) do
      nil -> -1
      index -> index + 1
    end
  end

  defp registry_modules do
    Enum.map(@fixed_registry, fn {_order, _name, module} -> module end)
  end

  # ── receipt shapes ──────────────────────────────────────────────────────────

  defp pass_receipt(header, outputs),
    do: Map.merge(header, %{"status" => "pass", "reason" => nil, "output" => wrap(outputs)})

  defp block_receipt(header, reason, outputs),
    do:
      Map.merge(header, %{
        "status" => "block",
        "reason" => reason,
        "output" => wrap(outputs)
      })

  defp wrap(nil), do: nil
  defp wrap(outputs) when is_list(outputs), do: %{"commands" => outputs}
  defp wrap(%{} = single), do: single

  # The realness law: an embedded output is real only when it is either one
  # `Stage.capture/3`-shaped map or a non-empty list of them, each carrying a
  # non-empty command, an integer exit, a binary stdout_tail and a
  # non-negative integer duration. This is what makes "a :pass with empty
  # embedded output is invalid" mechanically checkable.
  defp real_output?(%{"commands" => cmds}) when is_list(cmds) and cmds != [],
    do: Enum.all?(cmds, &real_command?/1)

  defp real_output?(%{} = o), do: real_command?(o)
  defp real_output?(_), do: false

  defp real_command?(%{
         "command" => cmd,
         "exit" => exit_code,
         "stdout_tail" => out,
         "duration_ms" => ms
       })
       when is_binary(cmd) and cmd != "" and is_integer(exit_code) and is_binary(out) and
              is_integer(ms) and ms >= 0,
       do: true

  defp real_command?(_), do: false

  # ── final receipt ───────────────────────────────────────────────────────────

  defp finish(opts, status, first_block, receipts) do
    run_id = Keyword.get(opts, :run_id) || new_run_id()
    dir = receipts_root(opts)
    run_dir = Path.join(dir, run_id)

    File.mkdir_p!(run_dir)

    Enum.each(receipts, fn receipt ->
      path =
        Path.join(run_dir, "stage-#{receipt["order"]}-#{receipt["stage"]}.json")

      File.write!(path, Jason.encode!(jsonable(receipt), pretty: true) <> "\n")
    end)

    report =
      %{
        "run_id" => run_id,
        "status" => status,
        "epoch" => opts[:epoch],
        "first_block" =>
          case first_block do
            nil -> nil
            {stage, reason} -> %{"stage" => to_string(stage), "reason" => jsonable(reason)}
          end,
        "stages" => Enum.map(receipts, &jsonable/1)
      }
      |> put_optional(opts, :human_minutes)
      |> drop_nils()

    File.write!(
      Path.join(run_dir, "landing-receipt.json"),
      Jason.encode!(report, pretty: true) <> "\n"
    )

    exit_code = if status == "ALIVE", do: 0, else: 1
    {exit_code, Map.put(report, "receipts_dir" |> to_string(), run_dir)}
  end

  defp receipts_root(opts) do
    case Keyword.get(opts, :receipts_dir) do
      dir when is_binary(dir) and dir != "" -> Path.expand(dir)
      _ -> Path.expand(@default_receipts_dir)
    end
  end

  defp new_run_id,
    do:
      "pl-" <>
        Integer.to_string(System.os_time(:second)) <> "-" <> Integer.to_string(System.unique_integer([:positive]))

  defp iso8601_now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  # F2 measurement seed (v26.10.20): `opts[:human_minutes]` — the human
  # implementation-minutes spent on the landed capability this run carries —
  # is emitted into the landing receipt ONLY when explicitly set and an
  # integer. Unset (or non-integer) input emits no key at all, so a receipt
  # built without it is byte-identical to a pre-field receipt (the same
  # put_optional/hash-chain-stability law as `GgenIgniter.Receipt`'s
  # risk_tier/risk_score/risk_approvals fields).
  defp put_optional(report, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) -> Map.put(report, to_string(key), value)
      _ -> report
    end
  end

  # ── typed reasons are JSON'd losslessly enough to branch on (the same
  # rendering `SemanticJira.Execute.jsonable/1` applies) ───────────────────────

  defp jsonable(value) when is_tuple(value), do: value |> Tuple.to_list() |> jsonable()
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)

  defp jsonable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp jsonable(value), do: value

  defp throw_invalid(reason), do: throw({:invalid, reason})
end
