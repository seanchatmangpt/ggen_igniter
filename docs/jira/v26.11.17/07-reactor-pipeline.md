# 07 Reactor Pipeline

Standing: UNVERIFIED

Lane 07 of v26.11.17. Read-only static exploration of the Reactor path
(`GgenIgniter.Reactors.ReconcileReactor`) and how the entry paths reach it. No test, compile
or sync command was run this pass, so every finding below is a static-read observation, not
an executed result. The main outcome: the "opt-in, default false" framing in `CLAUDE.md`,
`mix.exs` and one `docs/status.md` row no longer matches `mix ggen_igniter.sync`, which calls
the Reactor path unconditionally; only the controller path still reads `:use_reactor`. Two
moduledoc/runtime mismatches (`mix compile` flags, a missing test file) and one stale test
comment were also found.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| R-01 | sync ignores `:use_reactor`; tries Reactor always | UNVERIFIED | sync.ex:527-531, :1014 |
| R-02 | Only Controller reads the flag (default false) | UNVERIFIED | controller.ex:170-174 |
| R-03 | Docs disagree on default (status.md 72 vs 121) | UNVERIFIED | status.md:72,121 |
| R-04 | `--verify-cwd` heading says "use_reactor: true" | UNVERIFIED | sync.ex:415 |
| R-05 | Test comment says test config sets flag; none found | UNVERIFIED | cwd_pack_test:78 |
| R-06 | Moduledoc says warnings-as-errors; code: plain | UNVERIFIED | reactor.ex:270, :757 |
| R-07 | Moduledoc names removed step commit_manifest | UNVERIFIED | reactor.ex:294 vs :824 |
| R-08 | Cited test `receipt_compensated_test.exs` is absent | UNVERIFIED | `ls` said No such file |
| R-09 | admit_pending has 5 fail-closed refusals pre-write | UNVERIFIED | reactor.ex:2021-2081 |
| R-10 | Pack and SHACL courts precede queries; plan/1 shares | UNVERIFIED | reactor.ex:483-539 |
| R-11 | undo is real rollback; compensate no-op | UNVERIFIED | reactor.ex:646-708 |
| R-12 | Receipt before manifest (moduledoc claim only) | UNVERIFIED | reactor.ex:60-100 |
| R-13 | Prune after verify (Reactor); after write (inline) | UNVERIFIED | reactor.ex:290-298 |
| R-14 | for-each all-or-nothing in Reactor; inline partial | UNVERIFIED | status.md:89 |
| R-15 | Inline-fallback scope unclear (eval) | UNVERIFIED | sync.ex:536-541; status:86 |
| R-16 | Test-only opts live in production `actuate_one/2` | UNVERIFIED | reactor.ex:300-327 |
| R-17 | Edges tests are :integration, excluded | UNVERIFIED | edges_test:15; helper:144 |
| R-18 | Controller flattens error receipt to reason/standing | UNVERIFIED | controller.ex:195-200 |
| R-19 | `--check` skips verify and failure receipt append | UNVERIFIED | reactor.ex:735, :1008 |
| R-20 | Per-refusal test coverage not grepped | UNVERIFIED | none run |

Details: R-08 also affects failure-recovery.md:102 and adding-a-reactor-step.md:154 (overview.md:195
discloses it). R-12 ordering test exists (finalize_evidence_ordering_test) but was not run. R-05
command: `grep -rn "use_reactor" config mix.exs` printed only `mix.exs:195`. File prefixes:
reactor.ex = lib/ggen_igniter/reactors/reconcile_reactor.ex;
sync.ex = lib/mix/tasks/ggen_igniter.sync.ex;
controller.ex = lib/ggen_igniter/controller.ex; tests under test/.

## Next

1. Run `mix compile --warnings-as-errors` and `mix test`, then `mix test --include integration
   test/ggen_igniter_reactor_edges_test.exs`, and paste real output to promote R-09 to R-14.
2. Decide the single source of truth for "Reactor default" (R-01 to R-04) and align `CLAUDE.md`,
   `mix.exs` comment, `status.md:121`, and the `sync.ex:415` heading.
3. Fix or retarget the stale citations: plain `mix compile` (R-06), `:commit_manifest` (R-07),
   missing test file (R-08), `config/test.exs` comment (R-05).
4. Grep `test/` for each `admit_pending` refusal tag to settle R-20, and write a refusing
   fixture for any uncovered one.
5. Run `sync --for-each` with one invalid row under both paths to measure the R-14 parity gap.
6. Trace whether the controller path should surface the receipt standing (R-18).

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/reference/reactor/overview.md`
- `docs/reference/reactor/compensation.md`
- `docs/architecture/adr/0007-sync-always-attempts-receipts.md`
- `docs/status.md`
