# v26.11.13 — ash_a2a end-to-end projection via ggen

Standing: PARTIAL

Goal: from Turtle alone, `ggen sync run --skip-ea-admission` projects an Ash + AshA2A app
that compiles (`--warnings-as-errors`) and passes its generated tests, with no human or LLM step.

## Receipt

- Pack: `ggen-marketplace/packs/ash-a2a-app-pack` (domain, resource, agent, config, mix.exs,
  test_helper, per-agent card test, gates 010/020/030).
- Subject: fresh dir with only `ggen.toml` + `ontology/app.ttl`; ggen 26.11.5.
- Observed: sync exit 0; `mix compile --warnings-as-errors` clean; `mix test` 1 test, 0 failures;
  TTL-only edit adds resource + skill + test; re-sync is a no-op; invalid `consequence` is
  refused by gate 030 (FM-PACK-013) before any file is written.

## Gaps (open)

| id | gap | close condition |
|---|---|---|
| G1 | `mix ggen_igniter.*` cannot drive the pack: one EEx template per call, no `for_each`/frontmatter `.tmpl`/pack gates; deps unfetched in `~/ggen_igniter` | `ggen_igniter.sync --pack` runs a frontmatter pack end to end and its output equals `ggen sync run` byte-for-byte |
| G2 | `--skip-ea-admission` required; no `ea.graph.json` generated | pack emits an admissible `ea.graph.json`, or ggen defaults it for generated-only projects |
| G3 | pack hash change forces `rm ggen.lock` | `ggen sync run --relock` (or igniter `pack.lock`) |
| G4 | dev/test uses `:legacy_compat` (dep compiles `:prod`; `:dev_bypass` compiled out) | pack emits a `:strict` profile with durable stores/keys for prod |
| G5 | pack lacks: `hddl_operator`, authority/hooks, `argument_mapping`, `get?`, destroy accept, relationships, non-ETS data layers, multi-domain agents | each gets an ontology term, template branch, gate, fixture |
| G6 | no mutation court: a template mutation must flip the generated test | shim-court for each template |
| G7 | no gate for unknown `ashType` / duplicate names / agent-without-domain | gates 040+ |
| G8 | generated test only checks the card; no dispatch round-trip | test calls `AshA2A.Dispatcher.dispatch/6` on each read skill |

## Closed this wave

- Actions (read/create/update/destroy+accept), skill `consequence`/`lease_required?`,
  primary-key gate (010), skill-targets-action gate (020), consequence vocabulary gate (030).
