defmodule GgenIgniter.SemanticJira.Execute do
  @moduledoc """
  One frontier-eligible work order driven end to end, in-process:
  frontier -> descriptor -> execute -> receipt -> reconcile.

  Steps (each named hop is the `"hop"` of every refusal it can emit):

    * **frontier** -- `TransitionLog.fetch/1` -> `Reconciler.project/2` ->
      `Reconciler.frontier/3`. The `--identity` must be in the eligible set:
      a blocked order refuses `{:not_eligible, identity, reason}` (the
      kernel's own blocked reason, e.g. `"standing=PARTIAL_ALIVE"`), an
      order the graph does not know refuses `:unknown_identity`, and a
      tampered or undecodable ledger refuses `{:ledger_refused, reason}`
      BEFORE anything else runs (the ledger is read, never written, here).
    * **descriptor** -- `Descriptor.build_xaas_contract/4` with
      `--verifier-suite`, repeatable `--alias repo=alias`, `--provider`
      (default `"recipe"`, the deterministic RecipeWorker), optional
      `--court-map` and `--authority-graph`. The `descriptor_refused` family
      passes through verbatim.
    * **execute** -- exactly one backend, chosen at the invocation boundary:
      local (`--pack-dir` + `--target-dir`) or external (`--receipt PATH`,
      a sealed XaaS export consumed as data). The EXTERNAL backend has no
      pack involvement at all: the fabric owned the execution, so no
      `sj:targetPack` check runs there (pack enforcement is a property of
      the LOCAL pipeline, which is the one that opens the pack). Local:
      first the order's `sj:targetPack` (FORMAT-verified at admission by
      `GgenIgniter.SemanticJira.admit_work_order/1`'s `@pack_name` regex;
      `nil` = no constraint, behavior unchanged) must match the resolved
      `--pack-dir`: the lawful name source is `pack.toml`'s `[pack].name`
      via `GgenIgniter.Pack.parse_manifest/1` when a valid manifest is
      present, else the directory's basename -- the same precedence sync's
      `GgenIgniter.SemanticJira.TargetPack.enforce!/2` implies by resolving
      `[pack: name]`. A mismatch refuses `target_pack_mismatch`
      (`REFUSED(target_pack_mismatch)`, `mu_unlawful`) BEFORE
      `git rev-parse`, `GgenIgniter.Reconcile.run/1`, or any gate runs --
      sync's pack enforcement no longer evaporates between sync and
      execute. Then `git -C target rev-parse HEAD` must equal the
      descriptor's `base_sha` (else `base_drift`); then
      `GgenIgniter.Reconcile.run/1` over the pack at `--pack-dir` with a
      static out path inside `--target-dir`
      (`ggen-manufactured/report.md`) -- the pack's single template
      auto-discovered, or the explicit `--template PATH` for multi-template
      packs (omitting it on a multi-template pack is the pipeline's own
      ambiguous-template raise, refused `sync_failed`); then
      `GgenIgniter.GateVerify.run/2` +
      `verify_unbound/2` -- the same pair `mix ggen_igniter.verify` calls.
      Any gate or unbound-fact failure refuses `verification_failed`; a
      pipeline raise refuses `sync_failed`. All three leave the LEDGER
      BYTE-UNCHANGED with no receipt written (the target tree may already
      hold the actuated file in the latter two cases: work happened,
      standing did not advance -- the fail-closed honesty this module
      exists to keep). Disclosed follow-on (NOT this module's law yet):
      the name check pins the NAME only; re-digesting `--pack-dir` via
      `GgenIgniter.PackLock.digest_checked/1` and comparing it against the
      sync-time stamp `TargetPack.enforce!/2` recorded requires reading
      the sync receipt, which is a separate lane.
    * **receipt** -- `Descriptor.receipt_from_xaas/2` with the descriptor
      bridge: the single receipt consumer seam (v26.10.1 RESOLUTIONS R1),
      its `receipt_refused` family passing through verbatim. The export
      comes from the backend: external reads it as data; local SYNTHESIZES
      it -- the descriptor's `"bridge"` echoed verbatim, `outcome`
      `"partial_alive"`, `head_verified` `false` (HONEST CEILING: a
      repository-local execution caps at PARTIAL_ALIVE --
      `alive_without_head_verification` is structural, `head_verified` is
      never true and `outcome` is never `"alive"` here; ALIVE stays
      xaas-fabric-only), `final_head` is the 40-hex content identity over
      the sorted `{path, content}` actuated set
      (`GgenIgniter.Receipt.hash_files/1`'s sha256 construction, first 40
      hex chars -- content identity, NOT a git sha), `fabric_verifier`
      steps from the real gate report, `receipt_digest` via
      `Descriptor.receipt_digest/1`. The synthesized export is written to
      `--receipt-out` (required for the local backend).
    * **reconcile** -- `Reconciler.reconcile/4` direct, over the exact work
      order (the `Cli` `reconcile_receipt/4` pattern: try each order, skip
      `:definition_mismatch`). `:already_recorded` maps to
      `{"status" => "already_applied"}`; reconciler refusals pass through
      verbatim. The append is the LAST write: every earlier refusal leaves
      the ledger byte-unchanged.

  Refusals are `{1, typed}` where `typed` is
  `%{"standing" => "REFUSED", "reason" => ..., "broken_term" => ...,
  "hop" => ..., "detail" => ...}`; with `--out-dir` the same map is also
  written to `<out-dir>/refused.json`. Invalid invocation (missing flag,
  unreadable/non-JSON input, ambiguous or missing execution input) is
  `{2, %{"status" => "invalid_invocation", "reason" => reason}}`.

  The `broken_term` vocabulary (`~/.claude/rules/chatman-equation.md`):

    | hop       | reason head                 | broken_term            |
    |-----------|-----------------------------|------------------------|
    | frontier  | `:unknown_identity`         | `R_missing_identity`   |
    | frontier  | `{:not_eligible, _, _}`     | `R_missing_standing`   |
    | frontier  | `{:ledger_refused, _}`      | `R_missing_replay`     |
    | descriptor| `{:descriptor_refused, _}`  | `R_missing_authority`  |
    | execute   | `{:base_drift, _}`          | `mu_on_O`              |
    | execute   | `target_pack_mismatch`      | `mu_unlawful`          |
    | execute   | `:sync_failed`              | `mu_unlawful`          |
    | execute   | `{:verification_failed, _}` | `admission_vacuous`    |
    | receipt   | `{:receipt_refused, _}`     | `R_missing_consequence`|
    | reconcile | `{:refused, _}`             | `R_missing_authority`  |

  Zero `mix` shell-outs: the whole chain is function calls into
  `TransitionLog`, `Reconciler`, `Descriptor`, `GgenIgniter.Reconcile`,
  `GgenIgniter.GateVerify` and `GgenIgniter.Receipt`. The one subprocess is
  the real `git -C <target> rev-parse HEAD` of the base-drift check (git is
  ground truth, not a task); the OS-level test suite shells out to the mix
  task, never the reverse.
  """

  alias GgenIgniter.{GateVerify, Pack, Receipt, Reconcile}
  alias GgenIgniter.SemanticJira.{Descriptor, Reconciler, TransitionLog}

  @outcome "partial_alive"
  @target "PARTIAL_ALIVE"
  @out_template "ggen-manufactured/report.md"

  @spec run(keyword()) :: {0 | 1 | 2, map()}
  def run(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, ledger} <- required(opts, :ledger),
         {:ok, identity} <- required(opts, :identity),
         {:ok, backend} <- backend(opts),
         {:ok, authority_opts} <- authority_graph(opts),
         {:ok, contract_opts} <- contract_opts(opts) do
      drive(opts, work_orders, ledger, identity, backend, contract_opts, authority_opts)
    else
      {:error, {:authority, reason}} -> refuse(opts, "descriptor", reason)
      {:invalid, reason} -> {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  # ── the five hops ──────────────────────────────────────────────────────────

  defp drive(opts, work_orders, ledger, identity, backend, contract_opts, authority_opts) do
    with {:ok, events} <- hop("frontier", TransitionLog.fetch(ledger)),
         {:ok, _projected, _evidence} <-
           hop("frontier", Reconciler.project(work_orders, events)),
         {:ok, front} <- hop("frontier", Reconciler.frontier(work_orders, events, authority_opts)),
         :ok <- on_frontier(front, identity),
         {:ok, descriptor} <-
           hop(
             "descriptor",
             Descriptor.build_xaas_contract(
               work_orders,
               events,
               identity,
               contract_opts ++ authority_opts
             )
           ),
         {:ok, executed} <-
           execute_backend(backend, descriptor, opts, target_pack(work_orders, identity)),
         {:ok, receipted} <- receipt_from(executed, descriptor) do
      append_transition(opts, work_orders, ledger, identity, executed, receipted, authority_opts)
    else
      {:error, {hop, reason}} -> refuse(opts, hop, reason)
    end
  end

  defp hop(hop_name, {:error, reason}), do: {:error, {hop_name, reason}}
  defp hop(_hop, ok), do: ok

  # -- frontier ---------------------------------------------------------------

  # The same eligible/blocked vocabulary `Descriptor` applies to its own
  # eligible row: an eligible identity proceeds; a blocked one carries the
  # kernel's own blocked reason (`{:not_eligible, identity, reason}`);
  # anything else is `:unknown_identity`.
  defp on_frontier(front, identity) do
    cond do
      Enum.any?(front.eligible, &(&1["identity"] == identity)) ->
        :ok

      entry = Enum.find(front.blocked, &(&1["identity"] == identity)) ->
        {:error, {"frontier", {:not_eligible, identity, entry["reason"]}}}

      true ->
        {:error, {"frontier", {:unknown_identity, identity}}}
    end
  end

  # -- execute ------------------------------------------------------------------

  # Exactly one backend, resolved at the invocation boundary. The external
  # export is read here too: unreadable or non-JSON input is exit 2, the same
  # boundary `Cli` draws for every other file flag.
  defp backend(opts) do
    pack_dir = Keyword.get(opts, :pack_dir)
    target_dir = Keyword.get(opts, :target_dir)
    receipt = Keyword.get(opts, :receipt)

    cond do
      present?(receipt) and (present?(pack_dir) or present?(target_dir)) ->
        {:invalid,
         "--receipt is the external backend: it is mutually exclusive with --pack-dir/--target-dir"}

      present?(receipt) ->
        external_backend(opts)

      present?(pack_dir) and present?(target_dir) ->
        local_backend(opts, pack_dir, target_dir)

      true ->
        {:invalid,
         "exactly one execution backend is required: --pack-dir + --target-dir, or --receipt PATH"}
    end
  end

  defp external_backend(opts) do
    case json_file(opts, :receipt) do
      {:ok, export} -> {:ok, {:external, export}}
      {:invalid, _} = invalid -> invalid
    end
  end

  defp local_backend(opts, pack_dir, target_dir) do
    if present?(opts[:receipt_out]) do
      {:ok, {:local, pack_dir, target_dir}}
    else
      {:invalid, "the local backend (--pack-dir + --target-dir) requires --receipt-out"}
    end
  end

  # The executed order's `sj:targetPack` (nil when the order names none --
  # no constraint). FORMAT was verified at admission; the WORLD check
  # against the real --pack-dir happens in the local backend below.
  defp target_pack(work_orders, identity) do
    case Enum.find(work_orders, &(&1["identity"] == identity)) do
      nil -> nil
      order -> order["target_pack"]
    end
  end

  # Local backend: target-pack name gate, base-drift gate, real pipeline,
  # real fail-closed gates. The name gate runs FIRST so a mismatch writes
  # nothing anywhere -- no rev-parse, no actuation, no receipt.
  defp execute_backend({:local, pack_dir, target_dir}, descriptor, opts, target_pack) do
    with :ok <- check_target_pack(target_pack, pack_dir),
         {:ok, head} <- base_head(target_dir, descriptor["base_sha"]),
         {:ok, result} <- reconcile_pack(pack_dir, target_dir, opts[:template]),
         {:ok, gates} <- gates(pack_dir) do
      paths = [result.out_path]
      export = synthesize_export(descriptor, gates, paths)

      File.write!(opts[:receipt_out], Jason.encode!(export, pretty: true) <> "\n")

      {:ok, %{export: export, head: head}}
    end
  end

  # External backend: the sealed export arrived as data at the invocation
  # boundary; nothing executes here, only the mapping and the append remain.
  # The fabric owned the execution, so no pack -- and no sj:targetPack
  # check -- is involved.
  defp execute_backend({:external, export}, _descriptor, _opts, _target_pack) do
    {:ok, %{export: export}}
  end

  # The sj:targetPack WORLD check (the sync-side law of
  # `GgenIgniter.SemanticJira.TargetPack.enforce!/2`, carried through to
  # execution): nil imposes no constraint; otherwise the resolved
  # --pack-dir must RESOLVE to the same pack name the order names. The
  # lawful name source is `pack.toml`'s `[pack].name`
  # (`GgenIgniter.Pack.parse_manifest/1`) when a valid manifest is present;
  # the directory's basename is the fallback (a legacy pack without a
  # manifest is still a pack, and `Pack.resolve_dir!/1`'s `--pack NAME`
  # convention already names packs by directory basename).
  defp check_target_pack(nil, _pack_dir), do: :ok

  defp check_target_pack(expected, pack_dir) do
    resolved = resolve_pack_name(pack_dir)

    if resolved == expected do
      :ok
    else
      {:error, {"execute", {:target_pack_mismatch, expected, resolved}}}
    end
  end

  defp resolve_pack_name(pack_dir) do
    case Pack.parse_manifest(pack_dir) do
      {:ok, %Pack.Manifest{name: name}} -> name
      _ -> pack_dir |> Path.expand() |> Path.basename()
    end
  end

  # `git -C <target> rev-parse HEAD` must equal the descriptor's `base_sha`:
  # executing against a moved base is `mu_on_O` -- the observed world no
  # longer matches the admitted premise.
  defp base_head(target_dir, base_sha) do
    case System.cmd("git", ["-C", target_dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {head, 0} ->
        head = String.trim(head)

        if head == base_sha do
          {:ok, head}
        else
          {:error,
           {"execute", {:base_drift, "target HEAD #{head} != order base_sha #{base_sha}"}}}
        end

      {out, _code} ->
        {:error,
         {"execute",
          {:base_drift,
           "git rev-parse HEAD failed in #{target_dir} (#{String.trim(out)}); order base_sha #{base_sha}"}}}
    end
  end

  # The bounded pipeline: ontology-load -> engine-run -> render -> actuate,
  # exactly one render and one actuation (a static out path -- a path with no
  # `<%= %>` round-trips unchanged, per `Reconcile.run/1`'s documented `:out`
  # contract). `Reconcile.run/1` is a faithful, un-defensive mirror of the
  # pipeline and raises on real failure; the raise is caught here, at the
  # boundary that owns the refusal (`sync_failed`), not hidden in the pipeline.
  # `--template` (opts[:template]) is the explicit template path for
  # multi-template packs: `Reconcile.run/1` auto-discovers the pack's single
  # template, and raises `{:error, {:ambiguous, _}}` on multi-template packs
  # when no `:template` is given. Single-template packs (the execute test
  # fixture shape) execute unchanged with no flag.
  defp reconcile_pack(pack_dir, target_dir, template) do
    opt_template =
      case template do
        nil -> []
        "" -> []
        path -> [template: path]
      end

    Reconcile.run(Keyword.merge([pack_dir: pack_dir, out: Path.join(target_dir, @out_template)], opt_template))
  rescue
    error ->
      {:error,
       {"execute",
        {:sync_failed, "GgenIgniter.Reconcile.run/1 raised: " <> Exception.message(error)}}}
  end

  # The fail-closed court: every `gates/*.rq` gate and every inverted
  # `verify/*.unbound.rq` companion must pass, or standing never advances.
  defp gates(pack_dir) do
    ontology = GgenIgniter.Pack.default_ontology(pack_dir)

    with {:ok, results} <- GateVerify.run(pack_dir, ontology),
         {:ok, []} <- GateVerify.verify_unbound(pack_dir, ontology) do
      {:ok,
       %{
         "status" => "pass",
         "steps" => Enum.map(results, fn {name, :pass} -> %{"id" => name, "status" => "pass"} end)
       }}
    else
      {:error, reason} -> {:error, {"execute", {:verification_failed, inspect(reason)}}}
    end
  end

  # -- receipt (local synthesis) ------------------------------------------------

  # The sealed export a local execution can honestly produce. `bridge` is the
  # descriptor's echo verbatim; the court receipt binds the work order's
  # acceptance/falsifier IRIs to the REAL gate report (all gates passed -- a
  # gate failure refused one hop earlier), so nothing is invented: each IRI
  # stands for "the pack's own fail-closed contract held at this run".
  defp synthesize_export(descriptor, gates, paths) do
    bridge = descriptor["bridge"]

    export = %{
      "epoch_id" => "ggen-local",
      "run_id" => "local-" <> String.slice(digest_of(bridge), 7, 16),
      "receipt_id" => "receipt-" <> String.slice(digest_of(bridge), 7, 16),
      "bridge" => bridge,
      "final_head" => final_head(paths),
      "outcome" => @outcome,
      "head_verified" => false,
      "fabric_verifier" => %{
        "status" => gates["status"],
        "steps" => gates["steps"],
        "court_receipt" => %{
          "acceptance_results" =>
            Map.new(bridge["requires"]["acceptance"], &{&1, gates["status"] == "pass"}),
          "falsifier_results" =>
            Map.new(bridge["requires"]["falsifiers"], fn falsifier ->
              {falsifier, if(gates["status"] == "pass", do: "survived", else: "killed")}
            end)
        }
      }
    }

    Map.put(export, "receipt_digest", Descriptor.receipt_digest(export))
  end

  # Receipt hop for both backends: local maps the synthesized export, external
  # maps the consumed one. `Descriptor.receipt_from_xaas/2` is the single
  # receipt consumer seam (v26.10.1 RESOLUTIONS R1): its `receipt_refused`
  # family passes through verbatim -- including the honest-ceiling guard
  # `alive_without_head_verification`, which is why this module can never
  # overclaim ALIVE even if a future edit flipped the constants above.
  defp receipt_from(%{export: export}, descriptor) do
    case Descriptor.receipt_from_xaas(export, descriptor["bridge"]) do
      {:ok, receipt} -> {:ok, %{receipt: receipt}}
      {:error, {:receipt_refused, _}} = refused -> {:error, {"receipt", refused}}
    end
  end

  # -- reconcile ----------------------------------------------------------------

  # The `Cli` `reconcile_receipt/4` pattern, over the exact order: try each
  # work order, skip `:definition_mismatch` (a definition mismatch on a
  # non-targeting row is skipped, not fatal), surface every other refusal.
  # `:already_recorded` is a success-shaped no-op (`already_applied`), the
  # replay law `Reconciler.reconcile/4` owns.
  defp append_transition(opts, work_orders, ledger, identity, executed, receipted, authority_opts) do
    case Enum.find_value(work_orders, {:error, :no_matching_work_order}, fn work_order ->
           reconcile_order(work_order, receipted.receipt, ledger, authority_opts)
         end) do
      {:ok, event, :appended} ->
        {0,
         %{
           "status" => "executed",
           "identity" => identity,
           "outcome" => @outcome,
           "head_verified" => false,
           "final_head" => executed.export["final_head"],
           "receipt_out" => opts[:receipt_out],
           "receipt_digest" => executed.export["receipt_digest"],
           "target" => @target,
           "event" => event
         }}

      {:ok, event, :already_recorded} ->
        {0, %{"status" => "already_applied", "event" => event}}

      {:error, reason} ->
        refuse(opts, "reconcile", reason)
    end
  end

  # One work order against the receipt: a `:definition_mismatch` on a
  # non-targeting row is nil (skipped, `Enum.find_value/3` moves on), every
  # other refusal is fatal.
  defp reconcile_order(work_order, receipt, ledger, authority_opts) do
    case Reconciler.reconcile(work_order, receipt, ledger, authority_opts) do
      {:ok, event, which} -> {:ok, event, which}
      {:error, {:refused, :definition_mismatch}} -> nil
      {:error, {:refused, reason}} -> {:error, {:refused, reason}}
    end
  end

  # ── refusals ────────────────────────────────────────────────────────────────

  # One refusal shape, one write: `{1, typed}` and, with `--out-dir`, the same
  # map at `<out-dir>/refused.json`. Emitted for every exit-1 refusal; exit-2
  # invalid invocation is not a refusal and writes nothing. The
  # target-pack mismatch carries the kernel's `REFUSED(reason)` standing
  # form (`semantic_jira.ex`'s `standing/1` vocabulary) with a structured
  # `expected`/`resolved` detail instead of a prose string.
  defp refuse(opts, hop, {:target_pack_mismatch, expected, resolved} = reason) do
    emit_refusal(opts, %{
      "standing" => "REFUSED(target_pack_mismatch)",
      "reason" => "target_pack_mismatch",
      "broken_term" => broken_term(reason),
      "hop" => hop,
      "detail" => %{"expected" => expected, "resolved" => resolved}
    })
  end

  defp refuse(opts, hop, reason) do
    emit_refusal(opts, %{
      "standing" => "REFUSED",
      "reason" => jsonable(reason),
      "broken_term" => broken_term(reason),
      "hop" => hop,
      "detail" => detail(hop, reason)
    })
  end

  defp emit_refusal(opts, typed) do
    if out_dir = opts[:out_dir] do
      File.mkdir_p!(out_dir)
      File.write!(Path.join(out_dir, "refused.json"), Jason.encode!(typed, pretty: true) <> "\n")
    end

    {1, typed}
  end

  defp broken_term({:unknown_identity, _}), do: "R_missing_identity"
  defp broken_term({:not_eligible, _, _}), do: "R_missing_standing"
  defp broken_term({:ledger_refused, _}), do: "R_missing_replay"
  defp broken_term({:descriptor_refused, _}), do: "R_missing_authority"
  defp broken_term({:base_drift, _}), do: "mu_on_O"
  defp broken_term({:target_pack_mismatch, _, _}), do: "mu_unlawful"
  defp broken_term(:sync_failed), do: "mu_unlawful"
  defp broken_term({:verification_failed, _}), do: "admission_vacuous"
  defp broken_term({:receipt_refused, _}), do: "R_missing_consequence"
  defp broken_term({:refused, _}), do: "R_missing_authority"
  defp broken_term(_other), do: "mu_on_O"

  defp detail(_hop, {:not_eligible, identity, reason}),
    do: "#{identity} is not frontier-eligible: #{reason}"

  defp detail(_hop, {:unknown_identity, identity}),
    do: "no work order #{identity} in the graph, or it is not admitted"

  defp detail(_hop, {:base_drift, message}), do: message

  defp detail(_hop, :sync_failed), do: "the local reconciliation pipeline raised"

  defp detail(_hop, {:verification_failed, message}),
    do: "the pack's fail-closed gates refused: #{message}"

  defp detail(_hop, {:ledger_refused, reason}),
    do: "the standing ledger refused: #{inspect(reason)}"

  defp detail(hop, reason), do: "#{hop} refused: #{inspect(reason)}"

  # Typed refusals are tuples/atoms; render them losslessly enough to branch on
  # (the same rendering `Cli` applies before `Jason.encode!/1`).
  defp jsonable(value) when is_tuple(value), do: value |> Tuple.to_list() |> jsonable()
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)

  defp jsonable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp jsonable(value), do: value

  # ── invocation helpers ──────────────────────────────────────────────────────

  defp contract_opts(opts) do
    with {:ok, aliases} <- aliases(opts),
         {:ok, court_map} <- court_map(opts) do
      base = [verifier_suite: opts[:verifier_suite], aliases: aliases, provider: opts[:provider]]

      with_court_map = if court_map, do: base ++ [court_map: court_map], else: base

      {:ok, Enum.reject(with_court_map, fn {_key, value} -> is_nil(value) end)}
    end
  end

  defp aliases(opts) do
    opts
    |> Keyword.get_values(:alias)
    |> Enum.reduce_while({:ok, %{}}, fn pair, {:ok, acc} ->
      case String.split(pair, "=", parts: 2) do
        [repository, alias_name] when repository != "" and alias_name != "" ->
          {:cont, {:ok, Map.put(acc, repository, alias_name)}}

        _ ->
          {:halt, {:invalid, "--alias must be owner/repo=alias, got #{inspect(pair)}"}}
      end
    end)
  end

  defp court_map(opts) do
    if Keyword.get(opts, :court_map) do
      case json_file(opts, :court_map) do
        {:ok, %{} = map} -> {:ok, map}
        {:ok, _other} -> {:invalid, "--court-map must be a JSON object"}
        {:invalid, _} = invalid -> invalid
      end
    else
      {:ok, nil}
    end
  end

  # --authority-graph PATH: absent = [] (the kernel's canonical index);
  # unreadable = invalid invocation (exit 2); unparseable as Turtle = typed
  # refusal at the descriptor hop (exit 1), the same boundary `Cli` draws.
  defp authority_graph(opts) do
    case Keyword.fetch(opts, :authority_graph) do
      :error ->
        {:ok, []}

      {:ok, path} when is_binary(path) and path != "" ->
        read_authority_graph(path)

      {:ok, _} ->
        {:invalid, "missing --authority-graph"}
    end
  end

  defp read_authority_graph(path) do
    case File.read(path) do
      {:ok, bytes} -> parse_authority_graph(path, bytes)
      {:error, reason} -> {:invalid, "#{path}: #{inspect(reason)}"}
    end
  end

  defp parse_authority_graph(path, bytes) do
    case RDF.Turtle.read_string(bytes) do
      {:ok, graph} ->
        {:ok, [authority: graph]}

      {:error, reason} ->
        {:error, {:authority, {:authority_index_unavailable, path, inspect(reason)}}}
    end
  end

  defp work_orders(opts) do
    with {:ok, decoded} <- json_file(opts, :work_orders) do
      case decoded do
        list when is_list(list) -> {:ok, list}
        %{"work_orders" => list} when is_list(list) -> {:ok, list}
        _ -> {:invalid, "--work-orders must be a JSON array or {\"work_orders\": [...]}"}
      end
    end
  end

  defp json_file(opts, key) do
    with {:ok, path} <- required(opts, key),
         {:ok, body} <- File.read(path) |> or_invalid(path) do
      body |> Jason.decode() |> or_invalid(path)
    end
  end

  defp or_invalid({:ok, _} = ok, _path), do: ok
  defp or_invalid({:error, reason}, path), do: {:invalid, "#{path}: #{inspect(reason)}"}

  defp required(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:invalid, "missing --#{key |> to_string() |> String.replace("_", "-")}"}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  # ── content identity ───────────────────────────────────────────────────────

  # First 40 hex chars of `Receipt.hash_files/1`'s sorted `{path, content}`
  # sha256 -- a 40-hex CONTENT identity (the shape `receipt_from_xaas/2`'s
  # `final_head` law requires), never a git sha.
  defp final_head(paths) do
    case Receipt.hash_files(paths) do
      "sha256:" <> hex -> String.slice(hex, 0, 40)
    end
  end

  defp digest_of(value), do: GgenIgniter.SemanticJira.digest_exact(value)
end
