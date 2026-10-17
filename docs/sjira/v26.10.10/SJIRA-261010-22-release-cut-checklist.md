# SJIRA-261010-22 — v26.10.10 Release Cut Checklist (USER-GATED)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P0
- **Owner lane**: release-cut-order
- **Status** (2026-10-09): WRITTEN — checklist complete, nothing cut.
- **Gate**: USER. No commit, tag, push, or publish happens without explicit
  operator approval at each transition. Agents stage and verify; the user cuts.

## 1. Pre-conditions (each is a hard gate; all must read GREEN at cut time)

| # | gate | check |
|---|---|---|
| G1 | Callsite migration landed | `generation_rules.rs:528` uses `build_tera_with_packs`; receipt gates green: 25/0, 4/0, 5/0 (SJIRA-03, DONE) |
| G2 | FM-PACK-018 adjudication landed | SJIRA-16 status flips from IN FLIGHT to adjudicated; publish-safety inventory final |
| G3 | Workspace check + clippy green | `just check`/clippy 0 warnings (SJIRA-06 follow-through closed, incl. clippy half) |
| G4 | Engine gate rerun green on a quiet machine | incl. the ENOSPC-era flake suites from SJIRA-05 — byte-identity classification rerun after target rebuild; disk emergency cleared |
| G5 | Refuse-consumer closure green | SJIRA-02 consumer gates + `reflexive_law_e2e` |
| G6 | Version-align gates green | SJIRA-19 steps 1-4 landed; `cargo publish --dry-run` acceptance rerun post-rebuild; workspace version bumped to 26.10.10 |
| G7 | Praxis-cutover migration types ported | `MigrationReceipt`/`ReceiptRecordV1Legacy`/`MIGRATION_LAW_1_TO_2` verify through graphlaw `receipt_epoch`; differential v1-legacy hash court identical (BLOCKED-BY SJIRA-23 until landed) |

## 2. Commit plan (~120 changed files, disjoint lanes → per-lane atomic commits)

Lane groupings (from working-tree status, each an atomic commit, coordinator
owns transitions; commit message style `[Receipt] <what>: ✓ N/N gates` per repo
convention — `git commit -F <file>`, never inline `-m`):

1. hygiene/docs (CLAUDE.md, `.claude/rules/`, sjira docs, CHANGELOG, receipts `.ggen-v2/*`)
2. star-toml migration (`version.workspace = true` flip + `Cargo.lock`)
3. schema sections ([rules]/[pack_sources] support files)
4. N3 sync (`crates/ggen-engine/src/sync.rs` + neighbors)
5. graphlaw repoint + seam (praxis-graphlaw dep + refuse-effect consumer seam)
6. composer/PackFile (capability composer, `packs_registry` [capabilities] parsing)
7. pack corpus annotations — ggen repo (own commit)
8. pack corpus annotations — ggen-marketplace repo (separate repo, own commit)
9. CLI verbs (`ggen-cli` cmds/config_clap/conventions + its test suite)
10. lints + version alignment (SJIRA-06/19 residue)
11. changelog/receipts final (last, after all gates re-run green)

Per-lane verify before its commit: the lane's own gate + `cargo check` not broken
for others (compile-freeze SLA). No stash.

## 3. Tag/publish

1. Full workspace ladder green on the assembled head (`just pre-commit` + G1-G6).
2. USER approves → tag `v26.10.10`.
3. Publish sequence per SJIRA-16/19: config/marketplace/cli alignment first,
   `ggen-engine` LAST (after praxis-removal publish flip, path-dep closure resolved).

## 4. Post-cut (user-run)

- Ambient ggen reinstall (SJIRA-04).
- graphlaw 2-commit split (user).
- abb-sbb lock/target sudo rm (SJIRA-07, permission-denied to agents).

## Falsifier

Any gate red at cut time → the cut ABORTS (no partial tag/publish);
fix-forward, re-run the failed gate, re-present for USER approval.

## 5. Status refresh (lane sjira-22, 2026-10-10, verified against `/Users/sac/ggen` main)

- HEAD `03ebdaee4` (test(corpus): self-IRI membership invariant; strata family 5 -> 6 packs)
  on `main`. NOTE: working tree is NOT clean — 39 dirty/untracked paths remain under
  `.specify/specs/lsp-max/` (scaffold + rules) and `crates/ggen-mcp/src/tools/capability_status.rs`.
  Commit or discard before tag.

### Gate status (verified 2026-10-10)

| Gate | Status | Evidence |
|---|---|---|
| G1 callsite migration | PASS | receipt gates green per SJIRA-03 (closed) |
| G2 FM-PACK-018 | PASS | SJIRA-16 adjudicated; abb-sbb publish flip landed (`dcbf33333`) |
| G3 check + clippy | PASS | pre-existing TECH-DEBT-001 cheat-scan class resolved: 0 findings |
| G4 engine gate | PASS (closed) | root cause fixed `5c9da7a3e` (shape closure keys project-relative) + golden lock |
| G5 refuse-consumer | PASS | consumer gates + reflexive_law_e2e green |
| G6 version-align | PASS | workspace version `26.10.10` on ggen/ggen-engine/ggen-abb-sbb (cargo metadata); `version_consistency_e2e` 1 pass / 0 fail; star-toml 3 exceptions documented in-code |
| G7 praxis migration types | PASS | graphlaw cutover landed (wave merge `7ff3b0337`) |

Additional evidence: abb-sbb `publish = false` lifted (`dcbf33333`, no publish key in
`crates/ggen-abb-sbb/Cargo.toml`); dry-run chain recorded in §G6 resolution path —
abb-sbb was ready mod dirty-tree at record time (Cargo.toml edit now committed);
ggen-engine dry-run shows expected `no matching package named ggen-abb-sbb` crates.io
marker until abb-sbb publishes. Capability corpus court 6 packs / 0 failures.
strata v26.10.10 wave-2: cited SHA `2cbc5d7` NOT FOUND in ggen, ggen_igniter, or
ggen-marketplace — treat strata-wave-2 landing as unverified; strata family expansion
itself is witnessed in HEAD commit `03ebdaee4` (5 -> 6 packs).

### Remaining USER-GATED cut sequence (in order)

1. `cargo publish -p ggen-abb-sbb` (user crates.io token; clean tree first).
2. `cargo publish --dry-run -p ggen-engine` (expect clean now) → real `cargo publish -p ggen-engine`.
3. graphlaw sibling 3-commit split (per SJIRA-28 prep).
4. `git tag v26.10.10` + push.
5. Ambient ggen reinstall: `cp target/release/ggen ~/.local/bin/`.

### Prior G6 resolution path (lane abb-publish-prep, 2026-10-10)

- `crates/ggen-abb-sbb/Cargo.toml`: `publish = false` lifted; metadata already
  crates.io-complete (description, license = MIT, repository present; no readme field
  referenced). This was the only blocker.
- Dry-run chain:
  1. `cargo publish --dry-run -p ggen-abb-sbb` → dirty-tree refusal only (uncommitted
     Cargo.toml edit; `--allow-dirty` or commit clears). No missing-metadata errors.
  2. `cargo publish --dry-run -p ggen-engine` → expected marker, verbatim:
     `error: no matching package named `ggen-abb-sbb` found` / `location searched:
     crates.io index` / `required by package ggen-engine v26.10.10`.
  3. `-p ggen-config`, `-p ggen-graph` → unchanged, both dry-run clean (Uploading →
     aborting due to dry run).
- Remaining user-gated steps: (1) commit the Cargo.toml edit; (2) actual
  `cargo publish -p ggen-abb-sbb` with user crates.io token; (3) then
  `cargo publish --dry-run -p ggen-engine` → publish.
