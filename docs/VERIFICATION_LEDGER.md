# VERIFICATION_LEDGER

One row per `defect-round` invocation (step 7 RECEIPT). Append-only.

| round | hypothesis | failing-output | mutant-killed | SHA |
|-------|------------|----------------|---------------|-----|
<!-- example (do not keep): | 1 | EpochWatermark records blob sha per lib file | `1 test, 1 failure: expected sha256 ...` | yes | 1a6e60d6fed9c2adb06a2c097bbc83e8529f007e | -->

## Falsifier register (opened 2026-10-20, lane write-lane)

Open rows — run when the tree is green (`mix compile --warnings-as-errors` exit 0 first).
Each row closes only with real pasted output; a run that cannot refuse is a VACUOUS court.

| id | falsifier (from PRD §7 / RESTART_HANDOFF §4) | status | run-when-green command | close condition |
|----|----------------------------------------------|--------|------------------------|-----------------|
| F1 | reference receipt replays with `\|Δ\|=0`; a mutated artifact that still admits violates F1 | OPEN | `mix ggen_igniter.replay` (against the reference receipt; then shim-court: mutate one artifact byte, replay must REFUSE) | replay exit 0 with zero delta on clean subject AND typed refusal on the mutated subject |
| F2 | post-watermark unattributed edit to `config/**/*.exs` or `priv/repo/migrations/**/*.exs` must refuse (REFUSED_*, exit ≠ 0) | OPEN | `mix ggen_igniter.epoch.check` (post-watermark fixture edit in `config/`), plus `test/ggen_igniter_epoch_config_migrations_test.exs` | REFUSED_* verdict, exit 1; a clean compile of the unattributed edit = F2 violated |
| F3 | `mix ggen_igniter.review_eval.gate` exits 1 with an open blocking finding in `docs/REVIEW_STATE.md` | OPEN | seed an open blocker row in `docs/REVIEW_STATE.md`, then `mix ggen_igniter.review_eval.gate` | exit 1 with open blocker; exit 0 with open blocker = F3 violated |
| F4 | a diff containing a planted secret exits 5 SECURITY_BLOCKED via `mix ggen_igniter.security_review` | OPEN | plant a secret in a scratch diff, `mix ggen_igniter.security_review` (also `test/ggen_igniter_security_gate_test.exs`) | exit 5 + SECURITY_BLOCKED envelope; clean landing of the secret diff = F4 violated |

## F2 measurement seed (lane C18, v26.10.20)

Human implementation-minutes per landed capability is logged starting with
the reference project (this repo, ggen_igniter). Mechanism: optional
`human_minutes` field — integer, emitted only when set (`put_optional/3`,
`lib/ggen_igniter/landing_pipeline.ex` `finish/4`) — on the landing receipt;
declared additively in `priv/schema/receipt.schema.json` (type
`["integer","null"]`, not required). Old-shape receipts rebuild byte-stable:
an unset value emits no key at all, so pre-field receipt hashes are
unchanged. Covered by `test/ggen_igniter_receipt_schema_test.exs`
`describe "human_minutes (lane C18, additive F2 seed)"` (6 tests: schema
declaration, 42/null validate, non-integer refuses, old-shape stability,
real `LandingPipeline.run` emission probe against real git).

## TR register (v26.10.20 testing charter, PRD §9.2 — appended 2026-10-20, lane write-lane)

Standing re-verified on disk 2026-10-20 on `main` (HEAD `1a6e60d`), grep/read only —
no gate run this pass, so no row is ALIVE. Ids match PRD §9.2 exactly (note: a
dispatch note labeled the projection-pack row "TR-05"; on disk that row is TR-03 —
this ledger follows the on-disk charter).

| id | requirement | verification criterion | current standing (re-verified 2026-10-20) | evidence cite | close condition |
|----|-------------|------------------------|-------------------------------------------|---------------|-----------------|
| TR-01 | Full-suite gate clearance: `mix compile --warnings-as-errors && mix test` green | paste real full-suite output; zero failures, zero invalid | ALIVE (v26.11.10 verified 2026-11-10) | `docs/jira/v26.11.10/01-RELEASE-SHORE-UP-AND-COMPILATION.md`; `docs/jira/v26.11.10/evidence/test_run.log` | `mix compile --warnings-as-errors --force` (exit 0, 0 warnings); `mix test` (1,763 passed, 41 properties, 20 doctests, 0 failures, exit 0) |
| TR-02 | Plane A exempt-plane law: epoch courts never refuse on `test/**`, fixtures, receipts | `mix ggen_igniter.epoch.check` exits 0 for fresh unattributed `test/**` edits; a mutation making an exempt path refuse violates the row | OPEN — court code on disk (`epoch_freshness.ex`, `epoch_plan.ex`); not run this pass | `CLAUDE.md` epoch table; `lib/ggen_igniter/epoch_watermark.ex:60` | court run on a seeded exempt-path edit, exit 0, ALIVE-side verdicts only |
| TR-03 | Plane B: `test-suite-projection` pack projects a test suite deterministically | `ggen sync run` replay against a fixed ontology yields byte-identical suite output | SPEC-ADMITTED / OPEN — confirmed absent from `/Users/sac/ggen-marketplace/packs/` (grep for `test-suite` returned zero matches; nearest are `canonical-ash-projection-generator` and other `*projection*` packs, none is the named pack) | `docs/jira/v26.10.20/PRD.md` §9.1 Plane B; packs enumeration 2026-10-20 | **fixed-point byte-identical re-projection**: a second `ggen sync run` in `~/ggen-marketplace` over the fixed ontology reproduces the suite byte-for-byte |
| TR-04 | Convergence critic wired into `mix ggen_igniter.review.convergence` | task passes a critic-backed reviewer producing non-empty findings on a real diff | WIRED (module) / OPEN (CLI integration) — `lib/ggen_igniter/convergence/critic.ex` exists on disk; CLI task still documents a deterministic empty-finding default reviewer (`lib/mix/tasks/ggen_igniter.review.convergence.ex:18-21`) | `lib/ggen_igniter/convergence/critic.ex`; task scope note | task runs the real critic; non-empty findings on a real diff |
| TR-05 | Receipt integrity: sha256-only via `Receipt.compute_receipt_hash/1`; zero non-sha256 hash families in the receipt path | grep `lib/**` for BLAKE3/other hash families = zero matches; schema + round-trip test green | WIRED — confirmed on disk: `hash_entries/1` returns `"sha256:" <> hex_sha256(digest)` (`lib/ggen_igniter/receipt.ex:398-407`); no BLAKE3 token in the receipt path | `lib/ggen_igniter/receipt.ex`; `priv/schema/receipt.schema.json`; `test/ggen_igniter_receipt_schema_test.exs` | zero-match grep stands after any future hash-path edit |
| — | (supplementary, per dispatch) security task halt contract | `security_blocked -> halt(5)` | WIRED — confirmed on disk (`lib/mix/tasks/ggen_igniter.security_review.ex:108`; every real exit path ends in `System.halt/1`, lines 2, 107-108, 187) | same file, comment block lines 1-8 | stands while the exit contract holds; falsified by a clean landing of a secret-bearing diff (see F4) |

Note on the dispatch's `--engine` probe: `test/support/semantic_a2a_manufactured.ex`
contains no `--engine` flag and no "engine" token at all (grep zero matches,
137 lines). Its real `mix ggen_igniter.sync` subprocess (lines 73-89) passes
`--pack/--out/--manifest-dir/--verify-cwd` only, so the engine is whatever the
pack pipeline defaults to (oxigraph NIF per repo config) — the "--engine passes"
claim is UNVERIFIED for this file as written; the flag would have to be added to
the subprocess argv to be exercised there.
