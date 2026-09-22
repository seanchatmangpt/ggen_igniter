export const meta = {
  name: 'errc-closure-v26-9-20',
  description: 'Fan out ERRC closure streams (ggen_igniter x6, xaas x2, ash_a2a x1) in isolated worktrees, adversarially qualify each, repair, return receipts for serial merge',
  phases: [
    { title: 'Construct', detail: 'one agent per stream in its own worktree' },
    { title: 'Qualify', detail: 'gate re-run + falsifier + doctrine lens per stream' },
    { title: 'Repair', detail: 'fix-forward on qualifier findings' },
  ],
}

const GGEN = '/Users/sac/ggen_igniter'
const XAAS = '/Users/sac/xaas'
const A2A = '/Users/sac/ash_a2a'
const GGEN_BASE = args.ggenBase
const XAAS_BASE = args.xaasBase
const WT = '/Users/sac/ggen_igniter-wt2'

const COMMON = `
HARD RULES (all streams):
- First action: cd into the TARGET REPO ABSOLUTE PATH given below, run \`pwd && git remote -v && git rev-parse --abbrev-ref HEAD\` and echo it verbatim. If the remote is not the expected repo, stop and report a mismatch.
- Work ONLY inside your own git worktree (created with git worktree add from the exact base SHA given). NEVER edit the primary working tree of any repo. Other sessions and a running full \`mix test\` use the primary trees.
- Fix-forward only: never rebase, never git reset, never force-push, never push at all. Commit with \`git commit -F <file>\` (write the message with the Write tool; never inline -m for multi-line text). Verify the landed message with \`git log -1 --format=%B\`.
- Chicago-school tests only: real files, real subprocesses, real oxigraph, real Postgres if used. NO Mox/Mimic/Patch/:meck/mockall/Mock(/MagicMock anywhere. Verify with the exact repo grep: grep -rn --include='*.ex' --include='*.exs' --include='*.rs' --include='*.py' --exclude-dir=_build --exclude-dir=deps -E '(use|import) +(Mox|Mimic|Patch)\\b|(Mox|Mimic|Patch)\\.|:meck\\.|mockall|MagicMock|Mock\\(' test lib native  (must exit 1 with no output).
- Ontology-first: reusable structure goes in the pack ontology/queries/templates and is generated; do not hand-write Ash resources/domains (a repo hook blocks it). Hand-written code is the irreducible residue and must carry an explicit UNSUPPORTED(generator-capability) note when a generator path does not exist.
- After every Edit/Write, re-Read the file to confirm it landed. After edits show \`git diff --stat\`.
- Do not run the FULL \`mix test\` (takes ~25 min and the primary tree is already running one). Run narrow suites: your new tests, plus the semantic_jira, semantic_a2a, pack and doctor tests relevant to files you touched. Speed up setup with APFS clones: \`cp -Rc <primary>/deps <primary>/_build .\` and, for ggen_igniter, \`mkdir -p native/ggen_graph_nif && cp -Rc <primary>/native/ggen_graph_nif/target native/ggen_graph_nif/\`; fall back to \`mix deps.get\` if that fails.
- To avoid merge conflicts, do NOT edit docs/status.md, CHANGELOG.md, or the mix.exs version. Instead write your status rows/notes to docs/jira/v26.9.20/streams/<stream>.md (ggen_igniter) or docs/streams/<stream>.md (other repos); the integrator consolidates them.
- Status vocabulary: ALIVE only for observed execution of the exact subject; PARTIAL_ALIVE / BLOCKED / UNSUPPORTED(generator-capability) / REFUSED / UNKNOWN otherwise. Never claim planned/inspected work as executed. Paste real command output in your receipt.
- Blocker branches the search graph: if one edge is irreducible, quarantine it, record it as BLOCKED/UNSUPPORTED with evidence, and finish everything else in the stream.
- Final answer: ONLY the structured receipt (schema enforced).
`

const RECEIPT = {
  type: 'object',
  properties: {
    stream: { type: 'string' },
    repo: { type: 'string' },
    worktree: { type: 'string' },
    branch: { type: 'string' },
    base_sha: { type: 'string' },
    head_sha: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    commands: { type: 'array', items: { type: 'string' }, description: 'exact commands run with exit code and a one-line real result' },
    status: { type: 'string', enum: ['ALIVE', 'PARTIAL_ALIVE', 'BLOCKED', 'UNSUPPORTED', 'BUILD_BROKEN'] },
    generated_vs_handwritten: { type: 'string' },
    unsupported_or_blocked: { type: 'array', items: { type: 'string' } },
    falsifiers: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['stream', 'repo', 'worktree', 'branch', 'base_sha', 'head_sha', 'files_changed', 'commands', 'status', 'summary'],
}

const QUAL = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          description: { type: 'string' },
          evidence: { type: 'string' },
          fix_hint: { type: 'string' },
        },
        required: ['severity', 'description', 'evidence'],
      },
    },
    evidence: { type: 'string' },
  },
  required: ['verdict', 'issues', 'evidence'],
}

const GGEN_CTX = `TARGET REPO (absolute): ${GGEN}   base SHA: ${GGEN_BASE}
Create your worktree: cd ${GGEN} && git worktree add -b <BRANCH> ${WT}/<STREAM> ${GGEN_BASE}   (from the primary tree, but do all edits under the worktree).
Read ${GGEN}/CLAUDE.md, docs/status.md, docs/architecture/adr/ADR-010-event-sourced-standing.md, ADR-011-reduce-sj-toward-public-vocabularies.md, docs/jira/v26.9.19/013-a2a.md and the existing lib/ggen_igniter/semantic_jira/*.ex + lib/ggen_igniter/semantic_a2a.ex + priv/ggen/semantic-jira-pack/ + test/ggen_igniter_semantic_*.exs before designing.
Existing public API you must keep backward compatible: GgenIgniter.SemanticJira (promote/3, definition_digest/1, project/2, frontier_from_events/3, execution_package, work_order_digest), SemanticJira.Reconciler.reconcile/4, SemanticJira.TransitionLog, SemanticJira.Descriptor, SemanticJira.Shacl, SemanticA2A.`

const STREAMS = [
  {
    key: 'full-shacl-crown', repo: 'ggen', branch: 'errc/full-shacl-crown',
    task: `ERRC Raise: make the autonomics crown test (test/ggen_igniter_semantic_jira_autonomics_crown_test.exs) admit candidate WorkOrders through the FULL shipped shape priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl (via SemanticJira.Shacl) instead of the inline subset shape. Add negative cases (candidate violating each major constraint is REFUSED with the typed reason and never reaches the log), keep the concurrent-writer and replay-after-kill properties, and make Reconciler.reconcile/4 (or a thin admission helper in lib/) able to run SHACL admission of the work order against the full shape before promote/3 so the crown test exercises the same code production would. If the full shape rejects the crown's seed for a legitimate reason, fix the seed, not the shape. Falsifier: a WorkOrder missing a required property that the inline subset accepted must now be REFUSED.`,
  },
  {
    key: 'prov-o-events', repo: 'ggen', branch: 'errc/prov-o-events',
    task: `ERRC Create/Raise: PROV-O / RDF serialization of TransitionLog events. New module lib/ggen_igniter/semantic_jira/provenance.ex that renders a log event (receipt -> canonical-state transition) as Turtle using prov:Activity / prov:Entity / prov:wasGeneratedBy / prov:used / prov:wasAttributedTo / prov:startedAtTime plus dcterms identifiers, carrying definition_digest, snapshot digest and receipt digest as stable IRIs/literals; and a reverse parse (Turtle -> event map) so the log can be REPLAYED from RDF. Prove with real oxigraph: load the emitted Turtle through GgenIgniter.Ontology/Engine, run a real SPARQL query that recovers the frontier ordering, and assert round-trip equality of event maps (state-based, no mocks). Add a gate query file under priv/ggen/semantic-jira-pack/gates/ only if it is loaded by pack health without breaking it (pack tests glob gates/*.rq and templates/*.eex; runtime-only templates go under runtime-templates/). Add a mix task or TransitionLog export function (e.g. TransitionLog.export_turtle/1). Falsifier: tampering one digest literal in the Turtle must make replay refuse. Public TransitionLog API must stay backward compatible (another stream adds a Store behaviour concurrently: add your functions in provenance.ex and only a minimal delegating export in transition_log.ex).`,
  },
  {
    key: 'sj-vocab-reduction', repo: 'ggen', branch: 'errc/sj-vocab-reduction',
    task: `ERRC Reduce: implement ADR-011 (currently PLANNED): map the sj: vocabulary in priv/ggen/semantic-jira-pack/ontology.ttl toward public vocabularies (oslc_cm / dcterms / PROV-O / SHACL) WITHOUT breaking existing gates, templates or tests. Do prior-art first: check ~/ggen-marketplace/packs for existing OSLC/PROV mappings and reuse them. Deliver: (1) alignment axioms (rdfs:subClassOf / rdfs:subPropertyOf / owl:equivalentProperty / skos:exactMatch as appropriate) from each sj: term to its public counterpart in the ontology; (2) a new gate query that FAILS if an sj: term with a public counterpart lacks an alignment (anti-join), following the numbering convention of existing gates and registered where pack health/doctor expects; (3) a test proving every sj: class/property is either aligned or explicitly listed as sj-native residue with a reason; (4) update ADR-011 status from PLANNED to IMPLEMENTED (or PARTIAL with the exact residue) with evidence; (5) write docs/jira/v26.9.20/streams/sj-vocab-reduction.md with the mapping table. Do not rename sj: terms in this pass (renames break generated code); alignment + gate first. Another stream edits shapes/ and semantic_a2a; you own ontology.ttl alignment sections and a new gate, keep the diff to those regions to ease merging.`,
  },
  {
    key: 'brce-receipt-emitter', repo: 'ggen', branch: 'errc/brce-receipt-emitter',
    task: `ERRC Eliminate caller-supplied receipts / Create: a receipt EMITTER so receipts consumed by SemanticJira.Reconciler.reconcile/4 are produced by a real run rather than hand-built maps. First establish what "BRCE" (the only DO path: parse->route->admit/refuse->diagnose/repair->construct->actuate->receipt->replay->standing) means in THIS repo: read docs/status.md, docs/architecture/adr/0009-runtime-shape-semantic-ir.md, docs/rfc/RFC-SEMANTIC-JIRA-v26.9.19.md, lib/ggen_igniter/receipt.ex and the Reactor pipeline (lib/ggen_igniter/reactors/reconcile_reactor.ex). Then build lib/ggen_igniter/semantic_jira/receipt_emitter.ex: given an admitted WorkOrder's execution_package and a real acceptance command actually executed via a real subprocess (System.cmd) in a scratch dir, produce a receipt map with identity (work order digest + definition_digest), authority, consequence (exit code, stdout digest, files changed hashes via GgenIgniter.Receipt.hash_files/1 where applicable), replay data and standing, digest-sealed so Reconciler.reconcile/4 admits it, and a tampered/edited receipt (changed exit code or digest) is REFUSED. Provide an end-to-end test: admit WorkOrder -> execute real command -> emit receipt -> reconcile -> transition logged -> dependent eligible; plus a failing command producing a non-success receipt that is REFUSED for transition (standing stays). If a piece of BRCE does not exist as code here, implement the smallest faithful subset and record the remainder as UNSUPPORTED/PARTIAL in your stream doc, do not fabricate.`,
  },
  {
    key: 'transition-store', repo: 'ggen', branch: 'errc/transition-store',
    task: `ERRC Create: a storage behaviour for the append-only transition log plus a real Postgres-backed store. Postgres IS running locally (pg_isready: /tmp:5432 accepting connections; find the credentials/db via env, ~/.pgpass, psql \\l, or repo config; create a dedicated throwaway database like ggen_igniter_transition_test). Deliver: lib/ggen_igniter/semantic_jira/transition_log/store.ex (@behaviour: append with exclusive per-digest and per-seq claims, list/stream ordered by seq, get by digest), the existing file implementation refactored to implement it WITHOUT changing the public TransitionLog API or on-disk format (existing reconciler/crown/descriptor tests must still pass), and TransitionLog.PostgresStore using Postgrex (add {:postgrex, ..., optional: true} scoped so consumers are not forced to depend; if postgrex/ecto is already in the lock via ash_postgres dev/test, reuse it). Enforce the same invariants in SQL: UNIQUE(digest), UNIQUE(seq), append-only (no UPDATE/DELETE; test that they are rejected via a trigger or revoked privileges), optimistic concurrency. Test with REAL Postgres, including concurrent writers from multiple processes (no duplicate seq), replay of projection from PostgresStore equals replay from FileStore for the same events. Tests skip with a NAMED visible reason (ExUnit tag + skip message) only when Postgres is unreachable. Keep the semantic_jira reconciler API: reconcile/4 should accept a store option defaulting to the file store. Another stream adds PROV-O export in provenance.ex; keep your transition_log.ex edits minimal and additive.`,
  },
  {
    key: 'external-do-capability', repo: 'ggen', branch: 'errc/external-do-capability',
    task: `ERRC Create: close UNSUPPORTED(generator-capability) for external_do skills in the ash_a2a projection. Background: ash_a2a.install (26.9.17) cannot emit the consequence override the gate-declared external_do skill (run_exact_head_court) needs, so lib/ggen_igniter/semantic_a2a.ex + priv/ggen/semantic-jira-pack/templates/a2a_manufacture.ex.eex refuse it. First research with real runs: read deps/ash_a2a (its DSL, installer, how skills/actions map, whether an action can declare a consequence/authority), and try Igniter-based post-install patching (Igniter.Code.* / Sourceror) on the manufactured resource to add the consequence override deterministically through the composed manufacture step (not by hand-writing Ash). If a lawful generator path works: implement it in the pack template/manufacture task, flip the skill from UNSUPPORTED to admitted, update gates/tests (the semantic_a2a pack/manufacture/dispatch tests: run them all), and add tests proving external_do executes ONLY with a granted actor and a receipt, is refused for nil/ungranted actors, and second manufacture run is inert. If it does not work: produce an exact falsifier (a failing real run captured in a test asserting the precise upstream limitation, e.g. the installer re-adding or refusing the override), file the upstream gap as docs/jira/v26.9.20/streams/external-do-capability.md with a minimal repro and the proposed ash_a2a change, and leave the UNSUPPORTED marker accurate. You own semantic_a2a.ex, a2a templates and a2a gates; another stream edits ontology.ttl alignment regions, so touch the a2a: ontology sections only.`,
  },
]

const XSTREAMS = [
  {
    key: 'xaas-semantic-jira-bridge', repo: 'xaas', branch: 'errc/semantic-jira-bridge',
    task: `ERRC Create/Raise - THE central edge. In ${XAAS} (base SHA ${XAAS_BASE}) create your worktree: cd ${XAAS} && git worktree add -b errc/semantic-jira-bridge /Users/sac/xaas-wt2/semantic-jira-bridge ${XAAS_BASE}. Do NOT touch the primary tree ${XAAS} (it has uncommitted edits from another session).
The ggen_igniter dependency in mix.exs is hex "~> 26.9.12" (26.9.20 is unpublished). Switch it in YOUR worktree to a path dependency on a ggen_igniter checkout containing the 26.9.20 Semantic Jira modules: create your own read-only-use checkout: cd ${GGEN} && git worktree add --detach /Users/sac/ggen_igniter-wt2/xaas-dep ${GGEN_BASE} and use {:ggen_igniter, path: "/Users/sac/ggen_igniter-wt2/xaas-dep", override: true}. Resolve any dependency conflicts (ash_a2a, ash, plug, bandit, req versions) with the smallest change; record what you had to change.
Read xaas CLAUDE.md/AGENTS.md, lib/xaas/ultracode/{semantic_work,semantic_receipt,semantic_crown,semantic_wave,court_receipt,lease}.ex, lib/mix/tasks/xaas.semantic.materialize.ex, docs/ultracode/wave-v26.9.19-receipts/semantic-autonomics-crown/, and ggen_igniter's GgenIgniter.SemanticJira.{Reconciler,TransitionLog,Descriptor}, GgenIgniter.SemanticJira, GgenIgniter.SemanticA2A.
Deliver Xaas.Ultracode.SemanticJiraBridge: (1) maps an Ultracode SemanticReceipt/CourtReceipt for a wave into the receipt shape SemanticJira.Reconciler.reconcile/4 admits; (2) on admit appends to TransitionLog and returns the new frontier via SemanticJira.frontier_from_events/3; (3) emits the XaaS execution descriptor from the admitted frontier via SemanticJira.Descriptor (carrying definition_digest + snapshot digest); (4) refuses (typed REFUSED) tampered receipts, stale/mismatched definition digests, and unadmitted work orders. Replace hand-written xaas logic that re-implements admission/promotion with calls into ggen_igniter where the semantics are identical (prove equivalence with a test before deleting; if not identical, keep and record why). Add the Chicago crown test test/xaas/ultracode/semantic_jira_bridge_crown_test.exs (no mocks, real files/subprocess/oxigraph, real Postgres if xaas uses it in tests): seed failing condition -> candidate WorkOrder -> SHACL admit -> frontier -> descriptor -> real Ultracode receipt -> transition -> dependent eligible -> kill producer and replay from the log -> same frontier. Run: mix compile --warnings-as-errors, mix format --check-formatted, mix credo (touched files), the new test and the existing ultracode/semantic tests. Note the ash_a2a agent card in xaas must stay consistent with the descriptor.`,
  },
  {
    key: 'xaas-closure', repo: 'xaas', branch: 'errc/xaas-closure',
    task: `ERRC Reduce/Eliminate for ${XAAS} (base SHA ${XAAS_BASE}): create worktree: cd ${XAAS} && git worktree add -b errc/xaas-closure /Users/sac/xaas-wt2/closure ${XAAS_BASE}. Do NOT touch the primary tree (uncommitted edits from another session; leave them). Facts already observed: local main is 267 commits AHEAD of origin/main; draft PRs #53-58 (branches feat/sa2a-computation-boundary, feat/v26.9.18-semantic-work-fabric, feat/ultracode-cron-wave, feat/v26.9.19-semantic-ultracode-dfcm, feat/v26.9.20-dfcm-event-simulation, feat/v26.9.20-zoe-event-simulation) are all already merged into local main (git rev-list --count main..origin/<b> is 0), so they are open on GitHub only because main was never pushed. Tasks: (1) make the gate pass in your worktree: mix deps.get if needed, mix compile --warnings-as-errors, mix format --check-formatted (this is the xaas#56 formatting failure: run mix format and commit the formatting fix), mix credo, and the fast/narrow test suites you can run (do not run the entire multi-thousand-test suite serially if it takes over 15 minutes; run the ultracode, semantic, zoe, sa2a, system_authority suites and report exactly what you ran). Pre-existing failures vs failures introduced by you must be distinguished with evidence (git stash is forbidden; compare against base SHA by running the same test on a second clean worktree at the base if needed). (2) Inventory ALL local and remote-tracking branches and worktrees of xaas (git branch -a, git worktree list, git tag): for each branch determine merged-into-main or not; produce a table in docs/streams/xaas-closure.md; for branches not merged, merge them in a fix-forward manner in your worktree ONLY if they are non-superseded (read the commit subjects; several 'backup/*', 'probe/*' were already recorded as superseded, tips preserved as archive/* tags); resolve conflicts by reading both sides, never -X ours/theirs, never batch conflict scripts. (3) List open GitHub PRs with gh (read-only) and record which are fully contained in main. Do not push and do not close PRs.`,
  },
  {
    key: 'ash-a2a-format', repo: 'ash_a2a', branch: 'errc/ash-a2a-format',
    task: `ERRC Eliminate downstream failure ash_a2a#27 (formatting) in ${A2A}. Base: run cd ${A2A} && git rev-parse HEAD and use that exact SHA (the primary tree has 2 uncommitted files from another session: leave them untouched). Create worktree: git worktree add -b errc/ash-a2a-format /Users/sac/ash_a2a-wt2/format <that SHA>. Read the repo CLAUDE.md/AGENTS.md. Run mix deps.get, mix compile --warnings-as-errors, mix format --check-formatted, mix credo, mix test (this repo is small; run it fully). Fix formatting (mix format) and any lint failure with fix-forward commits; confirm with gh (read-only) what PR #27 checks failed if accessible (gh pr view 27 --json headRefName,statusCheckRollup, gh run view --log-failed) and make sure the same failure now passes locally. If PR #27's branch exists, note its name and whether your fix should be merged into it; do not push. Also report how ash_a2a's installer behaves for the external_do consequence override (read lib/ and installer: does any DSL allow an action-level consequence/authority declaration?) in docs/streams/ash-a2a-external-do.md since ggen_igniter's external-do stream needs it; include file:line evidence.`,
  },
]

function ctxFor(s) {
  return s.repo === 'ggen' ? GGEN_CTX.replace('<BRANCH>', s.branch).replace('<STREAM>', s.key) : ''
}

function constructPrompt(s) {
  return `${COMMON}\n${ctxFor(s)}\nSTREAM: ${s.key}   BRANCH: ${s.branch}\n\nTASK:\n${s.task}\n\nWhen done: all work committed on ${s.branch} in your worktree (git status clean), receipt returned with real command output summaries.`
}

const all = [...STREAMS, ...XSTREAMS]

const results = await pipeline(
  all,
  (s) => agent(constructPrompt(s), { label: `build:${s.key}`, phase: 'Construct', schema: RECEIPT }),
  async (receipt, s) => {
    if (!receipt) return { s, receipt: null, quals: [] }
    const base = `TARGET: worktree ${receipt.worktree} (repo ${receipt.repo}, branch ${receipt.branch}, head ${receipt.head_sha}). cd there first, run pwd, git status, git log --oneline -8, and echo them. You are a QUALIFIER: you must not trust the builder's receipt (${JSON.stringify(receipt.summary)}); re-derive everything by running commands yourself. You may add commits ONLY of failing falsifier tests or trivial fixes clearly labelled; otherwise report issues. Do not push, rebase, or reset. Never run the full mix test suite unless the stream is ash_a2a (small). Stream task for reference:\n${s.task}\n`
    const lenses = [
      `LENS gate: independently re-run in the worktree: mix compile --warnings-as-errors; mix format --check-formatted; mix credo (or --strict on touched files); the stream's new tests AND the pre-existing suites touching modified files; the exact Chicago mock grep (must exit 1, no output); repo-specific guards (for ggen_igniter also: grep -rn -e '^ *use Ash' -e '^ *import Ash' -e '^ *alias Ash' -e '^ *require Ash' lib/ must be empty). Paste real outputs. Distinguish pre-existing failures (verify against base SHA ${receipt.base_sha} in a scratch checkout if any fail) from introduced ones. verdict=fail on any introduced failure.`,
      `LENS falsifier: construct the most adversarial concrete inputs/scenarios that would defeat the stream's central claim (tampered digests, concurrent writers, stale snapshots, malformed Turtle/receipts, missing required fields, second-run idempotence, replay after process kill, backward-compat of the public API). Run them for real. If you break the claim, add a failing test in the worktree on a commit labelled test(falsifier) and report it as a blocker with the failing output. If you cannot break it after a serious attempt, say what you tried.`,
      `LENS doctrine: check the diff against repo doctrine: ontology-first (generated vs handwritten honestly reported; no hand-written Ash outside allowlist), no over-claiming in docs/ADRs/stream docs (status vocabulary; ALIVE only with observed execution), public API backward compatibility, no edits to docs/status.md/CHANGELOG.md/mix.exs version, commit hygiene (fix-forward, messages landed correctly), no leftover TODO/dead code/debug output, no secrets. Flag every over-claim with evidence.`,
    ]
    const quals = await parallel(lenses.map((l, i) => () => agent(`${base}\n${l}`, { label: `qual${i}:${s.key}`, phase: 'Qualify', schema: QUAL })))
    return { s, receipt, quals: quals.filter(Boolean) }
  },
  async (q, s) => {
    if (!q.receipt) return { stream: s.key, receipt: null, verdict: 'BUILD_FAILED', issues: [] }
    const issues = q.quals.flatMap((x, i) => (x.issues || []).map((it) => ({ ...it, lens: i })))
    const blocking = issues.filter((i) => i.severity !== 'minor')
    if (!blocking.length) return { stream: s.key, receipt: q.receipt, verdict: 'pass', issues, repaired: false }
    const fixed = await agent(
      `${COMMON}\nYou are the REPAIR agent for stream ${s.key}. TARGET: worktree ${q.receipt.worktree} (repo ${q.receipt.repo}, branch ${q.receipt.branch}). cd there, pwd, git status. Fix-forward ONLY (new commits). Resolve every blocker/major issue below with a root-cause fix and a permanent guard (test/fixture), re-run the same failing check and the stream's narrow suites, re-run the mock grep and format/compile/credo. If an issue is a false positive, prove it with a run and say so. Issues:\n${JSON.stringify(blocking, null, 1)}\nOriginal stream task:\n${s.task}\nReturn an updated receipt (new head_sha, all commands, honest status).`,
      { label: `repair:${s.key}`, phase: 'Repair', schema: RECEIPT },
    )
    return { stream: s.key, receipt: fixed || q.receipt, verdict: fixed ? 'repaired' : 'repair_failed', issues, repaired: !!fixed }
  },
)

return results.map((r) => r || { stream: 'unknown', verdict: 'stage_dropped' })
