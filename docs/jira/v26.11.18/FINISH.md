# FINISH — ggen_igniter (2026-11-18)

Standing: PARTIAL_ALIVE

Docs-honesty lane (10/10). Claims below are re-derived from disk / code,
not copied from earlier README badges.

## Ground truth (re-derived this pass)

| Fact | Value | Source |
|---|---|---|
| Version | `26.11.18` | `mix.exs` `version:` + `source_ref: "v26.11.18"` |
| Ontology packs under `priv/ggen/` | **26** | dirs with `ontology.ttl` |
| Of those with `pack.toml` | **9** | `find priv/ggen -name pack.toml` |
| Non-pack residual | `doctrine-canonical-source/` | contract-only |
| Doctor checks | **19** | `docs/reference/cli/doctor.md` numbered list |
| Refusal codes | **148** + **24** wrapped | `priv/schema/refusals.schema.json` |
| Local Hex tarball | `ggen_igniter-26.11.10.tar` only | repo root |
| Sync spine | CLI → **always** `ReconcileReactor` | `lib/mix/tasks/ggen_igniter.sync.ex` (`run_pipeline!/3` deleted; `mode: eval` included) |
| Controller spine | `Reconcile.run/1` unless `use_reactor: true` | shipped default `false` |

## False / overstated claims corrected this lane

- README verification ladder cited conflicting suite totals (1855 vs 1991)
  and marked `HEX_PACKAGE_ALIVE` / full-suite ALIVE without a 26.11.18
  receipt — softened to UNVERIFIED / false-for-26.11.18.
- README pack table listed 8 packs as if that were the catalog — now
  census + pointer to `docs/reference/cli/packs.md`.
- `docs/reference/cli/packs.md` heading said marketplace fetch was
  "not CLI-wired" while the body documented `mix ggen_igniter.pack.fetch`.
- Docs still saying doctor has **17** checks (`docs/index.md`,
  `getting-started.md`, `dev-setup.md`) — real count is **19**.
- Tutorials / README implying `use_reactor` gates CLI sync — false;
  flag is Controller-only.
- `docs/status.md` refusal count **147** (stale) → **148**; leftover
  "mode: eval → inline fallback" prose after Sync inline deletion.
- CLAUDE.md epoch table still said config/migrations unbound — they are
  in `EpochWatermark.default_globs/0`.

## Still open (operator decisions)

1. **Flip Controller `use_reactor` default to `true`?** Product call —
   in-process consumers would suddenly get receipts/compensation/verify.
2. **Hex publish of v26.11.18?** Runbook at
   `docs/jira/v26.11.10/10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md`;
   not executed. Local evidence still 26.11.10.
3. **Wire `[ontology.aggregate]` into the sync path?** Parse +
   `OntologyAggregate.enforce/3` exist; no call from Sync/Reactor yet
   (CHANGELOG discloses).
4. **Remaining `String.to_atom` sites** (install otp_app, DoctorFixes,
   refusals schema load, tera filter ops, review_eval kind,
   rename_options) — harden vs leave as trusted-input?
5. **Lock TOCTOU** (`pack_lock.ex` / `lock.ex` stale-check then
   rmdir/retry) — still OPEN in
   `docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md`.
6. **Marketplace ash-a2a pack G1–G8** — lives under ggen-marketplace,
   not this repo's finish criterion.
7. ~~**Fresh full-suite gate receipt**~~ **CLOSED 2026-11-18** —
   `mix compile --warnings-as-errors` exit 0; `mix test` →
   **1994 passed**, 5 skipped, 0 failed, exit 0
   (22 doctests, 41 properties, 1931 tests). Cited in README ladder +
   `RECEIPT-finish-slice.md`.

## See also

- `docs/jira/v26.11.18/RECEIPT-finish-slice.md` — code finish slice
- `docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md` — atom / lock backlog
- `docs/status.md` — capability matrix
- `docs/operations/runtime.md` — which pipeline runs where
