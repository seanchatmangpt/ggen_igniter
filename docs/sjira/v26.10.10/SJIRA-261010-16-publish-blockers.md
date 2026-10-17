# SJIRA-261010-16 — ggen-engine publish=false cutover: blocker inventory

Date: 2026-10-09 · Lane: publish-inventory · Subject: /Users/sac/ggen @ branch spec-integration (uncommitted tree; manifests read as-on-disk)

**Status** (2026-10-09 refresh #6): IN FLIGHT — FM-PACK-018 adjudication is
the open blocker item; release staging done separately (binary staged
26.10.8, smoke healthy, install is USER action — see SJIRA-04).
(2026-10-09 refresh #8): FM-PACK-018 adjudicated H2 (validation
over-refusal); fix landed — `crates/ggen-cli/src/cmds/pack.rs:454-528`
two-tier satisfaction (URN-form = consumer-declaration, non-URN = strict
closure), documented in the capability guide. Tallies converting via
gate-engine-2b. Marketplace capability six-suite 43/0 deterministic; clippy
marketplace src/ clean (123 test-only restriction lints headered; 1 types.rs
doc-comment warning under fix).

## Method

`TMPDIR=/tmp CARGO_TARGET_DIR=/tmp/lanepi-target cargo publish --dry-run -p ggen-engine`
→ refused at the gate: `` `package.publish` must be set to `true` or a non-empty list
`` (exit non-zero, no dependency resolution attempted). Cargo's publish=false gate
precedes blocker enumeration, so per-crate blockers below are from manifest static
analysis on disk (the same failure class dry-run would report once publish flips).
No publish performed. Read-only lane.

**Status** (2026-10-09 refresh #2): FM-PACK-018 adjudication in flight.
Publish-safety note CORRECTED — zero absolute sibling paths; the only
publish blockers are the 4 in-workspace path-only deps (ggen-abb-sbb,
praxis-core, praxis-graphlaw, ggen-marketplace). Refuse-consumer closure
(SJIRA-261010-02) in flight; seam rewire remains the GO-gate critical path.

## Per-crate blocker inventory

### ggen-engine (crates/ggen-engine/Cargo.toml, publish=false at line 23)
Path-only `[dependencies]` (path without `version` → publish-unresolvable), lines 97-105:
1. `ggen-abb-sbb = { path = "../ggen-abb-sbb" }` — line 97
2. `praxis-core = { path = "../praxis-core" }` — line 98 (vendored at crates/praxis-core, NOT ~/praxis — the workspace-root comment "hard absolute paths to sibling repos" is STALE)
3. `praxis-graphlaw = { path = "../praxis-graphlaw" }` — line 99 (vendored at crates/praxis-graphlaw)
4. `ggen-marketplace = { path = "../ggen-marketplace" }` — line 105
OK already: `ggen-config = { path = "..", version = "26.7.4" }` (line 111, path+version).
No other path-only deps in [dependencies]; `graphlaw = { workspace = true }` and all
other deps are registry deps.

### ggen-graph (crates/ggen-graph/Cargo.toml)
NO publish=false; no [dependencies] blockers. Its single path dep
(`ggen-engine = { path = "../ggen-engine" }`, line 49) is a DEV-dependency —
path-only dev-deps are stripped from the packaged manifest (verified per in-file
comment 2026-08-16 via `cargo package -p ggen-graph --no-verify --allow-dirty`).
Transitively clean today. Adding ggen-engine as a real [dependencies] edge remains
blocked until ggen-engine publishes.

### ggen-config (crates/ggen-config/Cargo.toml)
Zero path deps; no publish flag (defaults publishable). No blockers.

### ggen-marketplace (crates/ggen-marketplace/Cargo.toml)
One path dep WITH version: `ggen-config = { path = "../ggen-config", version = "26.7.1" }`
(line 65). Publishable as-is — no blockers. (Note: pins 26.7.1 while ggen-engine/cli pin
26.7.4 — not a publish blocker, flagged as version-skew.)

### ggen-cli (crates/ggen-cli/Cargo.toml) — NOTE: no `ggen-cli-lib` crate exists; the
crate is `ggen-cli` (publish=false at line 55)
Blockers:
1. `[dependencies.ggen-engine] workspace = true` (real, non-dev edge → unresolvable until ggen-engine publishes)
2. `ggen-lsp = { version = "26.7.2", path = "../ggen-lsp", optional = true }` (line 85) — path+version optional edge; resolvable only while ggen-lsp 26.7.2 is on crates.io (workspace-root comment lines 711-718 documents this gap for 26.7.2/26.7.3)

## Removal sequence once praxis retires (Cargo.toml lines to flip)

1. `crates/ggen-engine/Cargo.toml:23` — delete `publish = false`
2. Add `version` to the four path-only deps (they are vendored in-workspace; after
   each gets a crates.io release, add its version): ggen-abb-sbb (97), praxis-core (98),
   praxis-graphlaw (99), ggen-marketplace (105). If praxis-core/praxis-graphlaw are
   retired (not published), they must instead be inlined/removed from ggen-engine
   before publish can resolve.
3. `crates/ggen-cli/Cargo.toml:55` — delete `publish = false` (only after step 2
   succeeds; ggen-cli's ggen-engine edge resolves via registry).
4. ggen-graph / ggen-config / ggen-marketplace need NO manifest flips — their
   publish=false was documented as transitive and none actually carry the flag.
5. Stale-comment cleanup (drift guard): workspace root Cargo.toml lines 680-688
   ("absolute paths to sibling repos") and crates/ggen-graph/Cargo.toml lines 36-38
   — praxis deps are vendored in-workspace, not absolute.

## Falsifier (per-crate, run in order)

```
TMPDIR=/tmp CARGO_TARGET_DIR=/tmp/lanepi-target cargo publish --dry-run -p ggen-engine
cargo publish --dry-run -p ggen-graph
cargo publish --dry-run -p ggen-config
cargo publish --dry-run -p ggen-marketplace
cargo publish --dry-run -p ggen-cli
```
Each must exit 0 with no `error:` line (post-cutover). Today all fail or would fail;
ggen-graph/config/marketplace are expected to already pass (no publish flag, no
blocking path-only deps).

## star-toml single-version check

`grep -A1 'name = "star-toml"' Cargo.lock` → exactly ONE entry, `version = "26.7.3"`.
Single-version constraint holds — no duplicate-version blocker.

## Standing

PARTIAL_ALIVE: gate refusal + manifest analysis witnessed; dependency-resolution
blockers are inferred (publish=false gate prevents cargo from listing them). The
falsifier runs are the receipt for the cutover work order.
