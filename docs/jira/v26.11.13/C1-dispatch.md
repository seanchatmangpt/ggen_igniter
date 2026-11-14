# C1: sync dispatch to Tera packs plus receipts

Standing: UNVERIFIED

Authored without build tools; nothing below was compiled or run.

## Changes

| file | change |
|---|---|
| `lib/mix/tasks/ggen_igniter.sync.ex` | `run_sync/3` now checks `tera_pack_dir?/1` (`--pack-dir` set, no `--template`, `Sync.tera_pack?/1`) and delegates to `run_tera_pack/2` (`PackFrontmatter.Sync.run!` with `--ontology`/`--out`/`--dry-run`); old body is `run_sync_eex/3`, unchanged |
| `lib/ggen_igniter/pack_frontmatter/receipt.ex` | new: receipt per `~/.claude/dfcm/receipt.schema.json` v2 to `<out>/.ggen-igniter/receipt-<id16>.json` |
| `test/ggen_igniter/pack_frontmatter/dispatch_test.exs` | new: real subprocess `mix ggen_igniter.sync`, golden bytes, receipt shape, determinism, dry-run |

## Receipt

- identity: pack tree sha256, ontology sha256s, ggen_igniter version; id16 = prefix of
  sha256 of those (file name and `provider_execution_id`); no git SHA claimed.
- authority: CONSTRUCT, grant NONE. consequence: `files_changed` (written only) plus
  per-file sha256/outcome in `provider_ext.ggen_igniter.files`.
- replay: the `mix ggen_igniter.sync ...` command. standing: ALIVE, or PARTIAL_ALIVE when any
  file is `:skipped_exists`.
- Deterministic: no timestamps, sorted keys. Dry-run and `--check` write no receipt.

## Limits

- `--ontology` is a single-valued flag in the sync task schema, so one ontology per run here.
- Tera path takes no `Lock` and no reconciliation manifest (as before).
- Test is tagged `:integration`; include it if the suite excludes that tag.

## Coordinator runs

```
cd /Users/sac/ggen_igniter
mix compile --warnings-as-errors
mix format --check-formatted lib/mix/tasks/ggen_igniter.sync.ex lib/ggen_igniter/pack_frontmatter/receipt.ex test/ggen_igniter/pack_frontmatter/dispatch_test.exs
mix test test/ggen_igniter/pack_frontmatter/dispatch_test.exs --include integration
mix test test/ggen_igniter/pack_frontmatter
```
