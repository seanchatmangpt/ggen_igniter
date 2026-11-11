# v26.10.1-loop — sjira/sa2a loop closure lanes

One canonical checkout per repo. Coordinator owns ALL git transitions; agents never run
git state commands. Per-lane build isolation: `MIX_BUILD_ROOT=_build-<lane>`. Lane build
roots are leases — coordinator deletes them at integration. Shared files are
coordinator-owned (lanes REPORT content, never edit): `HANDWRITTEN.md` (ggen),
`CHANGELOG.md` (ash_a2a), `docs/reference/cli/index.md` (ggen).

Repos: ggen_igniter@main (4dc0525 + user's uncommitted v26.10.1 release files —
FORBIDDEN to all lanes: `mix.exs`, `CHANGELOG.md`, `.tool-versions`), xaas@feat/
sjira-v26-10-1-chicago-render (dc80048a), ash_a2a@main (02f221d, pre-existing dirty
docs — lanes append-only into CHANGELOG via coordinator), ash_pplan@main (f91fafe).

Epoch law (ggen): watermark ACTIVE — every `lib/**/*.ex` edit needs a HANDWRITTEN.md
row dated ≥ watermark. **HANDWRITTEN.md is coordinator-owned**: each ggen lane ends its
report with the exact row(s) to append.

Order: ggen G1 → (G2, G3, G5a) → xaas X2 → X3 → X1-commitA → [G1 pushed → ref-fill]
→ X1-commitB. ash_a2a (A1, A2) and ash_pplan (P1) are independent of everything.

## RESOLUTIONS (cross-lane seams)

- R1: ggen receipt consumer seam is single-sourced in `Descriptor.receipt_from_xaas/2`.
  G3 never hand-maps receipts; G5a owns struct-level projection only.
- R2: `reconcile_reactor.ex` — G2 owns `finalize_evidence/1` only; no other lane edits
  this file. `receipt.ex` is untouched by everyone (fields already exist).
- R3: HANDWRITTEN.md rows: G1 (transition_log.ex), G2 (semantic_jira.ex, target_pack.ex,
  sync.ex, reconcile_reactor.ex), G3 (execute.ex + task file), G5a (r_projection.ex) —
  all reported, coordinator appends once with paydown notes.
- R4: ash_a2a CHANGELOG bullets: A1 + A2 report text; coordinator appends to the dirty
  `[Unreleased] → Added` once.
- R5: ash_a2a `@identity_fields` never gains `:graph_digest`; `metadata.work_order_digest`
  is never compared to `semantic_subject.graph_digest` (different planes by construction).
- R6: xaas `@bridge_keys` = ggen's full ten-key list; receipt-contract key
  `snapshot_digest` and descriptor-v1 keys STAY; only the bridge-map key renames.
- R7: xaas `SemanticReceipt` export is NOT extended (would break `receipt_not_fabric_sealed`
  for pre-change sealed epochs); RProjection sources v2 keys from bridge/opts/run_id only.

## Lane G1 — ggen bridge seam (transition_log.ex)
OWNED: `lib/ggen_igniter/semantic_jira/transition_log.ex`,
`test/ggen_igniter_semantic_jira_transition_log_concurrency_test.exs`.
`event_digest/1` defp→def with @doc/@spec (digest/1 of event minus seq/event_digest).
NEW `legacy_event_digest/1` = `SemanticJira.digest_exact(Map.drop(event, ["seq",
"event_digest"]))` — evidence-pinned by xaas integrity_test:299 (refute equality ⇒ must
NOT elide the 9 derived-digest keys) and :307 (frontier assertion ⇒ must drop seq).
Moduledoc sentence on the public digest pair. Tests: divergence, seq-independence,
insertion-order independence, cross-repo vector (rebuild xaas's pinned case), tamper
refused by both rules. Gate: `MIX_BUILD_ROOT=_build-g1 mix compile --warnings-as-errors
&& mix test`. Falsifier: xaas `semantic_jira_bridge_integrity_test.exs:289-307` passes
against this dep.

## Lane G2 — sj:targetPack + pack_digest
OWNED: `priv/ggen/semantic-jira-pack/{ontology.ttl, shapes/work-order.shacl.ttl,
gates/020_work_orders.rq}`, `lib/ggen_igniter/semantic_jira.ex` (validator +
normalization ONLY; NOT @definition_fields), NEW `lib/ggen_igniter/semantic_jira/
target_pack.ex`, `lib/mix/tasks/ggen_igniter.sync.ex` (two hook sites beside
`maybe_verify_base_shas!`), `lib/ggen_igniter/reactors/reconcile_reactor.ex`
(`finalize_evidence/1` receipt stamp ONLY), `priv/schema/refusals.schema.json` (new code
TARGET_PACK_UNKNOWN: broken_term R_missing_identity, owner
GgenIgniter.SemanticJira.TargetPack, retryable true), `docs/reference/refusals.md`,
`docs/status.md` (:156-157). Law split: admission=FORMAT (`@pack_name
~r/\A[a-z0-9][a-z0-9_-]*\z/`, `{:invalid_target_pack, v}` reason), sync=WORLD
(enforce!/2 resolves pack, File.dir?, `PackLock.digest_checked/1`; unknown → ArgumentError
`REFUSED:TARGET_PACK_UNKNOWN pack=... work_order=...`). Receipt stamp: pack_name +
pack_digest top-level attrs in the :3037 Receipt.new via struct!/2 pass-through;
digest error → step failure (fail closed), packless → nil/omitted (byte-compat).
SHACL: optional property row (maxCount 1, xsd:string, pattern) mirroring
requiresGitGroundTruth. Gate 020 surfaces ?target_pack via OPTIONAL.
Tests: SHACL positive/negative×2, admission format + digest-stability law
(definition_digest identical with/without target_pack), enforce! real fixture packs
(unknown/symlink-escape/chmod-000), receipt stamping via real reactor run, zero-write
on refusal. Mutants: drop SHACL row / add to @definition_fields / nil-stamp — each
killed by a named test.

## Lane G3 — mix semantic_jira.execute
OWNED (new files only): `lib/mix/tasks/semantic_jira.execute.ex`,
`lib/ggen_igniter/semantic_jira/execute.ex`, `test/ggen_igniter_semantic_jira_execute_test.exs`,
`test/mix_semantic_jira_execute_task_test.exs`. Plain `use Mix.Task`; opts →
`Execute.run()` → `Cli.emit/2`; exits 0/1/2. Steps: frontier (TransitionLog.fetch →
Reconciler.project/frontier; not_eligible refuses) → descriptor
(`Descriptor.build_xaas_contract/4`) → execute (`--backend local` = base_sha HEAD check
+ `GgenIgniter.Reconcile.run/1` + `GateVerify.run/2`+`verify_unbound/2`; OR `--receipt
PATH` external) → receipt (synthesize sealed export: bridge echo, outcome
partial_alive, head_verified FALSE — honest ceiling: local caps at PARTIAL_ALIVE, ALIVE
is xaas-fabric-only; digest via `Descriptor.receipt_digest/1`; map via
`Descriptor.receipt_from_xaas/2` ONLY) → reconcile (`Reconciler.reconcile/4` direct,
cli.ex:63 precedent). Refusal shape xaas typed/5 + refused.json. Exactly one of
(pack-dir+target-dir | --receipt) else exit 2. Tests: full local loop (real tmp git
repo + real pack + real ledger), honest-ceiling mutant (alive/true in export →
receipt_from_xaas refuses), external --receipt as data file, not_eligible/gate-failure/
base-drift/tampered-ledger all leave ledger byte-unchanged, replay one-shot. Falsifiers:
overclaim (head_verified true), skip-verify, second-mapping — each killed by a named
test.

## Lane G5a — GgenIgniter.SemanticJira.RProjection
OWNED (new files): `lib/ggen_igniter/semantic_jira/r_projection.ex`,
`test/ggen_igniter_semantic_jira_r_projection_test.exs`. project/2 →
`{:ok, map} | {:error, {:r_projection_refused, reason}}`; write/2 → `<stem>.r.json`.
Standing map: alive+all-exit-0→ALIVE; alive w/ non-zero exit→REFUSED(admission_vacuous);
refused→BLOCKED:<reason>+mu_on_O; compensated→PARTIAL_ALIVE; compensation_failed→
PARTIAL_ALIVE (detail in derived_from); build_broken→BUILD_BROKEN+mu_unlawful.
pre/post_run_hash → subject_before/subject_after. identity.subject_sha/base_sha = 40-hex
git commits (default `git rev-parse HEAD` of opts[:repo], required, fail-closed
:repo_required/:head_unresolvable/{:subject_sha_not_a_commit,_}); never file-set hashes.
work_order_id required (metadata or opt). commands {cmd,cwd,exit} from receipt.commands.
receipt_hash rides provider_ext.ggen_igniter (object). Self-check: every ok result
passes `Bootstrap.Receipts.check/1` == []. Optional validator shell
(python3 ~/.claude/dfcm/validate_receipt.py) skip-if-absent. Determinism: same
input → byte-identical JSON.

## Lane X2 — xaas RProjection v2
OWNED: `lib/xaas/receipt/r_projection.ex`, `test/xaas/receipt/r_projection_test.exs`,
`test/xaas/receipt/r_projection_consistency_test.exs`,
`docs/sjira/v26.9.23/episodes/{fmt-1/receipt.r.json, me-1/drive/receipt.r.json,
me-2/drive/receipt.r.json}` (hand-extension ONLY). New keys: work_order_id ←
identity.subject resolution expr (:476); origin_authority ← Map.take(authority,
[ceiling,grant,actor]); provider.name ← opts[:provider] || authority.actor ||
"xaas-fabric" (new opt :provider); provider_execution_id ← native.run_id.
native/court → `provider_ext.xaas` (single top-level key named literally
"provider_ext.xaas"); consistency/2 court reads re-pointed, NO legacy fallback.
New laws V2-1..V2-4 (work_order_id==order identity==identity.subject;
provider_execution_id==ext.native.run_id fail-closed; origin_authority mirrors
authority; provider name non-empty) each with typed refusal + mutant test.
Fixtures: hand-extend all three (exact values in design: EP-A, lease grants, run_ids,
provider "recipe" from drive.json:57) → validator ADMITTED ×3. Falsifier (red today):
validator on fmt-1 REFUSED exit 1 → ADMITTED exit 0. Postgres test DB required.

## Lane X3 — plan-next (independent of X1)
OWNED: NEW `lib/xaas/ultracode/semantic_drive/plan_next.ex`; minimal edits
`semantic_drive.ex` (context opt, conditional step list, step(:plan_next) clause after
frontier_after, conclude summary + conditional court_form), `semantic_drive/ocel.ex`
(@extension_classes += "PolicyCandidateEmitted"), `lib/mix/tasks/xaas.episode.ex`
(--plan-next :boolean); NEW `test/xaas/ultracode/semantic_drive_plan_next_test.exs`.
Domain = standing-progression stub (graph's own @standings chain restricted past `to`;
promote may stick → :strong_cyclic; to∉chain → {:refused, standing_not_progressable};
fixed atoms, no String.to_atom). `AshA2A.Replan.Loop.run(subject=event["identity"],
%{formalism: :fond, domain, initial}, [{"ash_pplan", AshA2A.Replan.Port.AshPPlan}])`.
Journal: artifact plan_next.json (schema xaas/semantic-drive-plan-next/v1,
domain_source standing_progression_projection/1, full candidate, replay_key,
policy_binding_digest) + OCEL event ONLY on success. Step adapter NEVER refuses
(promote already committed — planning failure is an observation). Default OFF;
committed episodes bit-identical. Falsifiers F-1..F-6 (mode must be :strong_cyclic for
the promote-stick case; subject no-drift; purity/no File IO in plan/2; authority :none
/ standing :candidate; flag-off preservation; OCEL validator passes).

## Lane X1 — bridge un-gate (two commits)
OWNED: `mix.exs` (ggen_igniter entry only), `mix.lock`, `lib/xaas/ultracode/
semantic_jira_bridge.ex` (guard 4th conjunct + header comment, :118, :491, :722), the 8
tagged test files (rename lines + commit-B un-tagging, keep :subprocess), NEW
`test/xaas/ultracode/semantic_jira_bridge_seam_test.exs` (NEVER tagged; asserts
module-loaded IFF guard holds; the `guard_holds == true` assert is the dep-drift
alarm). Commit A (now): guard+comment, renames, @bridge_keys full ten-key alignment,
integrity required-paths additions, seam test (passes negative vs hex 26.9.29).
Commit B (after coordinator supplies post-G1 SHA): ref-fill procedure (verify BOTH defs
public in the ref via `git show <SHA>:...`), `rm -rf deps/ggen_igniter
_build/*/lib/ggen_igniter && mix deps.update ggen_igniter`, review lock diff
(ash_a2a hex-vs-git clash → override or widen, never blanket), un-tag 8 files.
Rename table: bridge_test :81/:205(right half)/:360, crown :139, integrity :103;
STAY: bridge :74/:510, falsifier :154, integrity :315, docs :255/:305.
Falsifier F2: old-key bridge → {:bridge_invalid, ["source_snapshot_digest"]}.

## Lane A1 — ash_a2a graph_digest invariant
OWNED: `lib/ash_a2a/hilt/work_order.ex`, NEW `lib/ash_a2a/chicago/courts/
hilt_work_order.ex`, `lib/ash_a2a/chicago/mutation/catalog.ex` (one appended entry),
`priv/sa2a/chicago_court_manifest.json` (regen via mix task only), NEW
`test/hilt_work_order_graph_digest_test.exs`. Optional `:graph_digest` field (NOT in
@enforce_keys, NOT in @identity_fields — comment the exclusion), new!/1 sha256:64hex
validation, for_command! carry-by-default (opts[:graph_digest] overrides). Named
private `checkpoint_graph_digest/2` in the with-chain: order nil→ok; subject present +
differ → {:error, :stale_graph_identity}; equal → ok; subject absent → ok.
@refusal_codes += stale_graph_identity: :refused_identity. Court CHI-HILT (gate 1,
profile :core), falsifiers 001-005 (disagree/e2e CommandBus via MutationHarness/agree/
either-absent-skip/carry-by-default). Mutation entry hilt_graph_digest_ok
({:replace_body, "ok."}, killers ["CHI-HILT"]). `mix ash_a2a.chicago.mutate --only
hilt_graph_digest_ok --require-killed`; pin_court_manifest + --check. Existing suites
untouched and green = backward-compat proof.

## Lane A2 — ash_a2a R projection
OWNED (new files): `lib/ash_a2a/receipt/r_projection.ex`,
`test/ash_a2a_receipt_r_projection_test.exs`. project/2 (receipt, opts): preconditions
ordered fail-closed (shape → Binding.verify/1 → anchors → work_order_id → consequence →
standing). Opts REQUIRED: repo, subject_sha (40-hex, caller-verified clean-tree HEAD per
C0), base_sha; projector runs NO git. Ceiling map :read/:observe→OBSERVE,
:change→CONSTRUCT, :external_do/:external→DO, unknown→refuse. NO caller override of
ceiling/standing/digests. ALIVE requires receipt.standing==:durable — :observed+executed
refuses :r_projection_standing_not_durable. Standing table: refused→REFUSED(<code>)
with broken_term map (authority_required→R_missing_authority, consequence_unclassified→
R_missing_consequence, anchor/store/in_flight→R_missing_replay, kill_switch→mu_unlawful,
rest→admission_vacuous); failed dispatch_crashed→BUILD_BROKEN+R_missing_consequence,
other→BLOCKED(:code); compensated→PARTIAL_ALIVE; unknown/pending→UNKNOWN.
subject_digest = input_digest prefix-stripped; commits always []; remote_effects =
[capability] iff DO; replay: one record, exit 0 iff executed+reconciled AND durable.
replay_binding from actuation/command ids + binding head link. Self-digest JCS in
provider_ext.ash_a2a. Tests: real EKV durable store ALIVE path (receipt_store_ekv
pattern), Memory dishonesty guard, ceiling map ×4, refusal family, Crashy BUILD_BROKEN,
PARTIAL/UNKNOWN/pending, reconciled→ALIVE, anchors fail-closed, determinism,
exit-gate totality.

## Lane P1 — ash_pplan bridge + FOND
OWNED: NEW `lib/ash_pplan/standing/sj_bridge.ex`, `lib/ash_pplan/workflow/task.ex`
(terminal_outcomes: [] field), `lib/ash_pplan/workflow/model.ex` (normalize +
check_terminal :unknown_terminal_outcomes), `lib/ash_pplan/workflow/project/fond.ex`
(branches/2 per-outcome routing, success_like/2, transitions BFS replacing subsets/1),
NEW `test/standing/sj_bridge_court_test.exs`, NEW
`test/workflow/fond_terminal_court_test.exs`, `test/fond_tla_bench_test.exs`,
`bench/fond_tla_bench.exs`, `test/support/fond_tla_bench.ex`.
Bridge: statuses/0 (7 bases), terminal?/1 (BLOCKED only), terminal_outcomes/0, map/2
(value family), map/3 (+rung from Standing.ladder/2). REFUSED bare refuses
(:sj_refused_requires_layers); unknown base/layer refuse. Rung NEVER moves because of a
status (ALIVE over unevidenced run → rung :UNKNOWN visible data). Ladder untouched.
FOND: live outcomes = non-terminal; first live completes, remaining live retry, all-live
→ [] ; all-terminal action OMITTED (empty_nondeterministic_outcome respect), state
stays with empty action map (losing). BFS from [] over admitted actions; seen-set
dedupes retry self-loops; exact-set assertion
`MapSet.new([[], [:a], [:b], [:a,:b], [:a,:c], [:a,b,:c]])` for the 3-task model.
Bench: :terminal_chain family, n=250/500 reduction bounds (@per_state 3000, @doubling
2.5), :strong admits. Sequencing: Task/Model → branches → BFS → bridge → courts →
bench. Gate: mix compile --warnings-as-errors && mix test && ./bin/gate.

## Integration (coordinator)
1. Append HANDWRITTEN.md rows (G1, G2, G3, G5a) + ash_a2a CHANGELOG bullets (A1, A2)
   + ggen cli doc one-liner (G3).
2. Full gates serially per repo: ggen `mix compile --warnings-as-errors && mix test`
   (+ `mix ggen_igniter.epoch.check` — must not regress); ash_a2a `mix compile
   --warnings-as-errors && mix test` + `mix ash_a2a.chicago` scoped + mutate; ash_pplan
   `mix compile --warnings-as-errors && mix test` (+ ./bin/gate if feasible); xaas
   `mix compile --warnings-as-errors && mix test` (Postgres required).
3. Integration falsifiers: `Code.ensure_loaded?(Xaas.Ultracode.SemanticJiraBridge)`
   → {:module,_} (post ref-fill); ggen sync receipt pack_digest non-null; unknown
   target_pack → REFUSED:TARGET_PACK_UNKNOWN; `mix semantic_jira.execute` drives one
   order to PARTIAL_ALIVE; validator ADMITTED ×3 on xaas fixtures.
4. Delete all `_build-lane*`/`_build-g*`/`_build-a*`/`_build-p*`/`_build-x*` roots.
5. Commit per lane (git commit -F file), push each repo's branch. Never touch the
   user's dirty files (ggen mix.exs/CHANGELOG/.tool-versions; ash_pplan mix.exs/
   mix.lock/docs/demonstration.md; ash_a2a docs/reference/*).
6. Final receipt: per-repo base/head SHAs, commands+exits, standing per hop.
