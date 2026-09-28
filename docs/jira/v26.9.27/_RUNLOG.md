# v26.9.27 run log (append-only, manufactured by calver-ticket-day-pack)

## epoch-003 — boundary watermark runbook, executed in pre-form

- 2026-09-27T14:2xZ | stamp (run 1) | `mix ggen_igniter.epoch.watermark --epoch v26.9.27-pre` | exit 0
  - `epoch watermark: v26.9.27-pre files=104 head=5ac166b6ae62 -> /Users/sac/ggen_igniter/.ggen_igniter/epoch/v26.9.27-pre/watermark.json`
  - stamp identity: HEAD 5ac166b6ae62753d96331c73d8ab3ccac6d0da38, 104 tracked `lib/**/*.ex` blob identities
- 2026-09-27T14:2xZ | stamp (run 2, idempotency witness) | same command | exit 0, identical file count and head — re-stamp over an unchanged tree is a no-op, no `--restamp` demanded
- 2026-09-27T14:3xZ | check | `mix ggen_igniter.epoch.check --epoch v26.9.27-pre --report .ggen_igniter/epoch/v26.9.27-pre/check-report.json` | **exit 1 (designed refusal)**
  - `epoch check: standing=REFUSED admitted_generated=0 admitted_residue=0 refused=110`
  - 110 candidates = 104 stamped pre-epoch files (REFUSED_LEGACY_EDIT) + 6 untracked epoch-machinery files as brand-new unattributed (REFUSED_NO_ATTRIBUTION). The gate refuses its own makers: witnessed.
  - First firing attempt crashed in `ast_features` on `__MODULE__.Sub` alias segments; repaired (epoch_freshness.ex `remote_name/alias_segment`) and re-fired — the crash itself is recorded here per the preserve-evidence law.
- 2026-09-27T14:4xZ | explain | `mix ggen_igniter.epoch.explain --epoch v26.9.27-pre --file lib/ggen_igniter/epoch_freshness.ex` | exit 0 (microscope, read-only)
  - verdict REFUSED_NO_ATTRIBUTION; law: "No post-watermark receipt, no residue ledger row. Every implementation file needs provenance: a ggen receipt, or a HANDWRITTEN.md row dated >= the watermark."

## epoch-001 — falsifier corpus runs

- `mix test test/ggen_igniter_epoch_freshness_test.exs` → 22 tests, 0 failures (every verdict atom witnessed; anti-vacuity pair green)
- `mix test test/ggen_igniter_epoch_admission_test.exs` → 18 tests, 0 failures (no-regression line byte-identical with and without the gate)

## boundary procedure recorded for the real 26.9 → 26.10 transition

1. Land the final v26.9 release head; commit ALL implementation state (the stamp sees tracked files only — untracked pre-epoch files are invisible to the boundary).
2. `mix ggen_igniter.epoch.watermark --epoch v26.10.1` at that head; archive the stamp (evidence-continuity.md: export before any tree wipe).
3. All v26.10.1 construction runs manufacture fresh; `mix ggen_igniter.epoch.check --epoch v26.10.1` must reach exit 0 before promotion; admission gate active via `semantic_jira.admit_candidates --epoch-manifest <watermark.json>`.
