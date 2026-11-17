# Prior Jira Carryover (v26.10.19 to v26.11.16)

Standing: UNVERIFIED

Lane 20 read the prior jira docs v26.10.19, v26.10.20, v26.11.10, v26.11.12, v26.11.13 and
v26.11.16, extracted still-open gaps, and checked each against the working tree by file
read, `ls` and `grep` only. Nothing was compiled or run, so no row is ALIVE. v26.10.19
holds only receipts (11 files), no gap list. The v26.11.13 gaps G1-G8 depend on the external
ggen-marketplace pack `ash-a2a-app-pack`, which is absent from this checkout, so they are
UNKNOWN here. The v26.11.12 `String.to_atom` and lock items are still OPEN. Machine-state
items in v26.11.16 (stashes, stray files) are not observable here.

## Findings

| id | source doc | gap | current standing | evidence |
|---|---|---|---|---|
| C01 | v26.11.12 | `String.to_atom` on frontmatter | OPEN | `lib/ggen_igniter/frontmatter.ex:357` still `String.to_atom(s)`; comment at 352-356 justifies it |
| C02 | v26.11.12 | `String.to_atom` on mode | OPEN | `lib/ggen_igniter/schema_dispatch.ex:460` still `String.to_atom()` |
| C03 | v26.11.12 | atom from SPARQL var name | OPEN | `lib/ggen_igniter/reconcile.ex:307,313`; also `reactors/reconcile_reactor.ex:1416` (doc said :1414) |
| C04 | v26.11.12 | atom from descriptor keys | OPEN | `lib/ggen_igniter/semantic_jira/descriptor.ex:110` |
| C05 | v26.11.12 | `to_atom` helpers not replaced by bounded admission | OPEN | `grep String.to_atom lib` also hits `mix/tasks/ggen_igniter.sync.ex:1747-1758`, `refusals.ex:54,72`, `pack_frontmatter/tera.ex:727,730`, `review_eval/corpus.ex:124`, `engine_registry.ex:76`, `refactors/rename_options.ex:56`; no allowlist seen |
| C06 | v26.11.12 | pack lock stale-check TOCTOU | OPEN (code); court UNKNOWN | `lib/ggen_igniter/pack_lock.ex:398-402` stale?, rmdir, re-acquire; `test/ggen_igniter_lock_contention_test.exs` exists, not read or run |
| C07 | v26.11.12 | `lock.ex` stale_lock? break-and-retry | OPEN (code); court UNKNOWN | `lib/ggen_igniter/lock.ex:124-129` break and retry; staleness/heartbeat tests exist, not run |
| C08 | v26.11.12 | git-ignored `doc/` copies drift | UNKNOWN | not examined |
| C09 | v26.11.10 synthesis | `Actuate` line-anchored splice, zipper AST follow-on | OPEN | `lib/ggen_igniter/actuate.ex:24-25` still says "this module's line-anchored text splice" |
| C10 | v26.11.10 synthesis | legacy `lib/generated/` docstring examples in `sync.ex` | OPEN | `lib/mix/tasks/ggen_igniter.sync.ex:45,49,82,96` still use `lib/generated` |
| C11 | v26.11.10 synthesis | unified wrapper for `--phase base`/`core` (planned v26.12) | OPEN | `ls lib/mix/tasks` shows no wrapper task |
| C12 | v26.10.20 ledger | falsifiers F1-F4 OPEN | OPEN (as recorded) | `docs/VERIFICATION_LEDGER.md` F1-F4 rows say OPEN; not run here |
| C13 | v26.10.20 handoff | F1 reference receipt NOT-YET-EXECUTED | OPEN (as recorded) | `v26.10.20/F1_RUNBOOK.md:5` says NOT-YET-EXECUTED; no later receipt found |
| C14 | v26.10.20 handoff | L5 security tests missing (`_receipt_`, `_gate_`) | CLOSED (files) | `test/ggen_igniter_security_{review,receipt,gate}_test.exs` all exist; pass status UNVERIFIED |
| C15 | v26.10.20 handoff | `test/fixtures/review_eval/` missing | CLOSED by design | `test/support/review_eval_fixture.ex` exists |
| C16 | v26.10.20 plan | `docs/status.md` row sourcing audit | UNKNOWN | `docs/status.md` has 301 lines; row-by-row audit not done |
| C17 | v26.11.13 G1 | igniter drives frontmatter pack; manifest, `--on-stale` on Tera path | PARTIAL | `lib/ggen_igniter/pack_frontmatter/sync.ex`, `lib/mix/tasks/ggen_igniter.pack_sync.ex`, `sync.ex:926` delegates via `tera_pack?/1`; manifest/`--on-stale` support unverified |
| C18 | v26.11.13 G2 | `EaAdmission` not wired into sync | UNKNOWN | `lib/ggen_igniter/pack_frontmatter/ea_admission.ex` exists; wiring not traced |
| C19 | v26.11.13 G3 | ggen CLI `sync run --relock` | BLOCKED (external) | igniter-side `ggen_igniter.pack_sync` exists; ggen repo not in checkout |
| C20 | v26.11.13 G4 | strict profile; `config.exs.tmpl` lacks `import_config("prod.exs")` | UNKNOWN | pack not in checkout; repo `config/config.exs:15` imports `#{Mix.env()}.exs` (different file) |
| C21 | v26.11.13 G5-G8 | pack features, mutation courts, gates 040+, dispatch test | UNKNOWN | `priv/ggen/` has no `ash-a2a-app-pack`; lives in external ggen-marketplace |
| C22 | v26.11.13 Next | gate non-vacuity: 106 of 149 gates lack refusing fixture | UNKNOWN | census is in the external pack; see lane 11 for in-repo gates |
| C23 | v26.11.16 | stashes, branches, stray root files, uncommitted jira docs | UNKNOWN | stray `erl_crash.dump`, `.tar`, `neg_*`, `tmp*` absent here; git state commands banned; `?? docs/jira/v26.11.17/` only |

## Next

1. Replace or allowlist the `String.to_atom` sites C01-C05, then re-run the v26.11.12
   check `rg 'String.to_atom' lib`.
2. Run the lock contention and staleness tests (C06, C07) and decide if TOCTOU is covered.
3. Run falsifiers F1-F4 from `docs/VERIFICATION_LEDGER.md` with real output (C12, C13).
4. Decide the Actuate zipper follow-on and the `sync.ex` docstring cleanup (C09, C10).
5. Attach or read `ash-a2a-app-pack` to settle G1-G8 (C17-C22); otherwise mark them external.
6. Run `mix compile --warnings-as-errors` and `mix test` (the gate skill) to move any row
   above UNVERIFIED.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/jira/v26.11.13/02-GAP-REGISTER.md`
- `docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md`
- `docs/VERIFICATION_LEDGER.md`
