# ggen Ecosystem ERRC Backlog

Backfilled via 5 parallel `mcp__plugin_lumen_lumen__semantic_search`-driven
agents across `~/ggen`, `~/ggen-legacy`, `~/ggen-core-v2`,
`~/ggen-marketplace`+`~/ggen-marketplace-bridged-packs`, and
`~/ggen-broker`+`~/ggen-create`+`~/ggen_scratch`. Every finding below is
grounded in a file:line citation the reviewing agent read directly — not
inferred from a summary. Companion to `SKILL.md` in this same directory.

## ELIMINATE

- ~~`~/ggen_scratch` is empty~~ — **done**, removed same session.
- Stale re-published pack version: `ggen-marketplace-bridged-packs/castle-pack.toml:3`
  pins `26.8.15`, but the real source pack
  (`ggen-marketplace/packs/castle-pack/pack.toml:3`) is at `26.8.18+dfcm.1`.
  The whole bridged-packs repo is 151 flat `.toml` stubs with no source —
  either regenerate on sync or delete. **Not fixed** — belongs to a repo
  this session doesn't own; flagged for the marketplace maintainer.

## REDUCE

- Merge-strategy string dispatch duplicates an existing serde impl:
  `ggen-marketplace/src/marketplace/compatibility.rs:855-862` hand-matches
  strategy strings, duplicating `MergeStrategy`'s own serde round-trip
  already tested in `ownership.rs:596-607`.
- Byte-identical duplicated pack tooling across two packs:
  `packs/tcps-core-pack/reference/製品版/tools/lifecycle.py` and
  `packs/tcps-release-pack/reference/tools/lifecycle.py` (confirmed via
  `diff`), same for their `build-receipt.schema.json`. The marketplace
  already has a composition mechanism for this
  (`scripts/qualify_packs.py:315` `copy_composed_packs`).
- Governance-ceremony doc boilerplate ("Required authority analysis /
  Required execution research / Acceptance gates") copy-pasted
  near-verbatim across ≥3 `ggen-legacy` subsystem docs
  (`docs/v26.8.1/50-evidence/51-receipt-schema.md:11-39`,
  `20-engine/27-receipt-stage.md:11-39`,
  `30-graph/38-ontology-imports.md:24-66`).
- `ggen-core-v2` re-derives manifest + pack-lockfile schemas `~/ggen`
  already runs in production (`src/config/mod.rs:113-132`,
  `src/packs/lockfile.rs:11-49`).

## RAISE

- `AppError::extract_fm_code` (`ggen/crates/ggen-engine/src/error.rs:265-280`)
  — dedup done right and documented so it won't regress: replaced a
  second independent `[FM-XXX-NNN]`-parsing copy formerly in
  `ggen-mcp::bridge`; both call sites now point back to this one source.
  Template for future FM-code consumers.
- `ggen-self-pack` (`ggen-marketplace/packs/ggen-self-pack/`) — a
  meta-pack whose own `ontology.ttl` formally describes every pack's
  required shape, with a structural gate that refuses an incomplete pack
  before any write, and templates that render new packs straight from
  that ontology. "Generate, don't hand-write" applied recursively to
  pack creation itself — the strongest reference-template candidate
  found.
- Real, live, byte-identical cross-repo LSP contract:
  `ggen/crates/ggen-lsp/generated/lsp-contract.json` vs
  `ggen-legacy/authority/lsp-contract.json` (14003 bytes, `diff` empty),
  backed by a real 991-line receiver implementation in `ggen-legacy`, not
  a stub. Worth promoting as a pattern: independent-receiver equivalence
  checking across repo pairs.
- `ggen-legacy`'s verifier (`verifiers/verify_ggen_v26_8_3.py:101`) runs
  a real mutation-kill fault-injection suite and downgrades
  `ALIVE`→`BUILD_BROKEN` on any miss — corroborated by an executed
  receipt showing `REPLAY_MATCH` between two independently generated
  reports. Genuine, not self-certification (though not independently
  re-run today by this pass).
- `ggen-broker`'s admission engine (`crates/ggen-broker/src/lib.rs:93-216`)
  — a real parse→policy-validate→state-transition→OCEL-log loop, 3 unit
  tests + 1102 lines of integration tests.
- `ggen-law`'s policy engine (`crates/ggen-law/src/lib.rs:210-331`) — a
  genuine hand-rolled comment-extraction state machine (handles
  `//`/`#`/`--`/block/HTML comments, string/lifetime disambiguation), 8
  unit tests covering real edge cases.
- `ggen-create`'s content-addressed receipt verification
  (`src/ggen_create/integrity.py:72-226`) — real, tamper-tested (byte +
  hash level, symlink rejection).
- `ggen-create` actually shells out to a real `ggen` binary and verifies
  output end-to-end (`src/ggen_create/verify.py:205-229`,
  `scripts/gall_ggen_binary_parity.py:44-100`) — genuine integration
  testing, not a mock.
- `ggen-core-v2`'s stricter lockfile integrity invariants
  (`src/packs/lockfile.rs:131-157`) and chained-receipt design
  (`src/receipt/mod.rs:45-96`) — worth evaluating for promotion into
  `~/ggen` if its own equivalents are weaker (unverified without reading
  `~/ggen`'s side directly).

## CREATE

- No pack lint catches cross-pack duplicate content or runs
  `ggen-self-pack`'s own shape gate against *existing* packs
  (`ggen-marketplace/scripts/marketplace.py:219-260`
  `inspect_marketplace()` only checks marketplace-level structural
  fields). Would have caught the `tcps-*-pack` duplication above.
  Extend `fingerprint_paths()` (`scripts/marketplace.py:157`) to a
  cross-pack check.
- No CI/schedule re-runs the ggen↔ggen-legacy equivalence check — only
  point-in-time manual receipts exist
  (`ggen-legacy/authority/v26.8.3/release-authority.json`).
- `ggen-create`'s end-to-end pipeline is conditional on an external
  `ggen` binary being on PATH/`GGEN_BIN`
  (`scripts/gall_ggen_binary_parity.py:47-52` raises
  `UNSUPPORTED:GGEN_EXECUTABLE_MISSING` when absent) — not guaranteed
  every run.
- `ggen-core-v2` has zero execution logic. Confirmed via
  `grep -rn "oxigraph|tera::|Tera::|fn run|fn execute|fn main" src`
  returning **zero hits**: no SPARQL execution, no Tera rendering, no
  file-write stage, no CLI binary. `PackResolver` only resolves
  already-cached local packs (no HTTP client dependency for
  `Registry`/`GitHub` sources). **Assessment: a partial rewrite stopped
  at the type/schema layer — cannot run `ggen sync` today.**

## Noted, not actioned

- `ggen/crates/bcinr-pddl/src/parse.rs` has 5 TODOs (lines 303, 758-768,
  1300-1328, 1392-1397) self-documented as intentionally-scoped-dead
  pending a grounder that doesn't exist yet — correctly guarded, not a
  defect. Worth a periodic check the trigger condition hasn't quietly
  become true.
- `ggen-broker`'s admission concepts and `ggen-create`'s
  content-addressing concepts sound conceptually adjacent — flagged
  directionally only; not enough evidence gathered this pass to claim
  real duplication.
