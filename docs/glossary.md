# Glossary

One canonical definition per term, pulled from the specialist docs that already
use it (cited per entry) — not invented for this page. Where a term in the
requested list is not this codebase's own literal vocabulary, that is stated
honestly rather than papered over with an invented definition.

## admission

Two senses, one entry. **(1) Pipeline admission** — the whole-plan,
fail-closed check `GgenIgniter.Reactors.ReconcileReactor`'s `:admit` step
performs over the **entire** intended set of
create/replace/eval/delete items — before a single byte is written, not
per-item as writes happen. Refuses the whole run (never a partial refusal) on
a duplicate output-path collision between two targets, an unowned `:delete`
candidate, or a stale-path violation under `--on-stale refuse`. Only the
Reactor pipeline has an explicit admission step; `GgenIgniter.Reconcile.run/1`
and `Mix.Tasks.GgenIgniter.Sync`'s inline pipeline have no equivalent
whole-plan gate. **(2) Kernel/graph admission** — the step that turns
observation O into admitted O*: a gate that can refuse decides which inputs
manufacture may act on. Candidates never become output without admission —
in this repo, `admit_work_order/1` plus SHACL admission of the work-order
graph, with `origin_authority` resolved against the pinned authority index
(prose never admits; see "gate", "court"). See
`docs/reference/reactor/steps.md`,
`docs/integrations/ggen/planning-boundary.md`.

## actuation

The act of a rendered template's content actually touching disk (or being
evaluated, under `mode: eval`). The single filesystem-mutation-boundary step
is `:actuate` in the Reactor pipeline, and `GgenIgniter.Actuate`'s
`write_file!/3` / `inject_content!/5` / `eval_code!/2` functions in both
pipelines. Every step before actuation is a pure read or in-memory
computation; every step after it (`:verify`) only reads what actuation
already wrote. See `docs/reference/reactor/steps.md`,
`docs/integrations/igniter/safety.md`.

## artifact

A generated output file — the concrete thing `mode: file` actuation produces
on disk from a template/query pair. See "stale artifact" below for the
specific, load-bearing sense this term carries in the reconciliation model.

## Chicago test

A test following Chicago-school (classicist) discipline: real collaborators
(real files, real subprocesses, real SPARQL engines), state-based assertions
on real resulting state — never interaction-based mocking ("was this function
called") of a collaborator this codebase owns or can run in-process. Verified
in this repo by a real, re-run grep (`grep -rn "Mock\|mock(\|patch(\|monkeypatch"
test lib native`, exit code 1 — zero matches). See `docs/testing/chicago.md`.

## compensation

Reverting real, already-written files after a later pipeline step fails.
Implemented via Reactor's `undo/4` callback on the `:actuate` step (fires when
a **later** step, `:verify`, fails after `:actuate` already succeeded) and,
separately, `:actuate`'s own internal self-heal inside `run/3` (reverting a
partial write from its own mid-loop failure before ever returning an error).
Produces the `:compensated` or `:build_broken` receipt standing, with
`pre_run_hash == post_run_hash` as the checkable proof restoration was
genuine. Scoped to the opt-in Reactor pipeline only — the default
`GgenIgniter.Reconcile.run/1` pipeline has no compensation mechanism at all.
See `docs/reference/reactor/compensation.md`, `docs/reference/evidence/recovery.md`.

## controller

`GgenIgniter.Controller` — a real, opt-in `GenServer` that holds live
reconciliation state (`last_reconciliations`, keyed by caller-chosen
`pack_key`) **in its own process** across multiple `reconcile/3` calls,
answering "how many times has this recipe actually been reconciled, in this
process" without touching disk. Adds no reconciliation logic of its own —
it dispatches to `GgenIgniter.Reconcile.run/1` (default) or
`GgenIgniter.Reactors.ReconcileReactor.run/1` (opt-in, `use_reactor: true`).
Started only when a consumer sets `config :ggen_igniter, start_controller:
true` (default `false`). See `docs/operations/controller.md`.

## Executable Research Claim

`GgenIgniter.EDS.Claim` — `ERC = <H, A, F, E, V>`, operationally `ERC+ = <H,
A, F, P, I, E, V, R>` (Executable Design Science, S6): hypothesis (`H`),
artifact (`A`, the executable thing operationalizing `H`), falsifiers (`F`,
see "falsifier" below), protocol (`P`, how the artifact is meant to be
exercised), execution identity (`I`), execution evidence (`E`, real
collected outputs once run), verifier (`V`, turns evidence + falsifier
verdicts into a `GgenIgniter.EDS.EvidenceState.t()`), and receipt (`R`,
produced by `verify/1`, not supplied up front). "A hypothesis with no
executable artifact remains legitimate research but is not yet an
executable research claim" (S6) — `Claim.new/1` therefore requires both
`hypothesis` and `artifact`, and raises `ArgumentError` if `falsifiers` is
empty ("an ERC with no falsifier is a demonstration, not an executable
research claim"). See `lib/ggen_igniter/eds/claim.ex`.

## falsifier

`GgenIgniter.EDS.Falsifier` (Executable Design Science, S9): "every strong
computational claim [must] identify what would weaken it," and the research
artifact must "make contradictory evidence representable" — a check
function that CAN return `:falsified`, not one wired to always pass.
`%Falsifier{}` pairs a human-readable statement of what would falsify the
hypothesis with a real `check` function of arity 1 (taking the artifact's
evidence) returning `{:survived, detail}` or `{:falsified, detail}`.
`Falsifier.run/2` executes it for real against real evidence; a raised
exception is caught and reported as `:falsified` (a crashing falsifier "has
not survived, it has been falsified by an unhandled real failure"). See
`lib/ggen_igniter/eds/falsifier.ex`.

## ggen

The real, external Rust project (`~/ggen` /
[seanchatmangpt/ggen](https://github.com/seanchatmangpt/ggen)) this project
bootstraps: ontology-to-code generation via ontology load → SPARQL query →
template render → guarded write. In `ggen_igniter`, this role is fulfilled by
this repo's **own** `GgenIgniter.Ontology`/`Engine`/`Render`/`Actuate` spine —
a from-scratch Elixir port of the same pipeline shape, not a runtime
dependency on (or shell-out to) the real `ggen` binary. One real Rust
component *is* embedded: a Rustler NIF wrapping `ggen`'s own
`ggen-graph-wasm` oxigraph query engine, used by the default `--engine
oxigraph`. See `docs/integrations/ggen/semantic-compilation.md`,
`docs/architecture/overview.md`.

## Igniter

The `igniter` hex package (a real, unconditional `mix.exs` dependency). Both
`mix ggen_igniter.sync` and `mix ggen_igniter.doctor` `use Igniter.Mix.Task`
(CLI-task composition/plumbing) and call `Igniter.add_notice/2`. `ggen_igniter`
does **not** use Igniter's AST-mutation API (`Igniter.Project.Module`,
`Igniter.Code`, `Sourceror.Zipper`-based structural patching) anywhere —
confirmed by a real grep with zero code matches. See
`docs/integrations/igniter/project-actuation.md`.

## manifest

`GgenIgniter.Manifest` — the current-state cache at
`<base_dir>/.ggen_igniter/manifest.json`, atomic-rename-persisted, keyed by
the `(template_path, out_template)` **recipe** identity (deliberately not
ontology path or pack name — see "reconciliation" below). Records what a
recipe's most recent **successful** (`:alive`) run actually wrote; it is not a
history. Consulted and updated by `Mix.Tasks.GgenIgniter.Sync`'s inline
pipeline and by `ReconcileReactor`'s own `observe_prior_manifest`/
`finalize_evidence` steps — never by `GgenIgniter.Reconcile.run/1`, which has
zero manifest awareness. See `docs/reference/reconciliation/manifest.md`.

## manufacturing plan

Not this codebase's own literal term — its real equivalent is
`GgenIgniter.PendingActuation`, the in-memory intermediate representation the
Reactor pipeline's `:render` step builds: one `%PendingActuation{}` struct per
intended output (create/replace/eval, plus one per stale-prune delete
candidate), carrying `operation`, `previous_hash`/`desired_hash`, `ownership`,
and `desired_content`. This is what lets `:admit` reason about the **full**
intended delta before a single byte is written — a real deferred-actuation
plan, not a bare rendered-text map. Modeled on (not calling) the real Rust
`ggen`'s own `PendingWrite`/`SyncReport` IR. Only the Reactor pipeline builds
this plan; `GgenIgniter.Reconcile.run/1` and the CLI's inline pipeline actuate
directly with no intermediate plan representation. See
`docs/integrations/ggen/planning-boundary.md`.

## ontology

The RDF/Turtle input file describing the domain to generate from — loaded via
`GgenIgniter.Ontology.load!/1` (`RDF.Turtle.read_file!/1`, from the `rdf` hex
package) into an in-memory `%RDF.Graph{}`, then queried via one of three
SPARQL engines. See `docs/integrations/ggen/semantic-compilation.md`.

## pack

A directory following the `priv/ggen/<pack-name>/{ontology.ttl, gates/*.rq,
templates/*.{eex,tmpl}}` convention, resolved by `GgenIgniter.Pack` (a pure
helper, no Igniter dependency) so `--ontology`/`--query`/`--template` don't
need to be repeated on every invocation. Selected via `--pack NAME` (resolves
`priv/ggen/NAME/`), `--pack-dir DIR` (uses `DIR` directly), or `--pack
NAME:TEMPLATE_STEM` (disambiguates a multi-template pack). Can also be
fetched from a `github:`/`hex:` marketplace source via
`GgenIgniter.Pack.fetch_pack!/2` (a real, tested library function with no CLI
flag wired to it yet). See `docs/reference/cli/packs.md`,
`docs/integrations/ggen/packs.md`.

## projection

Used precisely in one place in this codebase: `mix ggen_igniter.doctor`'s
check 17 treats `mix.exs`'s `version:` string literal as **a projection of**
this project's real, observed versioning convention — `CHANGELOG.md`'s
topmost `## vX` heading, not an independently maintained field — reporting
`MATCH`/`MISMATCH` rather than trusting `mix.exs` as its own source of truth.
See `docs/reference/cli/doctor.md`.

## Reactor

The `reactor` hex package (a real, unconditional `mix.exs` dependency, used
only at the config level as opt-in). `GgenIgniter.Reactors.ReconcileReactor`
is a plain `use Reactor` module — explicitly **not** `Ash.Reactor` — so
`ggen_igniter` stays usable without Ash. It is the real, tested **target**
coordination pipeline (observe → load → resolve → query → render → admit →
actuate → verify → finalize evidence), reachable only when a consumer sets
`config :ggen_igniter, use_reactor: true` (default `false`). See
`docs/reference/reactor/overview.md`, `docs/integrations/ash/reactor.md`.

## receipt

`GgenIgniter.Receipt` — a durable, append-only record of **one admitted
reconciliation attempt**, one JSON line per attempt regardless of outcome, at
`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`. Carries one of five
closed-set standings (see "standing"), `pre_run_hash`/`post_run_hash`, the
real touched `files`, an OCEL-shaped `events` list, and (since the
`sh_before:`/`sh_after:` shell-hook feature) a `commands` list — see "shell
hook" below. Written by `GgenIgniter.Reactors.ReconcileReactor.run/1` on
every path (the full receipt lifecycle), and by
`Mix.Tasks.GgenIgniter.Sync`'s inline pipeline ONLY when a real (non-
`--dry-run`) run declares `sh_before:`/`sh_after:` — a minimal, `standing:
:alive` receipt whose sole purpose is populating `commands`, not a full
reconciliation receipt (that pipeline has no `:verify`/compensation step of
its own). Schema: `priv/schema/receipt.schema.json`. A summary is not a
receipt. See `docs/reference/evidence/receipts.md`.

## shell hook

A template frontmatter's `sh_before:`/`sh_after:` field
(`GgenIgniter.Frontmatter.sh_before`/`sh_after`) — a real shell command run
via `GgenIgniter.ShellHook.run/3` before/after that target's real
`write_file!/3`/`inject_content!/5` call. Requires `--allow-sh`
(`Mix.Tasks.GgenIgniter.Sync`) / `allow_sh: true`
(`GgenIgniter.Reactors.ReconcileReactor.run/1`) — absent it, the whole run
refuses before any actuation, fail-closed. Deliberately **not** integrated
into "admission" or "compensation" (see those terms) — a disclosed,
intentional trust boundary, the same one a frontmatter `to:` path already
is. See `docs/reference/cli/sync.md`'s "`sh_before:`/`sh_after:` shell
hooks" section.

## reasoning recurrence

What `GgenIgniter.RecurrenceDetector.scan/2` detects: a repeated
`reasoning_class` (read from an OCEL-shaped reconciliation event's
attributes — `reasoning_class` or `reasoning_class_id`) that recurs across
at least `:min_distinct_runs` (default 2) explicit `reconcile_run` objects
with at least `:min_occurrences` (default 3) total classified events —
"repetition inside a single run is not sufficient evidence of cross-run
recurrence." A qualifying recurrence produces a candidate map with
`"standing" => "CANDIDATE"` and `"authority" => "NONE"`: the detector is
"deliberately OBSERVE/SELECT only" — it never writes a pack, edits a
template, invokes ggen, or acquires actuation authority; a returned
candidate stays `CANDIDATE`/`NONE` until a separate manufacturing/admission
path constructs and verifies a reusable artifact. See
`lib/ggen_igniter/recurrence_detector.ex`.

## reconciliation

Comparing a recipe's prior manifest-tracked output paths against the current
run's real new output paths to mechanically detect a rename or removal
upstream in the ontology (`stale = old_paths - new_paths`,
`Manifest.stale_paths/2`), then applying one of three named policies
(`--on-stale refuse|prune|preserve`). This is what turns `mix
ggen_igniter.sync` from a stateless generator into a stateful reconciler.
See `docs/reference/reconciliation/manifest.md`,
`docs/reference/reconciliation/stale-artifacts.md`.

## standing

Two senses, one entry. **(1) Receipt standing** — `GgenIgniter.Receipt.standing/0`,
a closed set of exactly five atoms
(`:alive`, `:refused`, `:compensated`, `:build_broken`, `:compensation_failed`);
`Receipt.new/1` raises `ArgumentError` on any other value. `:alive` =
succeeded, manifest advanced. `:refused` = fail-closed refusal before any
actuation, nothing touched disk. `:compensated` = files were written,
verification failed for a non-compile reason, undo restored prior bytes.
`:build_broken` = same shape as `:compensated`, but specifically because the
generated content itself does not compile. `:compensation_failed` =
CATASTROPHIC — files were written, verification failed, and the attempt to
restore them ALSO failed for one or more paths. Assigned by
`ReconcileReactor.run/1`'s full lifecycle; a failure inside the CLI's inline
pipeline (`Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`) is still a raised
exception with no standing, EXCEPT the one narrow, disclosed case where that
pipeline constructs a minimal `standing: :alive` receipt purely to record
`sh_before:`/`sh_after:` shell-hook invocations (see "shell hook") — that
receipt does not represent a full verify/compensate lifecycle the way
`ReconcileReactor`'s does. **(2) Capability standing** — the derived status of
a claim about an exact subject: `ALIVE` (observed execution on the exact
admitted subject), `PARTIAL_ALIVE` (some parts alive), `BLOCKED` (a named hop
cannot proceed), `UNSUPPORTED` (no capability, distinct from a refusal), plus
`UNKNOWN`, `BUILD_BROKEN` and typed `REFUSED:<CODE>`. Capability standing
lives in receipts bound to an identity, never stored as a literal. See
`docs/reference/evidence/standing.md`.

## stale artifact

A real, on-disk file that a **prior** run of a given `(template,
out_template)` recipe wrote (per that recipe's manifest entry) that the
**current** run does not write — the mechanical signature of a rename or
removal upstream in the ontology. Computed as
`Manifest.stale_paths(old_entry, new_paths)`. See
`docs/reference/reconciliation/stale-artifacts.md`.

## symlink boundary

The pack-lock law (v26.10.2, `ee10e7b`) governing which symlinks a pack
digest may lawfully contain (`GgenIgniter.PackLock`): a canonical symlink
whose resolved target stays inside the pack's enclosing git toplevel (the
in-repo canonical form, e.g. ash_pplan's
`priv/ggen/<pack>/ontology.ttl -> ../../ontology.ttl`, the "referenced,
never copied into the pack" ontology law) is a lawful pack member,
content-hashed with tag `"L"` — swapping the target moves the digest, so a
locked pack refuses `PACK_DIGEST_MISMATCH` on the swap. A target that
leaves the toplevel, any directory symlink, and any symlink loop or
dangling link refuse `PACK_SYMLINK_ESCAPE` (never a hang). Outside a git
repo the pack root itself is the boundary (the pre-26.10.2 law, unchanged
for tmp fixtures). See `lib/ggen_igniter/pack_lock.ex`'s "Symlink law"
moduledoc section, `docs/status.md`'s pack-lockfile row.

## targetPack

The `sj:targetPack` vocabulary term on an admitted work order
(`priv/ggen/semantic-jira-pack/ontology.ttl`,
`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`): binds the
order to one pack, enforced by `GgenIgniter.SemanticJira.TargetPack.enforce!/2`
at BOTH actuation hops — `mix ggen_igniter.sync` (and `ReconcileReactor`)
and the local backend of `mix semantic_jira.execute` — so a mismatch
refuses `REFUSED:TARGET_PACK_MISMATCH` / `mu_unlawful` before anything
runs (no rev-parse, no pipeline, no receipt, ledger byte-unchanged); a
`nil` targetPack names no constraint. The external `--receipt` execute
backend checks no targetPack: the xaas fabric owned the execution. See
`docs/status.md`'s `sj:targetPack` row, `docs/reference/cli/index.md`'s
Semantic Jira suite entry.

## semantic delta

Not this codebase's own literal phrase — its real equivalent is the stale
path set (`Manifest.stale_paths/2` = old outputs minus new outputs) at the
default pipeline's path-set-vocabulary layer, and `PendingActuation`'s
per-item `previous_hash`/`desired_hash`/`plan_unchanged?/1` comparison at the
Reactor pipeline's richer IR layer — the mechanically-computed difference
between what a recipe previously produced/owned and what the current
ontology-driven run now intends. See
`docs/reference/reconciliation/destructive-evolution.md`.

## semantic compiler

`ggen_igniter`'s own ontology-load → SPARQL-query → EEx-render → guarded-write
pipeline — the "Semantic Compilation Pipeline" — implemented entirely in
Elixir as a from-scratch port of the real Rust `ggen`'s pipeline shape
(sharing no code with it, except for one embedded Rust NIF: the default
oxigraph query engine). See `docs/integrations/ggen/semantic-compilation.md`.

## autonomic software manufacturing

The paradigm realized by `ggen_igniter`: closed-loop software generation and
reconciliation where formal knowledge (RDF ontologies) compiles
deterministically into verified, self-healing Elixir project state with zero
unmanaged drift, fail-closed admission, automated compensation, and
persistent audit standing.

## REFUSED_*

A typed refusal: a gate that can and does say no, carrying a code. Canonical
text form `REFUSED:<CODE> <detail>`; the enumerated set is
`priv/schema/refusals.schema.json`, accessed via `GgenIgniter.Refusals`
(`docs/reference/refusals.md`). Epoch verdict atoms (`REFUSED_LEGACY_EDIT`,
...) and plan codes (`REFUSED_EPOCH_*`) map to codes without the `REFUSED_`
prefix. Internal sub-reasons emitted as bare `{:error, :reason}` atoms are
declared as `wrapped_reasons` under their parent code. UNSUPPORTED is not
REFUSED: a refusal is a decision, unsupported is a missing capability.

## broken term (mu_on_O, admission_vacuous, mu_unlawful, R_missing_*, R_not_fed_back)

The one term of `A = mu(O*)`, `R = receipt(A)` a failure violates.
`mu_on_O`: manufacture from unadmitted input. `admission_vacuous`: a gate that
never refuses, so O* = O. `mu_unlawful`: manufacture that destroys admitted
capability. `R_missing_identity` / `_authority` / `_consequence` / `_replay` /
`_standing`: a receipt lacking that one of its five fields. `R_not_fed_back`:
a receipt that never re-enters the next observation. Each registry entry in
`refusals.schema.json` carries a non-null `broken_term`: one of these terms,
or `not_applicable` with a `not_applicable_reason` when no term is broken.

## gate

A check that admits or refuses. A gate is only informative if it has been
witnessed refusing (anti-vacuity: mutating the input makes it fail). Examples:
`mix ggen_igniter.epoch.check`, `mix ggen_igniter.hand_authored`, SHACL
admission of work orders.

## court

A verification lane that tries to falsify a claim on the exact landed subject
(for example the epoch freshness court, `GgenIgniter.EpochFreshness`); courts
kill, generators only propose.

## risk tier

Deterministic classification of a manufactured change (diff) into
`low`/`medium`/`high` from a path-weight model (longest-prefix
match; unmatched paths default to the privileged weight — fail-closed), plus
the number of machine approvals the tier requires. Pure policy, not
actuation: it computes a tier/score/approvals/signals triple other code may
consult; it never writes or admits anything itself, and a high-risk diff
never selects its own reviewers (the landing pipeline runs tiering at order
2, before fan-out review at order 4). See
`lib/ggen_igniter/review/risk_tier.ex`.

## machine approval

The count of automated gate passings a risk tier requires before a change
may land — `approvals/1` on a
`GgenIgniter.Review.RiskTier.Assessment` (`low` 0, `medium` 1, `high` 2),
recorded additively on `GgenIgniter.Receipt` as
`risk_tier`/`risk_score`/`risk_approvals`. The module is policy only — it
computes the required count; the gates that satisfy it are the landing
pipeline's stages. See `lib/ggen_igniter/review/risk_tier.ex`,
`lib/ggen_igniter/receipt.ex`.

## review perspective

One lens over a reviewed diff: a `review_diff/2` behaviour implementation
returning structured findings. The registry `perspectives/0` pins the four
shipped lenses (correctness, invariants, chicago_tests, epoch_law); the
aggregation core fans the diff out over them with `Task.async_stream`.
Perspectives are pure functions — agent execution is out of scope for the
layer. See `lib/ggen_igniter/review/perspective.ex`.

## verifier voting (M-verifier quorum)

Majority vote over a single review finding by M independent 1-arity
verifier functions (`finding -> :sustain | :reject | :abstain`). Sustained
iff `sustain_count >= floor(M/2) + 1` AND `sustain_count > reject_count`;
abstentions count toward M but toward neither side (M = 3: 2-0 passes,
1-1-1 fails). With no injected verifiers every finding is rejected — fail
closed. See `lib/ggen_igniter/review/verifier.ex`.

## suppression key

The deterministic key a cross-round repeat suppression chain is built on:
a vote-surviving finding whose key was `:posted` in the latest prior round
is suppressed (a carried repeat, not news); keys embedding the line mean
different-line `:pre_existing` findings are never suppressed. Applied only
to vote survivors — a vote-rejected finding is suppressed by the vote and
never resurrected. See `lib/ggen_igniter/review/filter.ex`.

## round cap / REVIEW_ESCALATED

The convergence loop's bounded-round law: a reviewed subject is re-reviewed
per content-sha until it passes, its findings are fixed-and-advanced, or
the cap (`@max_rounds`) is exhausted — at which point the round record
takes the terminal state `REVIEW_ESCALATED` (a real `GgenIgniter.Receipt`
with the review attrs), never a silent round 4. The cap is checked before
any reviewer dispatch. See `lib/ggen_igniter/convergence.ex`,
`lib/ggen_igniter/review_store.ex`.

## security finding

One entry in the security gate's findings ledger, produced by a
`@checks` implementation over ADDED diff lines only (secrets in diff, shell
interpolation, path traversal, dependency change, hook/settings change).
Dedup by stable id (`"SEC-" <> category <> "-" <> sha8` over
category|file|rule|normalized evidence; line deliberately excluded, so a
reformat keeps ledger continuity); evidence centrally redacted. Verdict is
`:blocked` iff any finding is `open`. See
`lib/ggen_igniter/security_review.ex`,
`lib/ggen_igniter/security_review/receipt.ex`.

## SECURITY_BLOCKED

The typed standing of a landing blocked by open security findings — exit
code 5 from `mix ggen_igniter.security_review` and the pre-step branch of
`mix semantic_jira.complete`. Distinct standing from `:drift`'s BLOCKED:
a security block is its own refusal class, never folded into another. See
`lib/ggen_igniter/task_contract.ex`,
`lib/ggen_igniter/semantic_jira/complete.ex`.

## auto-clear

The security ledger's transition where a previously `open` finding absent
from the current run's finding set becomes `auto_cleared` with
`cleared_at_commit` set. A cleared id never resurrects: if the same defect
reappears later it is still recorded `auto_cleared` — the clear decision is
a fact about the code, not something a re-diff overrides. See
`lib/ggen_igniter/security_review/receipt.ex`.

## incident corpus

The review-eval harness's seeded corpus of real incidents:
`.ggen_igniter/review-evals/corpus.jsonl`, one JSON object per line
(schema_version 1), each a defect case (`case_id`, git fix-commit source,
defect invariant, located file/line with tolerance, provenance). Seeded from
real fixed defects, scored for recall, and sealed into the eval baseline.
See `lib/ggen_igniter/review_eval/corpus.ex`.

## review eval baseline

The sealed admission standard for the review pipeline:
`.ggen_igniter/review-evals/baseline.json` (`run_id`, `head_sha`,
`corpus_digest`, `recall`, `per_surface`). A candidate run is admitted iff
its recall >= baseline recall AND no per-surface recall drops more than the
surface tolerance; errors count as missed (fail-closed). Sealing refuses
unless the run receipt exists and its corpus digest matches the current
corpus. See `lib/ggen_igniter/review_eval/gate.ex`.

## landing receipt

The per-run evidence artifact of a staged landing:
`<receipts_dir>/<run_id>/landing-receipt.json`, plus one per-stage receipt
`stage-<order>-<name>.json`, each embedding real captured command output —
a `:pass` with empty output is invalid and never reports ALIVE. The final
report is never a single boolean. See
`lib/ggen_igniter/landing_pipeline.ex`.

## stage contract

The behaviour every landing-pipeline gate implements: `name/0`,
load-bearing integer `order/0` (risk tiering precedes fan-out review), and
`run/1` returning exactly one of `{:pass, receipt}` / `{:block, reason,
receipt}` / refused — with `Enum.reduce_while/3` short-circuiting on the
first block, so later stages never run once an earlier gate refuses. Stage
resolution is fail-closed: a registry module that does not exist is the
typed refusal `{:stage_module_missing, module}`, never a silent skip. See
`lib/ggen_igniter/landing_pipeline/stage.ex`,
`lib/ggen_igniter/landing_pipeline.ex`.

## projection backend (:projection)

The sjira execute backend (wave W8) where one work order renders through
the real reconciliation pipeline pinned to a pack.lock digest: resolve the
order's `sj:targetPack`, scope to one row/template by `sj:capabilityId`
via the pack's `projections/<capability_id>.rq`, write via
`GgenIgniter.Actuate.write_file!/3` at `sj:targetPath` (guarded write =
idempotency surface: `:written`/`:unchanged`/`:skipped_exists`), then run
post-render gates plus falsifier-to-gate projection. Any failure refuses
with standing NOT advanced. See
`lib/ggen_igniter/semantic_jira/projection.ex`.

## epoch plane

One implementation-plane file glob bound by the epoch law
(`Admit(f) ⟺ FreshEpoch(f)`). Three courts, one per plane:
`lib/**/*.ex`, `config/**/*.exs`, `priv/repo/migrations/**/*.exs` — all
three stamped by default by `GgenIgniter.EpochWatermark.stamp!/3` and
judged by the same closed verdict set in `GgenIgniter.EpochFreshness`. See
`lib/ggen_igniter/epoch_watermark.ex`, `lib/ggen_igniter/epoch_freshness.ex`.

## pack bootstrap

Cold reconstruction of bounded system state from durable artifacts only
(git refs, canonical RDF, receipts, OCEL/TransitionLog, provider registry,
explicit config), each source an explicit argument, emitted as canonical
JSON plus a `state_digest`. An unreadable or tampered input is refused, not
skipped. See `lib/ggen_igniter/semantic_jira/bootstrap.ex`.

## G* fixed point

The ggen-loop closure target: the loop driving its own completion —
`mix semantic_jira.complete` loops frontier -> execute (via the
`:projection` backend) -> reconcile until the frontier is empty, with each
landing passed through the no-human review pipeline (risk tier, review,
convergence, security gate, review-eval gate) instead of a human approver.
Falsifier F1: the reference receipt replays with `|Δ|=0`; a nonzero delta
that still admits violates F1. The "G*" name is the wave's informal label
(not literal module vocabulary); the on-disk referents are
`GgenIgniter.SemanticJira.Complete`, `GgenIgniter.SemanticJira.Projection`,
and the falsifiers in `docs/jira/v26.10.20/RESTART_HANDOFF.md`.

## landing pipeline

`GgenIgniter.LandingPipeline` — one candidate landing driven through the
FIXED, ordered stage registry in process: each stage is a real
`GgenIgniter.LandingPipeline.Stage` behaviour implementation, and the order
is load-bearing (risk tiering at order 2 precedes fan-out review at order 4,
so a high-risk diff can never select its own reviewers). `reduce_while`
short-circuits on the first `:block`/`:refused`; stage resolution is
fail-closed — a missing registry module is the typed refusal
`{:stage_module_missing, module}`, never a silent skip. Stage 0
(`base_integrity`, implemented in the pipeline itself) proves the base
premise against real git before any registry stage runs. Evidence is never
a single boolean: per-stage + final receipts under
`<receipts_dir>/<run_id>/` (see "landing receipt"). See
`lib/ggen_igniter/landing_pipeline.ex`.

## convergence

`GgenIgniter.Convergence` — the per-content-sha round state machine that
re-reviews a subject in bounded rounds: `ROUND_PASSED` (terminal),
`ROUND_FIXED_ADVANCES` (class fixes apply, loop advances),
`REVIEW_ESCALATED` (findings at the cap; terminal, wrapped in a real
`GgenIgniter.Receipt`), never a silent round 4. The cap is checked BEFORE
any reviewer dispatch, and `decide/2` is total — no raise path. Rounds 2+
review only new/changed hunks; a finding whose hunk is unchanged is
carried, not re-posted. See `lib/ggen_igniter/convergence.ex` (state
machine), `lib/ggen_igniter/convergence/classes.ex`,
`lib/ggen_igniter/convergence/hunks.ex`.

## falsifier gate

The projection backend's falsifier-to-gate bridge: each order falsifier
(`order["falsifiers"]`, e.g. `"urn:semantic-jira:falsifier:EXEC-1:f1"`) is
bound to the capability's falsified-state query written once into
`verify/<capability>-falsifier-<n>.unbound.rq` in a STAGING COPY of the
pack, so the falsifier rides the same `verify_unbound` census as the real
`gates/*.rq` and can actually fire (a falsifier with no gate is a court
that cannot fire). A capability with falsifiers but no falsified-state
query refuses `{:falsifier_gates_missing, id}` (`admission_vacuous`).
Projection evidence maps falsifier URNs to `survived`/`killed` from the
real gate report. See
`lib/ggen_igniter/semantic_jira/projection.ex` §5,
`lib/ggen_igniter/semantic_jira/execute.ex`.

## epoch court

The epoch-law verification lane: `GgenIgniter.EpochFreshness` ("the epoch
freshness court") judges every implementation-plane file of a candidate
tree against a stamped `GgenIgniter.EpochWatermark` and returns one typed
verdict per file under the per-file binary law
`Admit(f) ⟺ FreshEpoch(f)` — three witnesses, in order of authority:
receipts admit, similarity falsifies, blame informs (git authorship is
recorded but never decides, because delete-and-re-add launders blame).
Bound to all three planes (see "epoch plane"); falsifier F2 in
`docs/jira/v26.10.20/RESTART_HANDOFF.md` exercises the config/migrations
courts. See `lib/ggen_igniter/epoch_freshness.ex`,
`lib/ggen_igniter/epoch_watermark.ex`.

## review-eval

The review-pipeline admission harness (`GgenIgniter.ReviewEval.*`):
a corpus of real incidents seeded from fixed defects
(`review_eval/seed.ex` → `corpus.ex`), a scorer running the corpus against
a candidate reviewer and scoring recall (`scorer.ex`, per-run receipt in
`receipt.ex`), and an admission gate over the sealed baseline
(`gate.ex` — see "review eval baseline"). The gate admits iff candidate
recall ≥ baseline recall with no per-surface drop beyond tolerance; errors
count as missed, fail-closed. See `lib/ggen_igniter/review_eval/`,
`docs/reference/cli/review-eval-gate.md`.

## sealed baseline

Alias for the sealed artifact of "review eval baseline":
`Gate.seal/1` writes `.ggen_igniter/review-evals/baseline.json` only when
the run receipt exists, its corpus digest matches the current corpus, and
the run's head is an ancestor of HEAD — after which it is the fixed
admission standard candidates are scored against, never silently resealed.
See `lib/ggen_igniter/review_eval/gate.ex`.

## stage behaviour

Alias for "stage contract": `GgenIgniter.LandingPipeline.Stage`, the
behaviour (`name/0`, load-bearing `order/0`, `run/1` → `{:pass, ...}` /
`{:block, ...}` / refused) every landing-pipeline gate implements. See
`lib/ggen_igniter/landing_pipeline/stage.ex`.

## pack lock

`GgenIgniter.PackLock` — the pack lockfile (`ggen_igniter.pack.lock`,
schema_version 1, sorted-key JSON) pinning each pack to the sha256 of its
on-disk content: a deterministic walk (path-sorted, tag `"F"` file / `"L"`
symlink domain separation, mtimes and permissions excluded) whose digest
change detects a tampered or silently changed pack instead of trusting it.
`check/2` returns `:ok` or typed errors (`pack_digest_mismatch`,
`lock_missing`, `lock_invalid`); symlink handling is the pack-lock law of
"symlink boundary". Consumed by the `:projection` backend before any byte
is rendered. See `lib/ggen_igniter/pack_lock.ex`.

## See also

- `docs/status.md` — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status of every
  capability named above
- `docs/index.md` — full documentation map
- `docs/architecture/overview.md` — the ownership table these terms compose
  into (ggen/Igniter/Ash/Reactor/OTP/Controller/Manifest/Receipt)
