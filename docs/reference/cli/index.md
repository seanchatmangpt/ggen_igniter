# CLI Reference

`ggen_igniter` ships two Igniter Mix tasks, both defined under `lib/mix/tasks/`:

- **`mix ggen_igniter.sync`** — the generator. Loads an RDF/Turtle ontology, runs
  one or more named SPARQL queries against it, renders an EEx template with the
  results, and writes (or evaluates, or injects) the output. See
  `docs/reference/cli/sync.md`.
- **`mix ggen_igniter.doctor`** — the diagnostic. Runs a fixed checklist of real
  environment/project/pack checks (Elixir/OTP version, dependency wiring,
  native NIF build freshness, pack shape, etc.) and can auto-`--fix` a subset
  of them. See `docs/reference/cli/doctor.md`.

Both tasks are real `Igniter.Mix.Task` modules (`use Igniter.Mix.Task`), so they
compose with other Igniter tasks and honor Igniter's own `--dry-run`-adjacent
conventions where applicable; `sync`'s own `--dry-run` flag (documented in
`sync.md`) is this project's own guarded-write preview, not Igniter's.

## Status label

Everything in this `docs/reference/cli/` tree is **IMPLEMENTED** — verified
directly against the real moduledocs and schemas in
`lib/mix/tasks/ggen_igniter.sync.ex` and `lib/mix/tasks/ggen_igniter.doctor.ex`
on 2026-08-27 (repo version `26.8.27`, per `mix.exs` and `CHANGELOG.md`'s
topmost `## v26.8.27` heading). No flag described here is planned-but-unshipped;
conversely, every real flag in both tasks' `schema:` is covered.

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
