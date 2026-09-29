# CLI Reference

`ggen_igniter` ships its Mix tasks under `lib/mix/tasks/`. The two core
tasks plus the full task inventory:

**Core tasks**

- **`mix ggen_igniter.sync`** — the generator. Loads an RDF/Turtle ontology, runs
  one or more named SPARQL queries against it, renders an EEx template with the
  results, and writes (or evaluates, or injects) the output. See
  `docs/reference/cli/sync.md`.
- **`mix ggen_igniter.doctor`** — the diagnostic. Runs a fixed checklist of real
  environment/project/pack checks (Elixir/OTP version, dependency wiring,
  native NIF build freshness, pack shape, etc.) and can auto-`--fix` a subset
  of them. See `docs/reference/cli/doctor.md`.

**Other shipped tasks** (each is a real `Mix.Task` with a `@shortdoc`; flags
live in each module's `schema:`/moduledoc)

- `mix ggen_igniter.plan` — plan-only counterpart of `sync`.
- `mix ggen_igniter.verify` — fails a pack CLOSED: inverted verify queries
  plus per-gate cardinality contracts.
- `mix ggen_igniter.hand_authored` — hand-authored-ledger accounting
  (documented in CHANGELOG v26.9.18).
- `mix ggen_igniter.rename --from --to [--arity] [--deprecate soft|hard]` — see `docs/reference/cli/rename.md`.
- `mix ggen_igniter.replay` — replays a receipt and reports real drift.
- `mix ggen_igniter.pack.fetch` — marketplace pack fetch
  (`github:`/`hex:` specs).
- `mix ggen_igniter.ocel.seal` — seals an OCEL v2 manufacturing log with the
  run's observed outcome (post-seal it builds an EDS Claim and runs 3 real
  falsifiers over the re-read log).
- `mix ggen_igniter.fortune5_ready`, `mix ggen_igniter.frontier_release_plan`
  (read-only preview), `mix ggen_igniter.install [--with-ash-domain]` (see `docs/reference/cli/install.md`), `mix ggen_igniter.upgrade FROM TO` (`upgrade.md`), `mix ggen_igniter.manifest.dump [--path DIR] [--out FILE]` (`manifest.md`), `mix ggen_igniter.packs [--json]` (`packs-list.md`), `mix ggen_igniter.shacl --data --shapes` (`shacl.md`), `mix ggen_igniter.pack.lock` (`pack-lock.md`); global exit codes in `exit-codes.md`; `sync --check` (exit 4 = drift).
- `mix ggen_igniter.epoch.watermark --epoch LABEL [--base-dir DIR]
  [--glob GLOB] [--restamp REASON]` — stamps the pre-epoch implementation
  identity (path + exact git blob SHA per file) into
  `.ggen_igniter/epoch/<epoch>/watermark.json` at the CalVer epoch boundary;
  re-stamping the same epoch over an UNCHANGED tree is idempotent, over a
  CHANGED tree it is refused unless `--restamp REASON` (exit 0
  stamped/idempotent, 1 refused with typed JSON on stderr, 2 bad
  invocation).
- `mix ggen_igniter.epoch.check --epoch LABEL [--base-dir DIR]
  [--threshold F] [--report PATH]` — the epoch freshness court (the
  WITNESS): judges every implementation-plane file in the tree against the
  watermark and refuses anything carried over from the pre-epoch
  implementation. Detector law: receipts admit; similarity falsifies; blame
  informs. Two-layer law: admission (`semantic_jira.admit_candidates
  --epoch-manifest`) refuses known-illegal plans before they run; this
  check proves the resulting BYTES afterwards — promotion requires both.
  Exit 0 every file ALIVE, 1 any refusal-or-unknown (report JSON printed),
  2 bad invocation. See `docs/reference/cli/epoch.md`.
- `mix ggen_igniter.epoch.explain --epoch LABEL --file PATH [--base-dir
  DIR]` — read-only microscope: one file's full provenance chain
  (attribution evidence, closest pre-epoch match with similarity, informing
  git authorship) and the specific condition that would make it ALIVE;
  always exit 0 on a judged file, even when the verdict inside is a
  REFUSED_* atom (`epoch.check` is the gate whose exit code decides).
- **Semantic Jira suite** — `mix semantic_jira.observe --finding
  --base-work-order --origin-authority IRI [--origin-observation IRI]
  [--ontology PATH] [--repair|--identity|--out]` — `--ontology` is the
  canonical graph SHACL runs over (default: the pack ontology; added
  `33c8e86`); `--origin-authority` is REQUIRED (INVARIANT
  A): a missing flag is the typed refusal `{:missing_origin_authority, _}`
  and an unadmitted origin is `{:origin_not_admitted, _}` — both exit 1, not
  invalid invocation; `...court_map --ontology
  --identity [--out]`, `...descriptor --work-orders --ledger --identity
  --alias --verifier-suite [--provider|--court-map|--authority-graph|--out]`,
  `...frontier --work-orders --ledger [--authority-graph]`, `...reconcile
  --work-orders --ledger --receipt [--authority-graph]` — `--authority-graph
  PATH` (Turtle) is the origin-authority graph an order's `origin_authority`
  must resolve in (typed objective/checkpoint, not prose, one recomputing
  `sj:admissionDigest`; default the canonical semantic-jira-pack ontology);
  an unresolved origin is blocked `origin_not_admitted` (SJ-002 AC-04), an
  unreadable file is exit 2 and an unparseable one exit 1 — and since the G1
  origin trust-root pin law (v26.9.25) an `(iri, sj:admissionDigest)` pair is
  admitted only when pinned by an `sj:AuthorityTrustRoot` node of the canonical
  semantic-jira-pack ontology (SHACL `sj:AuthorityTrustRootShape`), with
  `Authority.require_origin/2` guarding every kernel entry point (lease request,
  execution package, DO intent, promotion, transition, repair, A2A task), the old
  `authority_requirement: "NONE"` bypass removed, and any unpinned pair refused
  `{:authority_not_pinned, iri}` fail-closed (an unreadable trust root pins
  nothing);
  `...admit_candidates --candidates PATH [--authority-graph PATH]
  [--epoch-manifest PATH]` (added `be2750d`, epoch gate extended `7c4fcc0`)
  — judges a JSONL candidates file, one verdict per non-blank line in input
  order; a candidate is admitted only when the kernel
  `admit_work_order/1` passes AND its `origin_authority` resolves to an
  admitted authority in the pinned authority index (prose never admits);
  before either gate, `candidate_bounds/1` refuses a line claiming what only
  receipts confer — `{:refused_candidate, {:literal_standing, s}}` and
  `{:refused_candidate, {:ceiling_exceeds_construct, field, value}}` (a
  ceiling naming an actuation in any token — `DO`, `EXECUTE`, or
  `ACTUAT`/`MERGE`/`PUBLISH`/`DEPLOY`/`PUSH`/`RELEASE`-prefixed; the
  evidence ladder and CONSTRUCT name evidence, not actuation, and pass);
  gate 3, opt-in exactly like git ground truth, judges a candidate carrying
  a nonempty `"epoch"` value via `EpochPlan.check/2` against the stamped
  watermark passed as `--epoch-manifest` —
  `REFUSED_EPOCH_LEGACY_EDIT`,
  `REFUSED_EPOCH_UNATTRIBUTED_IMPLEMENTATION`,
  `REFUSED_EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT`,
  `REFUSED_EPOCH_WATERMARK_UNAVAILABLE` (fail closed) — while a line
  without `"epoch"` behaves byte-identically to a run without the flag; a
  later line repeating an earlier ADMITTED line's `identity`,
  `replay_identity`, or admitted `work_order_digest` is refused
  `{:refused_candidate, {:duplicate, field, first_line}}` — one candidate,
  one admission; exit 0 when every line was judged (a refusal is a verdict,
  not a failure), `2` invalid invocation or unreadable candidates file,
  `1` when the authority index is unavailable (fail closed: nothing is
  admitted);

  unreadable file is exit 2 and an unparseable one exit 1;
  `...prov --ledger [--out]` (PROV-O Turtle export of the standing ledger,
  SHACL-checked; `--out` is the Turtle file; exit 1 on a tampered ledger),
  `...xaas_receipt --bridge --xaas-receipt [--out]`, `...bootstrap --fleet
  --goal [--graphs|--receipts-dir|--ledger|--registry|--checkout|--out|--pack-dir]`,
  `...observe_prose --source --candidates --goal
  [--out-dir|--check|--pack-dir|--admit-goal|--context]` — observation only:
  admits prose propositions (`sj:candidateStanding` "UNKNOWN",
  `sj:authorityClaim` "NONE") and writes zero WorkOrders; the former
  compile_prose delta manufacture (and its `--receipts-dir`) is removed by
  the origin-authority law (ADR-012).

Both core tasks are real `Igniter.Mix.Task` modules (`use Igniter.Mix.Task`), so they
compose with other Igniter tasks and honor Igniter's own `--dry-run`-adjacent
conventions where applicable; `sync`'s own `--dry-run` flag (documented in
`sync.md`) is this project's own guarded-write preview, not Igniter's.

## Status label

Everything in this `docs/reference/cli/` tree is **IMPLEMENTED** — verified
directly against the real moduledocs and schemas in
`lib/mix/tasks/ggen_igniter.sync.ex` and `lib/mix/tasks/ggen_igniter.doctor.ex`.
The flag tables for the two core tasks were last fully re-verified on
2026-08-27 (repo version `26.8.27`); since then `sync` gained
`--verify-base-sha` (documented in `sync.md`'s flag table) and `doctor`
gained check 19 `semantic_jira_pack` (documented in `doctor.md`). The
Semantic Jira suite entry was re-verified against
`lib/mix/tasks/semantic_jira.observe_prose.ex` on 2026-09-24 (repo version
`26.9.24`), when `compile_prose` became the observation-only `observe_prose`
(ADR-012); it was re-verified again against the live moduledocs on
2026-09-27 (HEAD `7c4fcc0`), when `observe` gained `--ontology` (`33c8e86`)
and `semantic_jira.admit_candidates` plus the `ggen_igniter.epoch.*` trio
shipped — the suite entry, the task list above, and
`docs/reference/cli/epoch.md` reflect those signatures.

## Related references

- `docs/reference/cli/sync.md` — every `mix ggen_igniter.sync` flag: ontology/
  query/template/out wiring, `--engine`, `--pack`/`--pack-dir`, `--for-each`,
  `--dry-run`, `--mode`, `--on-stale`, `--unless-exists`/`--skip-if`,
  `--manifest-dir`, `inject: true`.
- `docs/reference/cli/doctor.md` — every `mix ggen_igniter.doctor` flag and its
  17-item checklist, including which checks require `--pack`/`--pack-dir` or
  `--engine qlever`, and what `--fix` actually changes.
- `docs/reference/cli/packs.md` — the `priv/ggen/<pack-name>/` directory
  convention: `--pack NAME`, `--pack-dir DIR`, and `--pack NAME:TEMPLATE` template
  disambiguation.
- `docs/reference/cli/epoch.md` — the `ggen_igniter.epoch.*` epoch-boundary
  suite (watermark / check / explain) and the two-layer epoch law.
- `docs/reference/cli/engines.md` — the three `--engine` values (`oxigraph`,
  `sparql`, `qlever`), the real current default, and the disclosed trade-offs of
  each.

## See also (other agents' docs, outside this tree)

- `docs/reference/reactor/**` (Agent 4) — the opt-in
  `GgenIgniter.Reactors.ReconcileReactor` coordinator (`config :ggen_igniter,
  use_reactor`), which `sync` dispatches to when enabled, within a bounded scope
  (no frontmatter, no `--for-each`) — see `sync.md`'s "Reactor dispatch" section
  for the CLI-visible half of that story.
- `docs/reference/reconciliation/**` (Agent 5) — the reconciliation manifest
  (`--on-stale`) in full depth; `sync.md` covers its CLI surface only.
