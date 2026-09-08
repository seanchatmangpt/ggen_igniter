# ash_tier_matrix_pack — `sh_after:`/`--allow-sh` harness for the Tier-1 Ash task matrix

## ARCHIVED 2026-09-08 — superseded design, retained for flag provenance only

This pack implemented the `sh_after:`/`--allow-sh` 26-shellout design that the current
architecture supersedes: the manufacture path now renders one composed `Igniter.Mix.Task` that
calls the real upstream Ash generators through `Igniter.compose_task/4`, so no template shells
out to `mix ash.*` per row. It was never executed beyond `--dry-run` — see the closing line of
"Verified so far" below, "Not yet run: any real (non-dry) `mix ash.*` execution" — so it
manufactured no execution evidence; no test in the suite referenced it (`grep -rln
'ash_tier_matrix\|ash_tier_task' test lib native --include='*.ex' --include='*.exs'` printed
nothing); and git never recorded it (`git ls-files test/fixtures/ash_tier_matrix_pack` returned
0 rows immediately before this move, and `git check-ignore` exited 1, so it was never-added
rather than ignored). It is retained for one reason only: the per-row flag-provenance notes in
"Where the pack deviates from ticket 02" and the engine constraints in "Constraints observed in
this engine", each of which cites a real `deps/` file:line against ash 3.33.1, ash_postgres
2.13.1 and igniter 0.8.4.

The `sh_after:`/`--allow-sh` feature itself is neither archived nor dead. It lives in
`lib/ggen_igniter/frontmatter.ex`, `lib/ggen_igniter/shell_hook.ex`,
`lib/ggen_igniter/reactors/reconcile_reactor.ex`, `lib/ggen_igniter/receipt.ex` and
`lib/mix/tasks/ggen_igniter.sync.ex`, and is exercised against the surviving fixtures
`test/fixtures/sh_{after_success,after_fail,before_fail}_template.ex.eex` by
`test/ggen_igniter_sync_sh_hooks_test.exs`. Only this pack — one consumer of that mechanism —
is retired.

Nothing below this section is runnable as written. Every relative path in it
(`../ash_tier_matrix_pack`, `test/fixtures/ash_tier_matrix_pack/...`) names the pack's former
location under `test/fixtures/`, which no longer exists. Read the rest of this file as a record
of what was measured, not as instructions.

## What it did

Implements `docs/jira/v26.9.8/03-SH-AFTER-ALLOW-SH-HARNESS.md` against the row content of
`docs/jira/v26.9.8/02-ASH-TASK-VALIDATION-MATRIX.md`. One `alp:AshTierTask` individual per
Tier-1 row (26), one receipt script per row, one fixed `sh_after:` runner that executes the
real `mix ash.*` / `mix ash_postgres.*` task each receipt renders. Runs from inside
`test/fixtures/book_library/` (ticket 01's real Ash project), never from this repo's root.

## Layout (the `GgenIgniter.Pack` convention `--pack-dir` resolves)

```text
test/fixtures/ash_tier_matrix_pack/
├── ontology.ttl                          # default --ontology (Pack.default_ontology/1)
├── gates/010_ash_tier_task_query.rq      # discovered as query name "ash_tier_task_query"
│                                         # (Pack.discover_queries/1 strips the ^\d+_ prefix)
├── templates/ash_tier_task_receipt.sh.eex # the single template (Pack.discover_template/2)
├── bin/run_pending_receipts.sh           # the fixed sh_after: runner (see below)
├── bin/matrix_run.sh                     # ticket 04 driver: one full run, invoke twice
└── README.md
```

`ontology.ttl` reuses the exact `alp:` prefix IRI of `test/fixtures/ash-lifecycle-pack/ontology.ttl`
(`http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#`), scoped by one new class
`alp:AshTierTask` with properties `alp:moduleName`, `alp:mixTask`, `alp:mixArgs`, `alp:rank`
(`xsd:integer`, ticket 02's dependency order), `alp:destructive` (`xsd:boolean`, rows 22-26),
`alp:idempotencyMechanism` (the real run-2 mechanism with a `deps/` file:line, or `NONE`), and
`alp:specDeviation` (empty when the row equals ticket 02's literal; otherwise what differs and
the `deps/` source line that forces it). All seven are rendered into each receipt's header.

## Where the pack deviates from ticket 02, and why it is recorded instead of hidden

Ticket 02's "Real args" column is not runnable verbatim against the fixture's real deps
(`ash 3.33.1`, `ash_postgres 2.13.1`, `igniter 0.8.4` — `grep -n @version` in
`test/fixtures/book_library/deps/{ash,ash_postgres,igniter}/mix.exs`). Ticket 02 is not
amended by this pack; each row's `alp:specDeviation` carries the exact difference. Summary:

- `--yes` is added to every Igniter-based row (1-11, 17): Igniter's global non-interactive
  switch (`deps/igniter/lib/mix/task.ex:117,189`); `sh_after:` has no TTY.
- `--ignore-if-exists` is passed only where the task's `info/0` reads it: `ash.gen.domain`
  (`ash.gen.domain.ex:36`), `ash.gen.resource` (`:76,103`), `ash.gen.enum` (`:31,52`). Rows
  3, 5, 6, 7, 8 (`base_resource`, `change`, `preparation`, `validation`,
  `custom_expression`) declare no such switch; Igniter parses non-strict
  (`deps/igniter/lib/mix/task.ex:237`) and would silently drop it, and each calls
  `Igniter.Project.Module.create_module` → `Igniter.create_new_file` with `on_exists`
  default `:error` (`deps/igniter/lib/igniter.ex:878,890`). Their
  `alp:idempotencyMechanism` is therefore `NONE` and **run 2 of those rows is expected to
  exit nonzero** — a real ticket 02 defect surfaced by this pack, not papered over by a
  flag the task ignores.
- Row 2: ticket 02's `-r belongs_to:author:Elixir.BookLibrary.Catalog.Author` references a
  resource no row generates (compile would fail); replaced by `-a author:string:public`, i.e.
  ticket 01's Book shape. `--uuid-primary-key` takes a value (`:string`, `ash.gen.resource.ex:65`).
- Rows 10, 17, 24: the real tasks take different positionals than ticket 02 lists
  (`ash.extend` needs an extension; `ash.set.domains` and `ash.tear_down` take none).
- Row 18: `ash.manifest.dump` defaults to stdout, so `--output priv/ash_manifest.json` is
  passed to have a file for def (b)'s `git diff`.
- Row 20: the task is `ash.generate_policy_chart` (singular) and raises without
  `--only`/`--all` (`:45`); row 23: `ash.reset` (no `ash_postgres.reset` file exists);
  row 25: `--force` so `ecto.drop` does not prompt; row 26: `--name` is not in
  `@switches` and `OptionParser.parse!(strict:)` raises (`squash_snapshots.ex:10-16,41`), so
  `--into last`.

## Exact invocation (ticket 03; ticket 04 runs it twice via `bin/matrix_run.sh`)

```bash
cd test/fixtures/book_library && \
mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
  --allow-sh
```

Prerequisites on a fresh clone, before that line or any `--dry-run` form of it: run
`mix deps.get` inside `test/fixtures/book_library/` (its `deps/` is gitignored; Hex network
needed), and have a Rust/`cargo` toolchain on `PATH` — the default `oxigraph` engine is a
Rustler NIF whose `priv/native/*.so` is gitignored at the repo root and gets built by the
fixture's `ggen_igniter` path dep on first compile. Postgres is **not** required for
`--dry-run` or for the negative path (no `Repo` exists at day zero and no `mix ash.*` task
runs); it is required for the real run from row 11 onward. The full step list is in
`docs/jira/v26.9.8/00-OVERVIEW.md`, "Reproducing the dry run and the negative path".

That is ticket 03's invocation verbatim. `bin/matrix_run.sh` wraps it for ticket 04: it `cd`s
into the fixture (path derived from the script's own location, no absolute paths), removes
the `.ash-validation-receipts/` harness dir, prefixes `ELIXIR_ERL_OPTIONS="+S 1"`, runs the
invocation above, then prints `git status --short` / `git diff --stat` for the fixture and the
exit code. Any extra argument is appended to the sync command, so
`sh test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh --dry-run` is the dry-run form.

Everything else is supplied by the pack: `--ontology` defaults to `ontology.ttl`,
`--query ash_tier_task_query=gates/010_ash_tier_task_query.rq` from `gates/`, `--template`
from `templates/` (exactly one file, so no `--template` needed), and `--out` from the
template's own `to:` frontmatter. `--manifest-dir` defaults to the invoking cwd, so the
reconciliation manifest lands at `test/fixtures/book_library/.ggen_igniter/manifest.json`
(gitignored in the fixture) and the reactor's `:verify` step runs
`mix compile --warnings-as-errors` inside the fixture.

Add `--dry-run` to see the 26 planned writes and the planned `sh_after:` line without touching
anything. Omit `--allow-sh` and the run refuses before any actuation (`check_allow_sh!/3`,
`ArgumentError` naming the template and its `sh_after:` line) — this is ticket 03's negative
path.

## How a row becomes a real `mix` run

1. Per row, the template renders `.ash-validation-receipts/<NN>-<module_name>-<mix_task>.sh`
   (`NN` = zero-padded rank, so lexical order == rank order). The body is a receipt of the row
   (all seven ontology properties) plus the executable line `mix <mix_task> <mix_args>`.
2. `sh_after: "sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh"` fires after each
   `:written` receipt, with cwd = the fixture root. The runner takes a `mkdir` lock, then runs
   every `NN-*.sh` that has no `.done` marker, in lexical (rank) order, capturing output to
   `<receipt>.log`, writing `<receipt>.done` on exit 0 or `<receipt>.failed` and exiting
   nonzero on the first failure — which makes the hook raise and the reactor compensate.
3. A receipt whose header says `# destructive: true` (rows 22-26) is executed with cwd = a
   disposable copy of the fixture tree (`mktemp -d`; sources copied, `deps/` and `_build/`
   symlinked, the `{:ggen_igniter, path: "../../.."}` dep rewritten to the absolute repo
   root). The copy's path is kept in `.ash-validation-receipts/.disposable_dir` so rows 22-26
   share one copy in sequence; `matrix_run.sh` deletes it before the next run. This is ticket
   02's "run against a disposable copy of the fixture" (lines 112-114) for the *tree*; the
   Postgres database is named by config and is shared, so rows 23 (`ash.reset`) and 25
   (`ash_postgres.drop --force`) do destroy `book_library_dev`.

## Constraints observed in this engine (real, not assumed)

- `sh_after:` is **not** EEx-rendered per row. `ReconcileReactor.render_target/3` hands
  `frontmatter.sh_after` to `GgenIgniter.ShellHook.run/2` verbatim; only `to:` and the body
  go through `Render.render/2`. That is why the per-row command lives in the receipt body and
  the `sh_after:` line is one fixed runner.
- `:actuate` runs rows through `Task.async_stream/3` with
  `max_concurrency = System.schedulers_online()` (`reconcile_reactor.ex:1747`). Twenty-six
  concurrent `mix ash.*` runs in one project would race on `config.exs`/`_build`.
  `matrix_run.sh` sets `ELIXIR_ERL_OPTIONS="+S 1"` so the VM reports one scheduler, the
  stream degrades to sequential row order, and each hook runs exactly its own newly-written
  receipt. The lock in the runner is defence in depth if that variable is dropped.
- `sh_after:` only fires when the write outcome is `:written` (`reconcile_reactor.ex:2056`).
  On run 2 of ticket 04's protocol the receipts would be byte-identical (`:unchanged`) and no
  task would be re-driven — def (c) would then hold by construction of the harness, not by
  the tasks. `matrix_run.sh` therefore removes `.ash-validation-receipts/` (a gitignored
  harness artifact, not fixture source) before every run, so every row is `:written` again and
  every `mix` task really re-executes. The `.done`/`.failed` markers only serialize receipts
  within one sync run (the hook fires 26 times); they are not a cross-run cache.
- `GgenIgniter.ShellHook` has a 60 s per-hook timeout (`default_timeout_ms/0`). Rows 16
  (`ash.setup`) and 23 (`ash.reset`) compile and migrate; on a cold `_build` they may exceed
  it — warm the fixture (`mix compile`) before the first run.
- `ORDER BY ?rank` is honored by the default `oxigraph` engine numerically (observed order
  `1,2,...,9,10,...,26`, not lexical `1,10,11,...`) even though
  `GgenIgniter.Query.Oxigraph.run/2` returns the bound value as the string `"1"`; the
  template's `String.pad_leading/3` handles that.

## Verified so far (this pack's own evidence; the fixture-side runs belong to ticket 04)

See `docs/jira/v26.9.8/DRY-RUN-RECEIPT.md` for the command transcripts. In short, from inside
`test/fixtures/book_library/`:

- `--allow-sh --dry-run`: exit 0, 26 `planned: write .ash-validation-receipts/NN-...` lines in
  rank order 01..26, each followed by
  `planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh`; a `find`
  snapshot of the fixture is identical before and after.
- Same command without `--allow-sh`: exit 1, zero `planned:` lines, `ArgumentError ...
  refusing to sync -- ../ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex declares
  sh_after: ... Pass --allow-sh ...`.
- Receipt bodies for rows 3 and 22 rendered through the real `GgenIgniter.Ontology.load!/1` →
  `GgenIgniter.Query.Oxigraph.run/2` → `GgenIgniter.Render.render/2` path (26 rows bound).
- `bin/run_pending_receipts.sh` exercised standalone against three fake receipts (one plain,
  two `destructive: true`, the last exiting 3): the plain one ran in the fixture dir, the
  destructive ones ran in one shared disposable copy with symlinked `deps/`/`_build/` and the
  rewritten path dep, the fixture tree was untouched, `01`/`02` got `.done`, `03` got
  `.failed`, exit 3; a second invocation skipped `01`/`02` and retried `03`.

Not yet run: any real (non-dry) `mix ash.*` execution against `test/fixtures/book_library/`
(ticket 04).
