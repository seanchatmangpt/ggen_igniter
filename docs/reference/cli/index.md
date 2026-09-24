# CLI Reference

`ggen_igniter` ships its Mix tasks under `lib/mix/tasks/`. The two core
tasks plus the full task inventory:

**Core tasks**

- **`mix ggen_igniter.sync`** — the generator. Loads an RDF/Turtle ontology, runs
  one or more named SPARQL queries against it, renders an EEx template with the
  results, and writes (or evaluates, or injects) the output. See
  `docs/reference/cli/sync.md`.
- **`mix ggen_igniter.doctor`** — the diagnostic. Runs a fixed checklist of real
  environment/project/pack checks (Elixir/OTP version, dependency wiring,
  native NIF build freshness, pack shape, etc.) and can auto-`--fix` a subset
  of them. See `docs/reference/cli/doctor.md`.

**Other shipped tasks** (each is a real `Mix.Task` with a `@shortdoc`; flags
live in each module's `schema:`/moduledoc)

- `mix ggen_igniter.plan` — plan-only counterpart of `sync`.
- `mix ggen_igniter.verify` — fails a pack CLOSED: inverted verify queries
  plus per-gate cardinality contracts.
- `mix ggen_igniter.hand_authored` — hand-authored-ledger accounting
  (documented in CHANGELOG v26.9.18).
- `mix ggen_igniter.rename --from --to [--arity] [--deprecate soft|hard]`.
- `mix ggen_igniter.replay` — replays a receipt and reports real drift.
- `mix ggen_igniter.pack.fetch` — marketplace pack fetch
  (`github:`/`hex:` specs).
- `mix ggen_igniter.ocel.seal` — seals an OCEL v2 manufacturing log with the
  run's observed outcome (post-seal it builds an EDS Claim and runs 3 real
  falsifiers over the re-read log).
- `mix ggen_igniter.fortune5_ready`, `mix ggen_igniter.frontier_release_plan`
  (read-only preview), `mix ggen_igniter.install`.
- **Semantic Jira suite** — `mix semantic_jira.observe --finding
  --base-work-order [--repair|--identity|--out]`, `...court_map --ontology
  --identity [--out]`, `...descriptor --work-orders --ledger --identity
  --alias --verifier-suite [--provider|--court-map|--out]`, `...frontier
  --work-orders --ledger`, `...reconcile --work-orders --ledger --receipt`,
  `...xaas_receipt --bridge --xaas-receipt [--out]`, `...bootstrap --fleet
  --goal [--graphs|--receipts-dir|--ledger|--registry|--checkout|--out|--pack-dir]`,
  `...compile_prose --source --candidates --goal
  [--receipts-dir|--out-dir|--check|--pack-dir|--admit-goal]`.

Both core tasks are real `Igniter.Mix.Task` modules (`use Igniter.Mix.Task`), so they
compose with other Igniter tasks and honor Igniter's own `--dry-run`-adjacent
conventions where applicable; `sync`'s own `--dry-run` flag (documented in
`sync.md`) is this project's own guarded-write preview, not Igniter's.

## Status label

Everything in this `docs/reference/cli/` tree is **IMPLEMENTED** — verified
directly against the real moduledocs and schemas in
`lib/mix/tasks/ggen_igniter.sync.ex` and `lib/mix/tasks/ggen_igniter.doctor.ex`.
The flag tables for the two core tasks were last fully re-verified on
2026-08-27 (repo version `26.8.27`); since then `sync` gained
`--verify-base-sha` (documented in `sync.md`'s flag table) and `doctor`
gained check 19 `semantic_jira_pack` (documented in `doctor.md`).

## Related references

- `docs/reference/cli/sync.md` — every `mix ggen_igniter.sync` flag: ontology/
  query/template/out wiring, `--engine`, `--pack`/`--pack-dir`, `--for-each`,
  `--dry-run`, `--mode`, `--on-stale`, `--unless-exists`/`--skip-if`,
  `--manifest-dir`, `inject: true`.
- `docs/reference/cli/doctor.md` — every `mix ggen_igniter.doctor` flag and its
  17-item checklist, including which checks require `--pack`/`--pack-dir` or
  `--engine qlever`, and what `--fix` actually changes.
- `docs/reference/cli/packs.md` — the `priv/ggen/<pack-name>/` directory
  convention: `--pack NAME`, `--pack-dir DIR`, and `--pack NAME:TEMPLATE` template
  disambiguation.
- `docs/reference/cli/engines.md` — the three `--engine` values (`oxigraph`,
  `sparql`, `qlever`), the real current default, and the disclosed trade-offs of
  each.

## See also (other agents' docs, outside this tree)

- `docs/reference/reactor/**` (Agent 4) — the opt-in
  `GgenIgniter.Reactors.ReconcileReactor` coordinator (`config :ggen_igniter,
  use_reactor`), which `sync` dispatches to when enabled, within a bounded scope
  (no frontmatter, no `--for-each`) — see `sync.md`'s "Reactor dispatch" section
  for the CLI-visible half of that story.
- `docs/reference/reconciliation/**` (Agent 5) — the reconciliation manifest
  (`--on-stale`) in full depth; `sync.md` covers its CLI surface only.
