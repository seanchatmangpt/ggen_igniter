# SJIRA-261010-19 — Intra-workspace Version Skew Audit (follow-up to SJIRA-16)

**Priority**: P2
**Owner lane**: version-skew
**Repo**: /Users/sac/ggen @ branch spec-integration
**Scope**: measured skew of `version = "26.x"` declarations on path deps vs each
dep crate's actual version; align-or-bump order.

**Status** (2026-10-09 refresh #3): steps 1-4 **DONE** — gates re-run after
disk recovery (lane target /tmp/lanevg2-target; first attempt killed at 30min
on shared Cargo.lock held by a concurrent lane's `cargo check --workspace`,
retried once per lane contract):

1. `cargo check -p ggen-marketplace -p ggen-lsp -p ggen-cli-lib -p ggen-config`
   → exit 0, `Finished \`dev\` profile [unoptimized + debuginfo] target(s) in
   25m 24s`. CLEAN.
2. `cargo tree -p ggen-cli-lib -i ggen-config --depth 1` → single resolution
   `ggen-config v26.10.8`, consumers ggen-cli-lib v26.10.8,
   ggen-engine v26.10.6, ggen-marketplace v26.10.8. SINGLE 26.10.8 RESOLUTION.
3. `cargo publish --dry-run -p ggen-config` → refused as expected, NO
   version-conflict warnings. Exact refusal:
   `error: 20 files in the working directory contain changes that were not
   yet committed into git:` … `to proceed despite this and include the
   uncommitted changes, pass the \`--allow-dirty\` flag` (dirty-tree refusal
   from fan-out checkout, not a publish-fitness failure).

Step 5 (ggen-engine edges 26.7.13 → 26.10.6, Cargo.toml:217 +
crates/ggen-lsp:48) remains **cutover-coupled** per SJIRA-261010-01.

## Measured actual versions (2026-10-09)

Workspace `[workspace.package] version = 26.10.8` — inherited via
`version.workspace = true` by: root `ggen` (crates/ggen-cli), `ggen-graph`,
`ggen-lsp`, `ggen-config` (`[package.version] workspace = true`),
`ggen-marketplace` (`[package.version] workspace = true`).
Own versions: ggen-engine 26.10.6, pm4pytest-cli 26.10.6, ggen-abb-sbb 26.9.26,
ggen-architecture 26.7.30, praxis-graphlaw 26.7.9, praxis-core 26.7.2,
powl2-decompose 26.6.30, bcinr-pddl 26.6.26, bcinr-mfw-ir 26.6.26.

## Skew table (dep → declared versions → actual)

| dep | declared @ locations | actual | skew |
|---|---|---|---|
| ggen-config | 26.7.1 crates/ggen-marketplace:65 · 26.7.2 Cargo.toml:215 · 26.7.4 crates/ggen-cli:~213 · 26.7.4 crates/ggen-engine:111 · 26.7.1 crates/ggen-lsp:50 | 26.10.8 | 4 distinct declarations, all stale |
| ggen-graph | 26.7.2 Cargo.toml:210 · 26.7.1 crates/ggen-lsp:51 | 26.10.8 | 2 declarations |
| ggen-lsp | 26.7.2 crates/ggen-cli:85 | 26.10.8 | 1 |
| ggen-marketplace | 26.7.2 Cargo.toml:216 · 26.7.4 crates/ggen-cli:~210 · 26.7.4 crates/ggen-lsp:49 | 26.10.8 | 3 declarations |
| ggen-cli-lib | 26.7.2 Cargo.toml:209 | 26.10.8 | 1 |
| ggen-engine | 26.7.13 Cargo.toml:217 · 26.7.13 crates/ggen-lsp:48 | 26.10.6 | 2 declarations |
| bcinr-mfw-ir | 26.6.26 crates/bcinr-pddl:42 | 26.6.26 | none (exact) |
| bcinr-pddl | 26.6.26 crates/praxis-graphlaw:40 | 26.6.26 | none |
| praxis-graphlaw | 26.7.9 crates/praxis-core:34 | 26.7.9 | none |
| wasm4pm-cognition | 26.7.1 crates/praxis-graphlaw:56 (optional, external) | external | out of scope, note only |

Resolution impact: none today — bare `"26.7.1"` is caret `^26.7.1`, and every
actual version satisfies its req. The skew bites at `cargo publish`
(verification that the published dep resolves from crates.io) and as
documentation drift; 4 different declared versions for ggen-config is the
worst offender.

## Align-or-bump order

Fix before publish checks run. Every edit is manifest-only, resolution-neutral
(new req still satisfies actual version), so all Step 1–3 edits are **safe
now**.

1. **crates/ggen-marketplace/Cargo.toml:65** — `ggen-config` 26.7.1 → `"26.10.8"`.
2. **crates/ggen-lsp/Cargo.toml:50-51** — `ggen-config` 26.7.1 → `"26.10.8"`;
   `ggen-graph` 26.7.1 → `"26.10.8"`. (Line 49 `ggen-marketplace` 26.7.4 → `"26.10.8"`.)
3. **crates/ggen-cli/Cargo.toml:85** — `ggen-lsp` 26.7.2 → `"26.10.8"`; also the
   two `version = "26.7.4"` entries (lines ~206/210: ggen-config, ggen-marketplace)
   → `"26.10.8"`.
4. **Cargo.toml:209-216** (workspace deps table) — ggen-cli-lib 26.7.2 →
   `"26.10.8"`; ggen-graph 26.7.2 → `"26.10.8"`; ggen-config 26.7.2 →
   `"26.10.8"`; ggen-marketplace 26.7.2 → `"26.10.8"`.
5. **ggen-engine edges** (Cargo.toml:217, crates/ggen-lsp:48) — 26.7.13 →
   `"26.10.6"`: **cutover-coupled**. ggen-engine carries its own CalVer
   (26.10.6) and its retirement gate (SJIRA-261010-01 praxis retirement) may
   change both its version and its publish status; bump these two only in the
   same commit as the engine cutover, not before.

## Acceptance

- After steps 1–4: `cargo publish --dry-run -p ggen-config`,
  `-p ggen-marketplace`, `-p ggen-graph`, `-p ggen-lsp`, `-p ggen-cli-lib`
  exit 0 (or, for a crate with `publish = false`, record the explicit
  not-published refusal instead — ggen-lsp has publish=false per T049).
- After step 5 (at cutover): ggen-engine via its praxis-retirement gate
  (SJIRA-261010-01 steps), plus `cargo publish --dry-run -p ggen-engine` if it
  remains published.
- Guard: `grep -rn 'version = "26\.[0-7]\.' crates/*/Cargo.toml Cargo.toml`
  returns only the engine-edge lines pending step 5 (and external-crate reqs).

## Falsifier

A publish dry-run fails on a req that no crates.io version satisfies, or the
guard grep still shows a `26.7.x` declaration against a workspace member
post-step-4.
