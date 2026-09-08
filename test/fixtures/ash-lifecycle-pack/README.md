# ash-lifecycle-pack — hand-render fixture, retained as a pack-SHAPE corpus

This pack HAND-RENDERS Ash resource and domain source text from EEx templates. That pattern
predates the current doctrine and is FORBIDDEN for new work. The pack is retained only because
8 test suites consume its SHAPE, not its Ash output. Read this before changing anything here.

## Standing

`UNSUPPORTED` as an Ash manufacturing path. `ALIVE` as a pack-shape test corpus.

`templates/resource.ex.eex` writes `use Ash.Resource` and `templates/domain.ex.eex` writes
`use Ash.Domain` as literal template text. That is exactly the construct
`.claude/hooks/refuse-handwritten-ash.sh` exists to block, and it is why this directory sits
on that hook's allowlist (`*/test/fixtures/ash-lifecycle-pack/*) exit 0 ;;`, line 99) rather
than passing the guard on its merits.

The current doctrine for any new Ash surface is the composed-generator path: an ontology drives
gates, gates drive ONE composed `Igniter.Mix.Task`, and that task calls the REAL upstream Ash
generators via `Igniter.compose_task/4`. No template renders Ash resource source on that path.
See `test/fixtures/ash_manufacture_pack/` for the pack that does hold that standing.

## What this pack is NOT

It is not evidence that ggen_igniter can manufacture Ash resources. A green run here proves the
pack machinery (discovery, `for_each`, reconciliation, pruning) works. It proves nothing about
Ash correctness, because the "Ash" in the output is template text, never a generator call.

Its rendered output only ever lands in a `System.tmp_dir!()` subdirectory or a throwaway `mix
e2e` scaffold. It is never written into a consumer project, so the forbidden construct it emits
does not escape the test tree.

## Why it is retained

These 8 suites consume the pack as a pack-shape corpus. Each row names a file under `test/`
with the `ggen_igniter_` prefix and the `_test.exs` suffix elided:

| Suite | Shape exercised |
| --- | --- |
| `pack_discovery_matrix` | discovery; pins "6 gates, 2 templates -> ambiguous" |
| `sync_pack_template_stem` | `--pack NAME:STEM` selection in a 2-template pack |
| `sync_inprocess_dispatch` | `for_each` dispatch, dry-run, inject |
| `sync_inprocess_reconcile` | `--on-stale refuse\|prune\|preserve`, in-process |
| `reconciliation_manifest` | reconciliation manifest via real subprocess |
| `manifest_destructive_evolution` | add -> rename -> remove of tracked outputs |
| `destructive_change_agent3` | 9 destructive ontology-evolution shapes |
| `project_config` | project config struct shape |

The 11 `ontology_v*.ttl` files exist to drive those destructive-evolution shapes (rename,
remove, re-associate) against a stable pack, which is the reason a two-template pack with a
multi-domain ontology is worth keeping at all.

## Do not change the file inventory

19 files are tracked in git here. `test/ggen_igniter_pack_discovery_matrix_test.exs` pins the
exact counts: 6 gate queries under `gates/*.rq` and 2 templates under `templates/*.eex`.

Adding or removing a gate or a template breaks those pinned assertions. This README is safe to
add because gate discovery globs `gates/*.rq` (`lib/ggen_igniter/pack.ex:87`) and template
discovery globs `templates/*.eex` and `templates/*.tmpl` (`lib/ggen_igniter/pack.ex:126-127`) —
neither glob reaches a file at the pack root.

## If you need a new Ash surface

Do not add it here. Use the composed-generator path in `test/fixtures/ash_manufacture_pack/`,
which renders one `Igniter.Mix.Task` that composes real upstream Ash generators.

## See also

- `AGENTS.md` — the hand-write refusal doctrine this pack predates and does not satisfy
- `test/fixtures/ash_manufacture_pack/README.md` — the pack that holds the current standing
- `.claude/hooks/refuse-handwritten-ash.sh` — the guard this pack is allowlisted against
  (line 99); its refusal rules are stated in `AGENTS.md` under "What is structurally refused"
- `docs/jira/v26.9.8/08-REVIEW-MANUFACTURE-PATH.md` — cites this pack's 3-property
  `alp:Action` class as the modelling the newer pack regressed from (line 113); it does NOT
  record the hand-render exception, which is why this README exists
