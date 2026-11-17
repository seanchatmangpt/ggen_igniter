# LANES

Standing: UNVERIFIED

Lane index for v26.11.17. Twenty exploration lanes, one owned file each, all under
`docs/jira/v26.11.17/`. The coordinator owns all git transitions and this file.

## Lanes

| lane | owned file | scope |
|---|---|---|
| 01 | `01-ontology-load.md` | `Ontology.load!/1`, Turtle parsing, prefix handling |
| 02 | `02-engine-nif-vs-sparql.md` | `Engine.run/2`, oxigraph NIF vs pure-Elixir sparql divergence |
| 03 | `03-render.md` | `Render.render/2`, EEx templates, Tera subset |
| 04 | `04-actuate.md` | `Actuate.write_file!/3`, inject modes, write safety |
| 05 | `05-reconcile-manifest.md` | `Reconcile.run/1`, manifest, `--on-stale` |
| 06 | `06-sync-task.md` | `Mix.Tasks.GgenIgniter.Sync`, frontmatter, `--for-each` |
| 07 | `07-reactor-pipeline.md` | opt-in Reactor pipeline, admission and compensation |
| 08 | `08-epoch-law.md` | epoch watermark / check / explain, verdict set |
| 09 | `09-sjira-authority.md` | sJira origin authority (SJ-002), semantic_jira admission |
| 10 | `10-pack-inventory.md` | `priv/ggen/<pack>` census: ontology, gates, templates |
| 11 | `11-gate-non-vacuity.md` | `.rq` gates and refusing-fixture coverage |
| 12 | `12-ash-integration.md` | Ash dev+test-only boundary, no handwritten surfaces |
| 13 | `13-igniter-integration.md` | Igniter codemods, AST edits |
| 14 | `14-chicago-test-audit.md` | mock-library grep, test discipline, skips/exclusions |
| 15 | `15-status-md-verification.md` | `docs/status.md` claims vs evidence |
| 16 | `16-docs-adr-drift.md` | docs structure, ADR numbering, glossary drift |
| 17 | `17-ci-e2e-toolchain.md` | CI workflows, `mix e2e`, toolchain pins, Dockerfile.e2e |
| 18 | `18-native-nif.md` | `native/ggen_graph_nif` Rust crate |
| 19 | `19-mix-tasks-cli-ref.md` | every `mix ggen_igniter.*` task vs `docs/reference/cli/` |
| 20 | `20-prior-jira-carryover.md` | open gaps in v26.10.19 through v26.11.16 |

## Rules

- Each lane writes exactly its one owned file; no other file is edited.
- No git state commands (add, commit, stash, checkout, worktree).
- Read-only against `lib/`, `test/`, `native/`, `priv/`, `config/`.
- Every status claim cites `file:line` or a command and its real output.
  Unrun means UNVERIFIED.

## See Also

- `docs/jira/v26.11.13/LANES.md`
- `docs/jira/v26.11.16/migration-plan.md`
