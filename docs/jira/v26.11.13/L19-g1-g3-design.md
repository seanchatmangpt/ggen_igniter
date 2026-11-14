# L19: G1-G3 design and verification

Standing: UNVERIFIED

Nothing below was compiled or run in this lane (no build tools permitted); every claim is
authored code awaiting the coordinator's gates.

## Finding that changes G1's scope

`mix ggen_igniter.sync` already parses frontmatter (`GgenIgniter.Frontmatter.split_template/1`),
honors `to`/`for_each`/`sparql:`/`force`, and fans out `--pack-dir` over multi-template packs.
What it cannot do is render ggen packs: bodies go through `GgenIgniter.Render` (EEx) while pack
bodies are Tera (`{% set %}`, `filter(attribute=,value=)`, `loop.last`, `| default | split`), and
`to:` is Tera too. So G1 reduces to a Tera body/`to` renderer plus pack-level gate semantics.

## Delivered

| file | role |
|---|---|
| `lib/ggen_igniter/pack_frontmatter/tera.ex` | Tera-subset interpreter (whitespace control, set/for/if, filters used by the pack) |
| `lib/ggen_igniter/pack_frontmatter/sync.ex` | ontology union, pack admission, gates (rows = violation, refuse before writes), per-template render, `Actuate.write_file!/3` |
| `lib/mix/tasks/ggen_igniter.pack_sync.ex` | CLI: `--pack-dir --ontology --out --dry-run --check --lock --relock` |
| `test/ggen_igniter/pack_frontmatter/{tera,sync}_test.exs` | unit + golden courts, real engine, no mocks |
| `test/.../fixtures/**`, `test/.../golden/**` | frozen pack core + `ggen sync run` golden of `/tmp/a2a_demo3` (8 files, `*.golden`) |
| pack: `ontology.d/L19-ea.ttl`, `templates/L19_ea_graph.json.tmpl`, `gates/L19_*.rq`, `fixtures/L19-ea.ttl`, `fragments/L19-NOTES.md` | G2 + G3 notes |

## Residual gaps (explicit)

1. `mix ggen_igniter.sync --pack-dir` itself is unchanged; the Tera path is the sibling task
   `ggen_igniter.pack_sync`. To make `sync` dispatch, add in `run_sync/3`:
   `if GgenIgniter.PackFrontmatter.Sync.tera_pack?(opts[:pack_dir]), do: delegate` (same module as above, `Sync.tera_pack?/1`) (edit to an
   existing file; out of this lane's ownership).
2. No reconciliation manifest, receipt, or `--on-stale` on the Tera path (plain atomic writes).
3. Unsupported frontmatter fields refuse loudly (`REFUSED:UNSUPPORTED_FRONTMATTER`), see
   `Sync` moduledoc.
4. Tera subset only; a template using another filter/tag raises `unsupported ...`.
5. Row shape assumption: graphlaw omits or empties unbound OPTIONAL columns (both falsy in
   `Tera`); a different shape (e.g. `nil` values with key present) is also handled.
6. The live-pack golden test (`@tag :live_pack`) compares only the 8 golden files; if another
   lane changes `resource.ex.tmpl` output for the demo ontology it will flag, correctly.
7. G2 emits an admissible-by-structure graph with no candidate SBB/qualification (digests are
   Rust-computed); see the pack's `fragments/L19-NOTES.md`.

## Coordinator verification

```
cd /Users/sac/ggen_igniter
mix compile --warnings-as-errors
mix test test/ggen_igniter/pack_frontmatter
mix test test/ggen_igniter/pack_frontmatter --only live_pack
rm -rf /tmp/pf_out && mix ggen_igniter.pack_sync \
  --pack-dir /Users/sac/ggen-marketplace/packs/ash-a2a-app-pack \
  --ontology /tmp/a2a_demo3/ontology/app.ttl --out /tmp/pf_out
for f in lib/demo/desk.ex lib/demo/note.ex lib/demo/ticket.ex lib/demo/desk_agent.ex \
         test/desk_agent_test.exs test/test_helper.exs config/config.exs mix.exs; do
  cmp /tmp/pf_out/$f /tmp/a2a_demo3/$f; done
mix ggen_igniter.pack_sync --pack-dir <pack> --ontology <app.ttl> --out /tmp/pf_out --check; echo $?   # 0
mix ggen_igniter.pack_sync --pack-dir <pack> --ontology <app.ttl> --out /tmp/pf_out --relock
```

Most likely first failures: (a) `GgenIgniter.PackLock.update/3` return shape (task wraps `:ok`
and `{:ok, _}`); (b) `mix format` on the new files; (c) a Tera edge in a lane-added template
(error names the construct); (d) sparql row value types (booleans/numbers from the engine) are
normalised by `==` but `{{ }}` of a non-scalar raises.
