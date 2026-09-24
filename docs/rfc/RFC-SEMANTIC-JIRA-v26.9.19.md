# RFC — Semantic Jira: ontology-native work-order fabric (v26.9.19)

**Specification status:** FINAL_SPEC — closed for v26.9.24  
**Implementation subject at closure base:** `seanchatmangpt/ggen_igniter@292e40ab08a250ef3f049f9a80b4a65e332d9155`  
**Authority ceiling:** SELECT/CONSTRUCT; consequential DO remains external

## 0. Status of this document: RE-MANUFACTURE

This file is a **re-manufacture**, not the original text.

- Date of re-manufacture: 2026-09-20 (artifact observations 04:00–04:15Z, UTC)
- Reason: the original `RFC-SEMANTIC-JIRA-v26.9.19.md` (1,827 lines, SHA-256
  `4ae00b21d5e9c7a74f4d27cf7302bcdbad2b142a065edd1c69988a8c22872b77`) was created by a
  prior session on disk-only storage and never entered version control. Wave-1 searches
  (documented in the PR #20 body section "RFC status: LOST", fetched this session from
  `gh api repos/seanchatmangpt/ggen_igniter/pulls/20`, `updated_at` 2026-09-20T01:59:23Z)
  found no copy: `find` over `/Users/sac` (maxdepth 3), `/Users/sac/dev`, `/Users/sac/.zcode`,
  `/Users/sac/ggen-marketplace` (maxdepth 5), Spotlight `mdfind`, `/tmp`, `/var/folders`,
  and a read-only scan of the `/Users/sac/ggen_igniter` tree — all negative.
- The original SHA `4ae00b21…` is therefore unrecoverable and this file **supersedes** it.
- **No text was reconstructed from memory or invented.** Every factual claim below cites a
  live artifact read this session (repo file at head `58460d0`, a `gh api` response, or the
  forensic PR comment). Where a claim could not be observed, this document says UNKNOWN.

Standing context (all observed this session via API): PR #20
`feat(pack): manufacture Semantic Jira work orders from RDF`, state OPEN, **draft**,
head `58460d0f65f32c50770221d9531d194d1a98260d`, base `main`
`d84da1419a6945c6a8a64b8f6cdca9d0b2c9e0f3` (`gh api repos/seanchatmangpt/ggen_igniter/pulls/20`).
Clone used for this document: fresh `gh repo clone` into `/tmp/scj-finish/w2-a4` at the same head.

---

## 1. Summary

Semantic Jira is the capability of manufacturing work-tracking artifacts **from a canonical
RDF graph** instead of hand-written Markdown: `sj:WorkOrder` individuals are declared once in
the pack ontology, admitted through SPARQL gates + a real SHACL court + kernel/template
refusal guards, and projected deterministically into Jira-shaped tickets, PRDs, and a
family of typed projections — each execution bound to a durable receipt carrying the exact
semantic graph hash, with byte-identical replay as the acceptance bar.

The first repository-native slice ships as Core-profile pack `semantic-jira-pack` v26.9.19
(`priv/ggen/semantic-jira-pack/pack.toml`: `name = "semantic-jira-pack"`,
`version = "26.9.19"`), self-dogfooded: the pack's own graph contains work order **SJ-001**
("Manufacture Semantic Jira work orders from RDF",
`priv/ggen/semantic-jira-pack/ontology.ttl` line 49–67) plus the typed work-order fabric
**GALL-001..032** (32 work orders, verified this session by
`grep -c 'dcterms:identifier "GALL-'` over `ontology.ttl` = 32, contiguous GALL-001..GALL-032).

## 2. The pipeline, stage by stage

`canonical TTL graph → SPARQL + SHACL admission → deterministic projections → graph-bound receipt → deterministic replay`

| # | Stage | Implementing artifact (exact path) | Mechanism |
|---|---|---|---|
| 1 | **Canonical TTL graph** | `priv/ggen/semantic-jira-pack/ontology.ttl` (1,854 lines) + `priv/ggen/semantic-jira-pack/pack.toml` | `sj:WorkOrder` class + properties (`sj:baseSha`, `sj:standing`, `sj:authorityCeiling`, `sj:replayIdentity`, …); dogfood SJ-001; GALL-001..032 typed fabric with `sj:DependencyEdge` chains, courts, evidence requirements, acceptance criteria, falsifiers; header comment: "Markdown tickets are consequences of this graph; edit this graph … never a generated ticket" (ontology.ttl lines 14–16) |
| 2a | **SPARQL admission gates** | `priv/ggen/semantic-jira-pack/gates/010_work_order_subjects.rq`, `020_work_orders.rq`, `030_properties.rq`, `040_nodes.rq`, `045_description_integrity.rq`, `046_alive_receipt_crown.rq`, `050_frontier.rq` (7 gates) | `010` enumerates `sj:WorkOrder` subjects; `020` extracts the complete scalar row (OPTIONAL per field — a missing required scalar yields an incomplete row the template refuses); `030` properties; `040` labeled+described nodes; `045` description-integrity violations (blank/whitespace/IRI-echo/label-echo descriptions); `046` ALIVE-without-receipt-crown violations; `050` frontier = UNKNOWN work with satisfied typed dependency edges (nested MINUS, see §5). Gate execution proven by test `"every pack gate executes cleanly against the canonical graph"` (`test/ggen_igniter_semantic_jira_pack_test.exs` lines 242–267, asserts 7 gates via `GgenIgniter.Query.run/2`, and that SJ-001 stays frontier-eligible) |
| 2b | **SHACL admission court** | `priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl` (194 lines) + `lib/ggen_igniter/semantic_jira/shacl.ex` (720 lines, `GgenIgniter.SemanticJira.Shacl`) + `test/ggen_igniter_semantic_jira_shacl_test.exs` (426 lines, 20 tests) | Real SHACL-core validator compiled from the shipped shapes (minCount/maxCount, nodeKind, datatype, pattern, minLength/maxLength, hasValue, class, closed+ignoredProperties, SELECT-only `sh:sparql`); unsupported constructs (sh:in, sh:not, qualifiedValueShape, non-simple paths) **fail closed as violations, never silently skipped** (shacl.ex moduledoc; witnessed by tests at shacl test lines 320, 343). `$this` binding via injected `BIND` because sparql 0.3.12 has no pre-binding API (shacl.ex moduledoc, measured 2026-09-19) |
| 2c | **Kernel admission** | `lib/ggen_igniter/semantic_jira.ex` (`GgenIgniter.SemanticJira`, 991 lines) — `admit_work_order/1` (line 68) | Required-field check (`@required` line 35), regex courts `@sha` 40-hex / `@repo`, standing vocabulary, non-empty lists for courts/evidence/acceptance/falsifiers/projections, typed dependency + receipt-class + path-scope validation; every refusal typed `{:error, {:refused_work_order, reason}}`; admitted work orders gain `admitted: true`, `authority: "NONE"`, and a canonical `work_order_digest` (lines 85–101) |
| 2d | **Template refusal guards** | `priv/ggen/semantic-jira-pack/templates/jira.md.eex`, `templates/prd.md.eex` | Render-time fail-closed guards raising `REFUSED:SEMANTIC_JIRA_INVALID_WORK_ORDER`: subject-set vs row-set equality (incomplete/ambiguous scalar identity), unique `dcterms:identifier`, unique `sj:replayIdentity` (jira.md.eex lines 6–46; prd.md.eex identical guards) |
| 3 | **Deterministic projections** | `templates/jira.md.eex` → `docs/jira/<id>.md`; `templates/prd.md.eex` → `docs/prd/<id>.md` (PRD template landed in commit `6f76502`); `templates/projection.md.eex` → `docs/semantic-jira/<id>/<type>.<extension>` for **every** `sj:ProjectionSpec` | Executed through the real Reactor `--for-each` path: `mix ggen_igniter.sync --engine sparql --pack semantic-jira-pack:{jira,prd} …` (test helper `run_sync/4`, test file lines 37–63). 14 projection types declared in `@projection_types` (semantic_jira.ex line 25) and in the ontology as `sj:projection-jira, -wbpr, -prd, -ard, -vision, -fond, -hddl, -sa2a, -worker, -verification, -executive, -machine, -receipt, -replay` (ontology.ttl line 197); the generic template feeds each row through `GgenIgniter.SemanticJira.render_projection/3` (projection.md.eex line 89), which emits the `authority=NONE` header (semantic_jira.ex lines 723–739) |
| 4 | **Graph-bound receipt** | `lib/ggen_igniter/receipt.ex` (`GgenIgniter.Receipt`, 744 lines) | Durable receipt per sync: `receipt["standing"] == "alive"`, `receipt["files"]` contains every generated path, and `receipt["metadata"]["graph_hash"] == sha256(ontology.ttl)` — asserted in the pipeline test (test file lines 97–100) and the PRD test (lines 163–166) |
| 5 | **Deterministic replay** | Same `run_sync/4` executed twice; `GgenIgniter.SemanticJira.replay_check/2` (semantic_jira.ex line 570) for evidence-level replay | Second sync produces **byte-identical** Markdown (`File.read!(output_path) == first_bytes`, test lines 102–105) and equal `graph_hash` across both receipts (lines 107–114); replay evidence requirement defined at `sj:replay-evidence` (ontology.ttl lines 185–187) |

## 3. Admission boundary — full rejects list (fail-closed)

The falsifier matrix (commit `58460d0` "test(semantic-jira): admission boundary falsifier
matrix", describe block at `test/ggen_igniter_semantic_jira_pack_test.exs` lines 362+,
"One test per attack, named after the rejection class it witnesses") plus the wave-1 PR-body
boundary list (PR #20 body fetched this session) give the complete rejection surface:

1. **Incomplete scalar identity** — removing `dcterms:title` or `dcterms:identifier` refuses admission (class 1 tests, lines 378, 382); whitespace-only title/refusing whitespace-as-identity (lines 655, 663).
2. **Ambiguous scalar identity** — a duplicated `dcterms:title` or duplicated `sj:baseSha` resolving to two rows refuses (lines 390, 398).
3. **Duplicate WorkOrder IDs** — a second WorkOrder reusing `SJ-001` refuses; two individually valid WorkOrders sharing one identifier refuse (combinational bypass) (lines 409, 421); template guard jira.md.eex lines 40–43; SHACL uniqueness `sh:sparql` constraint shapes/work-order.shacl.ttl lines 51–62.
4. **Non-exact `baseSha`** — uppercase hex, 39-hex, 41-hex, leading whitespace all refuse — "exact means exact" (class 3 tests, lines 436–460); shape `sh:pattern "^[0-9a-f]{40}$"` (work-order.shacl.ttl line 27); kernel `@sha` regex (semantic_jira.ex line 36).
5. **Invalid standing** — lowercase and fabricated standings refuse; `REFUSED()` with an empty reason refuses ("a refusal must state its reason") (class 4 tests, lines 468, 482); shape pattern `^(UNKNOWN|PARTIAL_ALIVE|ALIVE|BLOCKED|BUILD_BROKEN|UNSUPPORTED|REFUSED\(.+\))$` (work-order.shacl.ttl line 29).
6. **Authority above CONSTRUCT** — `MERGE`/`DEPLOY` refuse; `CONSTRUCT` typos and trailing whitespace refuse; control: `OBSERVE` admits (class 5 tests, lines 495–523); shape pattern `^(OBSERVE|SELECT|CONSTRUCT)$` (work-order.shacl.ttl line 31).
7. **Missing required relations** — a graph without any one of `sj:requiresCourt`, `sj:requiresEvidence`, `sj:acceptance`, `sj:falsifier`, `sj:projection`, `sj:nextAction`, `sj:nextCheckpoint` refuses (class 6 parameterized test, line 531); shape `sh:minCount 1` on each (work-order.shacl.ttl lines 37–43).
8. **Undescribed relation targets** — label-only target, bare IRI target, and plain-literal target refuse (class 7 tests, lines 540–561); gate `045_description_integrity.rq` additionally refuses empty-string, whitespace-only, node-IRI-echo, and label-echo descriptions ("self-reference is not semantics") with witnessing tests at lines 603–642.
9. **Standing smuggling** — `ALIVE` without `sj:candidateSha` + `sj:subjectSha` + `sj:receipt` refuses; control: full receipt crown admits (lines 572, 583); enforced twice: gate `046_alive_receipt_crown.rq` and SHACL constraints (work-order.shacl.ttl lines 63–75, 183–193).
10. **Replay-identity collision** — two valid WorkOrders sharing `sj:replayIdentity` refuse (line 590); SHACL uniqueness constraint (work-order.shacl.ttl lines 90–100); template guard (jira.md.eex lines 44+).
11. **Malformed ontology** — a Turtle syntax error fails closed with no ticket actuated (line 671).
12. **Authority-requiring work without identity binding** — non-`NONE` `sj:authorityRequirement` must bind `sj:authority`, `sj:lease`, `sj:worker` (work-order.shacl.ttl lines 76–89); duplicate active exclusive leases on one concurrency key refuse (lines 145–156); ambiguous standing transitions (`UNKNOWN → ALIVE` skip) refuse (lines 117–130).
13. **Projection authority claims** — every `sj:ProjectionSpec` must carry `sj:authorityClaim` exactly `"NONE"` (`sh:hasValue`, work-order.shacl.ttl lines 107–109); violating test at shacl test line 174.

The wave-1 PR-body rejects list (fetched from PR #20 this session) is the subset of items
1–8 above; items 9–13 are the falsifier-matrix/SHACL additions landed in commits
`dd6ac93` and `58460d0`, including gates `045_description_integrity.rq` and
`046_alive_receipt_crown.rq`.

## 4. Zero-authority statement for generated artifacts

Generated Markdown carries **zero execution authority**:

- Every projection header carries `authority=NONE` (semantic_jira.ex `render_projection/3`,
  lines 728–732: `"… authority=NONE -->"`); kernel normalizes `authority: "NONE"` at
  admission (semantic_jira.ex line 99).
- Kernel moduledoc (semantic_jira.ex lines 1–13): "It does not issue runtime leases, grant
  authority, perform BRCE/CommandBus DO, merge, publish, deploy, or self-promote standing.
  Lease objects remain XaaS/Ultracode-owned; consequential DO remains BRCE-owned."
- Ontology promotion rule (every WorkOrder, e.g. SJ-001 ontology.ttl line 59): standing may
  advance only from an independent exact-head court receipt for the same subject; generated
  Markdown cannot promote itself.
- Falsifier `sj:projection-gains-authority` (ontology.ttl lines 93–95): treating a generated
  ticket as authority to actuate/merge/publish/deploy falsifies the projection boundary;
  witnessed in the pipeline test's boundary assertions (`zero independent actuation`,
  test lines 93, 153).
- This RFC document itself is documentation: it performs no DO, no merge, no publish, no
  standing promotion. PR #20 is held in draft.

## 5. CI incident record (NIF cache root cause + fix)

Sources: forensic PR comment
`https://github.com/seanchatmangpt/ggen_igniter/pull/20#issuecomment-5746425067`
(id 5746425067, created 2026-09-20T00:30:17Z, fetched this session), the PR body's
"CI honesty" section, commit log, and this session's `gh api …/actions/runs` fetch.

1. **Pre-existing NIF cache defect (not branch-introduced).** On hosted runners the native
   graph NIF failed to load from cached `_build`: `ggen_graph_nif.so: cannot open shared
   object file: No such file or directory`, failing engine suites identically on base
   `main` `d84da14` (run 35315548332) and on branch heads (e.g. run 35477774420 at
   `d1bcdb7`, 59 counted failing entries; same-head swings 69 vs 42 at `3190b32` — flaky
   cascade, membership shifting run-to-run per the forensic comment).
2. **Fix:** commit `c81f8dc` "fix(ci): force per-run NIF rebuild so cached `_build` cannot
   drop `ggen_graph_nif.so`" (PR #20 commits API, fetched this session).
3. **Branch-introduced pack failures (deterministic, 3 of 6 pack tests, both `d1bcdb7`
   runs per the forensic comment):** (a) 2x `SPARQL.Algebra.Expression not implemented for
   Atom :"$undefined"` — sparql 0.3.12 FILTER/EXISTS evaluation crash in pack queries;
   fixed by expressing the frontier gate as nested MINUS (commit `2e67fcf`; gate
   `050_frontier.rq` header documents the mechanism and the guarding test) and by the
   SHACL court's OPTIONAL+BOUND form (work-order.shacl.ttl lines 14–17, "measured
   2026-09-19"); (b) 1x refused-envelope tuple-shape drift between test expectation and
   `admit_work_order/1`; fixed in the falsifier-matrix commit `58460d0` (the matrix
   witnesses the current typed envelope `{:refused_work_order, …}`, semantic_jira.ex
   lines 102–105).
4. **Current truth (this session's fetch, 2026-09-20T~04:03Z):
   `gh api "repos/…/actions/runs?branch=feat/semantic-jira-v26.9.19&per_page=10"`:**

| run id | run # | head | conclusion | created_at |
|---|---|---|---|---|
| 35482802140 | 204 | `58460d0` | success | 2026-09-20T01:59:37Z |
| 35482795117 | 203 | `58460d0` | success | 2026-09-20T01:59:24Z |
| 35481346118 | 202 | `dd6ac93` | success | 2026-09-20T01:25:20Z |
| 35481344778 | 201 | `dd6ac93` | failure (step `mix test`; jobs API checked this session) | 2026-09-20T01:25:19Z |
| 35481012086 / 35481010863 | 200/199 | `6f76502` | cancelled | 2026-09-20T01:17:32Z / :30Z |
| 35480185576 / 35480182984 | 198/197 | `c81f8dc` | cancelled | 2026-09-20T00:59:05Z / :02Z |
| 35480047749 / 35480045821 | 196/195 | `2c1835e` | cancelled | 2026-09-20T00:55:48Z / :45Z |

Head `58460d0` has both runs green. Run 201's failure step (`mix test`) was verified via
the runs/:id/jobs API this session; its per-test list was NOT inspected (UNKNOWN) — its
head `dd6ac93` also produced run 202 success.

## 6. Verification table (observed 2026-09-20T04:00–04:15Z)

| Item | Status | Evidence (read this session) |
|---|---|---|
| PR #20 state/head/base | ALIVE (observed) | `gh api repos/seanchatmangpt/ggen_igniter/pulls/20`: OPEN, draft, head `58460d0f…`, base `d84da1419…` |
| Branch commit list (13 commits) | ALIVE (observed) | `gh api repos/…/pulls/20/commits` (3190b32 → 58460d0, listed §0/§5) |
| Pack file surface | ALIVE (observed) | Fresh clone at `58460d0`: 13 files under `priv/ggen/semantic-jira-pack/` (pack.toml, ontology.ttl, 7 gates, shapes/work-order.shacl.ttl, 3 templates), plus `lib/ggen_igniter/semantic_jira.ex` (991 lines), `lib/ggen_igniter/semantic_jira/shacl.ex` (720 lines), `test/ggen_igniter_semantic_jira_pack_test.exs` (1,108 lines), `test/ggen_igniter_semantic_jira_shacl_test.exs` (426 lines) |
| Hosted CI at head `58460d0` | ALIVE (both success) | Runs 35482795117 + 35482802140 (§5 table) |
| SPARQL gates 010–050 execute | ALIVE (hosted, at `58460d0`) | Guarding test `"every pack gate executes cleanly…"` passed inside runs 203/204; locally the guard is asserted, not re-executed, by this session (see local row below) |
| SHACL admission court | ALIVE (landed commit `dd6ac93`) | `shacl.ex` + shapes file + 20-test `ggen_igniter_semantic_jira_shacl_test.exs`; hosted green at `58460d0` |
| Admission falsifier matrix | ALIVE (landed commit `58460d0`) | Describe block, test file lines 362+, classes 1–7 + smuggling/uniqueness/integrity/syntax |
| Graph-bound receipt + byte-identical replay | ALIVE (hosted, at `58460d0`) | Pipeline test asserts `metadata.graph_hash == sha256(ontology.ttl)` and byte equality (test lines 97–114); passed in runs 203/204 |
| Handwritten ledger honesty | ALIVE | `HANDWRITTEN.md` row (2026-09-19) + `sj:ledger-unsupported-001` UNSUPPORTED row in ontology.ttl (tail of file) + commit `7676730` |
| Ticket day-pack provenance | ALIVE | `docs/jira/v26.9.19/` (7 tickets + `_RUNBOOK.md` + `_RUNLOG.md`); `_RUNLOG.md` records `mix ggen_igniter.sync --pack calver-ticket-day-pack:…` manufacture, 2026-09-19T17:35Z, 3 exits 0; manufactured in commit `019d34a` |
| Local `mix test` (full suite) | UNKNOWN (not run by this session) | Not executed in this session; hosted runs 203/204 are the green evidence. This document adds **no** local test claims. |
| Local gates on this doc change | see receipt | `mix format --check-formatted` and `mix credo` executed this session on the tree containing this file (results recorded in the PR-body append + commit receipt) |

## 7. Remaining checkpoints (landed vs in-flight at observation 2026-09-20T04:08Z)

Sibling agents are landing work concurrently; each item below is marked for **my**
observation window only and must be re-checked against the branch tip before merge.

1. **wbpr/ard/vision dedicated templates** — IN FLIGHT / NOT LANDED at `58460d0`:
   `templates/` contains only `jira.md.eex`, `prd.md.eex`, `projection.md.eex`
   (directory listing this session). The three projections are already renderable
   generically via `projection.md.eex` (per-`ProjectionSpec` for-each) and the kernel's
   `render_projection_body("wbpr"/"ard"/"vision", …)` stubs (semantic_jira.ex lines
   745–757); dedicated templates were not observed on the branch at this timestamp.
2. **FOND/HDDL projections** — PARTIAL (candidate stubs only): kernel emits candidate
   PDDL/HDDL stubs with `authority NONE` (semantic_jira.ex lines 777–788; ontology
   extensions `.pddl`/`.hddl`, ontology.ttl lines 239–253). Solver-grade FOND/HDDL
   emission: NOT LANDED at this timestamp.
3. **OCEL binding** — NOT LANDED at pack level: `ocel` appears in the pack only inside
   GALL-004's descriptions ("Observation independently binds actuation to telemetry,
   OCEL, and postcondition evidence", ontology.ttl lines 465, 492); no `ocel` projection
   type exists in `@projection_types`. A repo-level OCEL emitter exists independently
   (`lib/ggen_igniter/telemetry/ocel_emitter.ex`, 255 lines, referenced by
   `lib/ggen_igniter/reactors/reconcile_reactor.ex`); wiring GALL-004's telemetry
   evidence to it was not observed (UNKNOWN / in flight).
4. **`baseSha` git ground truth** — NOT LANDED: admission validates format only
   (`^[0-9a-f]{40}$`, kernel `@sha` + shape pattern); grep for `rev-parse` /
   `System.cmd("git"` across `semantic_jira.ex`, `semantic_jira/shacl.ex`, and the pack
   tests returned no matches this session (exit 1). No artifact compares `sj:baseSha`
   against actual git history.
5. **RFC document** — this file closes the "RFC LOST" checkpoint in the PR body
   (commit recorded in §9).
6. **Merge readiness** — PR #20 remains draft; per ticket
   `docs/jira/v26.9.19/001-pr-20.md`, acceptance is "gh pr list no longer lists #20".
   Not attempted by this session.

## 8. Traceability matrix

| Criterion (ontology) | Artifact | Evidence | Status |
|---|---|---|---|
| `sj:canonical-source` (ontology.ttl 77–79) | `ontology.ttl` canonical graph; graph-edit comment lines 14–16 | Pipeline test graph-hash assertions (test 97–114) | SATISFIED (hosted green at `58460d0`) |
| `sj:deterministic-projection` (81–83) | templates + `render_projection/3`; replay in test 102–105 | Byte-identical second sync inside runs 203/204 | SATISFIED (hosted) |
| `sj:fail-closed-invalid` (85–87) | §3 rejects list; kernel + templates + shapes | Falsifier matrix tests, hosted green | SATISFIED (hosted) |
| SHACL court (`sj:add-qualified-shacl-court` / `sj:shacl-admission-checkpoint`, 101–107) | `shacl.ex` + `work-order.shacl.ttl` + 20-test file (commit `dd6ac93`) | Hosted green at `58460d0`; unsupported constructs fail closed (shacl tests 320/343) | SATISFIED (closed the SJ-001 next-action) |
| ALIVE receipt crown (`sj:exact-head-projection-court`, `sj:graph-receipt-evidence`, 69–75) | `Receipt` + gate 046 + SHACL constraints | Pipeline test graph_hash/file assertions; gate 046 + shapes 63–75 | PARTIAL: graph-bound receipt SATISFIED; an *independent external* exact-head court receipt is not claimed by this document (that promotion step remains unclaimed) |
| 14-way projection family (line 197) | `projection.md.eex` for-each over `ProjectionSpec`s; kernel 14 types | Template + `@projection_types` read this session | PARTIAL: generic path SATISFIED; dedicated wbpr/ard/vision templates + FOND/HDDL solver-grade + OCEL = §7 items 1–3 |
| Receipt-bound replay (`sj:projection-replay`, 303–309) | `replay_check/2`, `sj:replay-evidence` (185–187) | Replay tests hosted green | SATISFIED (kernel/template level) |
| Hand-writing ≤1% with ledger | `HANDWRITTEN.md` + `sj:ledger-unsupported-001` | Both read this session; commit `7676730` | SATISFIED (ledger row admitted with paydown plan) |
| RFC exists in-repo | this file | commit `docs(rfc): re-manufacture semantic-jira RFC from live artifacts` (SHA recorded in the PR #20 body append) | CLOSED by this re-manufacture |
| `baseSha` git ground truth | none found | grep exit 1, §7 item 4 | OPEN |

## 9. Evidence boundary + receipt

- Every claim above traces to an artifact read this session: 25 distinct in-repo files
  (listed by path in §2/§3/§6/§7), 6 `gh api` fetches (PR metadata+body, PR commits,
  issue comments list, comment 5746425067 body, CI runs list, run-201 jobs), 1 fetched
  PR body file. UNKNOWN is marked wherever a
  thing was not observed (run 201's test list; local mix test; sibling in-flight work
  beyond this window; the lost original's content — which is deliberately NOT
  reconstructed).
- This document's own manufacture: written by agent W2-A4 into a fresh clone at
  `/tmp/scj-finish/w2-a4`; commit
  `docs(rfc): re-manufacture semantic-jira RFC from live artifacts`; pushed to
  `feat/semantic-jira-v26.9.19` per the no-force-push collision protocol; the PR body
  gains exactly one appended line recording the commit SHA. No merge, publication,
  deployment, Jira SaaS mutation, or standing promotion is claimed or authorized.


## v26.9.24 closure addendum

The forensic re-manufacture history in section 0 remains part of the record; it no longer means the specification is open.

The v26.9.24 implementation carries the Friday GoalCheckpoint tuple in the canonical RDF/SHACL surface: GoalCheckpoint identity, capability requirement, postcondition, evidence horizon, exclusions, and successor policy. Generated Jira/PRD/ARD/projection artifacts remain consequences of the graph and cannot grant authority.

Specification closure does not self-promote runtime standing. Exact-head courts, receipt identity, and replay remain the promotion mechanism for implementation claims.
