# v26.11.17 — exploration sweep overview

Standing: UNVERIFIED

Twenty read-only exploration lanes (see `LANES.md`) swept the pipeline, packs, docs and CI.
No lane ran `mix`, `cargo` or tests: the container has no Elixir or Rust toolchain, so every
finding is a static read with `file:line` evidence. Lane 11 (gate non-vacuity) had not
reported when this file was written.

## Receipt

- Repo `seanchatmangpt/ggen_igniter`, branch `claude/kind-ptolemy-imv2b6`.
- `which mix elixir` returned nothing; `mix compile --warnings-as-errors` was not run.
- Coordinator spot checks (read, not run): `lib/ggen_igniter/engine.ex:8-18` states the
  multi-engine surface was removed; `test/ggen_igniter_receipt_compensated_test.exs` and
  `test/ggen_igniter_lock_node_restart_pid_reuse_test.exs` do not exist;
  `epoch_freshness.ex:864` is `parse_instant/1`.
- Other per-lane claims are relayed from lane reports and not independently re-read.

## Highest-risk findings

| lane | finding | file |
|---|---|---|
| 08 | Bad or missing `watermark_instant` falls back to unix 0 (fail open) | `08-epoch-law.md` |
| 08 | Zero judged files reports ALIVE; receipt without hash admits any bytes | `08-epoch-law.md` |
| 04 | Actuate has no path containment; inject is non-atomic | `04-actuate.md` |
| 05 | Prune failure still returns `{:ok, receipt}`; partial batch delete | `05-reconcile-manifest.md` |
| 09 | Bad hex key crashes SOVEREIGN gate via `Base.decode16!` | `09-sjira-authority.md` |
| 12 | Four forms bypass the Ash-write hook | `12-ash-integration.md` |
| 01 | `.nq` returns a Dataset but `Query.Oxigraph.run` matches Graph only | `01-ontology-load.md` |
| 03 | Four render engines chosen by entry path; same `.tmpl` can differ | `03-render.md` |

## Doc and contract drift

| lane | drift | file |
|---|---|---|
| 02 | `CLAUDE.md` and `status.md` describe selectable engines; only graphlaw remains | `02-engine-nif-vs-sparql.md` |
| 07 | `sync` always tries the Reactor; docs still call it opt-in | `07-reactor-pipeline.md` |
| 15 | 19 of 40 sampled `status.md` claims stale, missing or contradicted | `15-status-md-verification.md` |
| 19 | Reference pages document removed flags; 11 `semantic_jira.*` tasks undocumented | `19-mix-tasks-cli-ref.md` |
| 16 | ADR 0010 absent from generated README; 93 of 215 relative links broken | `16-docs-adr-drift.md` |
| 13 | Igniter docs say Sourceror edits unused; code uses them | `13-igniter-integration.md` |
| 10 | Five packs absent from `packs.md` and `status.md` | `10-pack-inventory.md` |
| 17 | `Dockerfile.e2e` on Elixir 1.17/OTP 25; no workflow runs `mix e2e` | `17-ci-e2e-toolchain.md` |

## Other lane results

- 06 sync task: stale moduledoc pointers; refusal paths without a located test.
- 14 test audit: CLAUDE.md mock grep gave 3 self-reference hits; 7 bare `assert true` skips.
- 18 native NIF: no dirty-scheduler annotation, no Rust tests in CI.
- 20 carryover: `String.to_atom` sites, stale-lock retry paths, falsifiers F1-F4 still open;
  v26.11.13 G1-G8 unobservable here.

## Next

1. Run `mix compile --warnings-as-errors` and `mix test` on a machine with the toolchain, then
   re-judge each lane's findings (UNVERIFIED to ALIVE/REFUSED with command output).
2. Land lane 11 and add its row to this file.
3. Fix the fail-open epoch fallback and the Actuate containment gap first.
4. Repair `status.md`, `CLAUDE.md` engine and Reactor text via evidence, not edits by memory.
5. Note: several lane tables exceed the 100-character line limit; wrap or accept.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/jira/v26.11.13/00-OVERVIEW.md`
- `docs/status.md`
