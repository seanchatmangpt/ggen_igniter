# Dry-run receipt: Tier-1 Ash task matrix harness (tickets 01/02/03)

Date: 2026-09-08 (second pass, after Task D repairs). Repo: `ggen_igniter`, HEAD `1738ad1`
(working tree also carries the untracked `test/fixtures/book_library/`,
`test/fixtures/ash_tier_matrix_pack/`, and `docs/jira/v26.9.8/`; nothing committed, nothing
pushed). Toolchain:

```text
Erlang/OTP 28 [erts-16.2] [source] [64-bit] [smp:16:16] [ds:16:16:10] [async-threads:1] [jit]
Elixir 1.19.5 (compiled with Erlang/OTP 28)
ash 3.33.1 / ash_postgres 2.13.1 / igniter 0.8.4 (test/fixtures/book_library/deps/*/mix.exs @version)
```

Every command below was actually run this session from the directory shown; output is
trimmed to the informative parts except the 26-row preview, which is reproduced in full.
`mix ggen_igniter.sync` was **only ever run with `--dry-run`**. No `mix ash.*` task was
executed. All `$ cd` lines are the session's own transcript; the pack's documented
invocations contain no absolute paths (`grep -rn "/Users/sac" test/fixtures/ash_tier_matrix_pack
test/fixtures/book_library --exclude-dir=deps --exclude-dir=_build` → no matches, exit 1).

## Repairs applied this pass (Task D — each maps to a refuted finding)

1. **Ontology args vs ticket 02 (13/26 rows differed silently).** `ontology.ttl` now
   carries every row's `alp:mixArgs` as close to ticket 02's literal as the real deps allow,
   plus two new properties on every row: `alp:specDeviation` (empty string when the row
   equals the literal; otherwise the exact difference and the `deps/` file:line forcing it)
   and `alp:idempotencyMechanism` (the real run-2 mechanism with file:line, or `NONE`).
   Rows now byte-equal to ticket 02: 12, 13 (`--name add_book_and_author` restored), 14, 15,
   16, 19, 21, 22. Rows 9/10 use ticket 02's `Elixir.AshPostgres.DataLayer` (the task
   resolves any module via `Module.concat`, `ash.extend.ex:168-175`). Every remaining
   deviation is recorded in the row and rendered into its receipt header.
2. **False header claim ("every flag is a real switch").** Rewritten. `--ignore-if-exists`
   is now passed only to `ash.gen.domain`, `ash.gen.resource`, `ash.gen.enum`, whose `info/0`
   reads it. Rows 3, 5, 6, 7, 8 no longer carry it (their tasks declare no schema; Igniter's
   non-strict parse would drop it, `deps/igniter/lib/mix/task.ex:237`), and their
   `alp:idempotencyMechanism` is `NONE ... Run 2 is expected to exit nonzero`
   (`Igniter.create_new_file` `on_exists` default `:error`, `deps/igniter/lib/igniter.ex:878`).
   Row 8's bogus `--args title,isbn` (types expected) is gone.
3. **Run 2 never re-executed tasks; no destructive isolation.** `bin/run_pending_receipts.sh`
   header now states the marker semantics (within-run serialization only, not a cross-run
   cache), and a receipt whose header says `# destructive: true` (rows 22-26, new
   `alp:destructive` property) runs in a disposable `mktemp -d` copy of the fixture tree
   (sources copied, `deps/`/`_build/` symlinked, path dep rewritten to the absolute repo root
   computed at runtime). New `bin/matrix_run.sh` is the ticket 04 harness invocation: it
   removes `.ash-validation-receipts/` (now gitignored in the fixture) before running ticket
   03's exact sync command, so run 2 renders every receipt `:written`, the hook fires, and
   every `mix` task really re-runs. Template now renders all seven properties.
4. **Fixture pre-wired Repo/Application/config (ticket 01 lists none).** Deleted
   `lib/book_library/repo.ex`, `lib/book_library/application.ex`, the `mod:` entry in
   `mix.exs`, `ecto_repos:` in `config/config.exs`, the repo blocks in `config/dev.exs` and
   `config/test.exs`, and the Sandbox line in `test/test_helper.exs`. Row 11
   `ash_postgres.install --yes` is now the real first install (repo defaults to
   `BookLibrary.Repo`, `install.ex:31-33`). The `ggen_igniter` path dep stays, with its
   deviation from ticket 01 documented in `mix.exs`.
5. **Hygiene.** Pack README: hardcoded `/Users/sac/...` invocation removed; stale "mix.exs
   does not yet declare the path dep" paragraph removed; "Exact invocation" is now ticket
   03's line verbatim, with `ELIXIR_ERL_OPTIONS`/`--dry-run` moved to `matrix_run.sh`.
   `erl_crash.dump` is gitignored in the fixture and none exists now
   (`ls erl_crash.dump` → No such file).

Files touched: `test/fixtures/ash_tier_matrix_pack/{ontology.ttl,README.md,gates/010_ash_tier_task_query.rq,templates/ash_tier_task_receipt.sh.eex,bin/run_pending_receipts.sh,bin/matrix_run.sh (new)}`,
`test/fixtures/book_library/{mix.exs,.gitignore,config/config.exs,config/dev.exs,config/test.exs,test/test_helper.exs}`,
deleted `test/fixtures/book_library/lib/book_library/{repo.ex,application.ex}`, and this file.
Nothing under `lib/` of the repo was touched.

## Step 1: day-zero fixture compiles

```text
$ cd test/fixtures/book_library && mix compile --force --warnings-as-errors ; echo "compile exit=$?"
==> ggen_igniter
     ... (5 `warning:` lines, all under ==> ggen_igniter: pack.ex x3, ggen_igniter.doctor.ex,
          engine_registry.ex -- pre-existing in the path dep, none in the fixture)
Generated ggen_igniter app
==> book_library
Compiling 1 file (.ex)
Generated book_library app
compile exit=0
```

`grep -c 'warning:'` on the full log = 5, every one above the `==> book_library` line.

## Step 2: the ticket-03 invocation, `--allow-sh --dry-run`, from inside the fixture

```text
$ cd test/fixtures/book_library
$ mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
    --allow-sh --dry-run ; echo "dry-run exit=$?"
```

Output after the `==> ggen_igniter` dep-compile lines:

```text
==> book_library
planned: write .ash-validation-receipts/01-BookLibrary.Catalog-ash.gen.domain.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/02-BookLibrary.Catalog.Book-ash.gen.resource.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/03-BookLibrary.BaseResource-ash.gen.base_resource.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/04-BookLibrary.Catalog.Book.Genre-ash.gen.enum.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/05-BookLibrary.Catalog.Changes.NormalizeTitle-ash.gen.change.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/06-BookLibrary.Catalog.Preparations.FilterActive-ash.gen.preparation.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/07-BookLibrary.Catalog.Validations.IsbnFormat-ash.gen.validation.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/08-BookLibrary.Catalog.Expressions.FullTitle-ash.gen.custom_expression.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/09-BookLibrary.Catalog.Book-ash.extend.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/10-BookLibrary.Catalog.Book-ash.patch.extend.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/11-BookLibrary.Repo-ash_postgres.install.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/12-BookLibrary.Repo-ash_postgres.create.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/13-BookLibrary.Repo-ash_postgres.generate_migrations.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/14-BookLibrary.Repo-ash_postgres.migrate.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/15-BookLibrary-ash.codegen.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/16-BookLibrary-ash.setup.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/17-BookLibrary.Catalog-ash.set.domains.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/18-BookLibrary-ash.manifest.dump.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/19-BookLibrary.Catalog-ash.generate_resource_diagrams.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/20-BookLibrary-ash.generate_policy_chart.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/21-BookLibrary-ash.generate_livebook.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/22-BookLibrary.Repo-ash_postgres.rollback.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/23-BookLibrary.Repo-ash.reset.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/24-BookLibrary.Catalog.Book-ash.tear_down.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/25-BookLibrary.Repo-ash_postgres.drop.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/26-BookLibrary.Repo-ash_postgres.squash_snapshots.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh

Igniter:

    No proposed content changes!

Notices:

* ggen_igniter: planned: write ... (same 26 lines) ... (engine: oxigraph, 1 query,
  26 total row(s)) -- summary: planned to write 26 (via reactor)

Notices were printed above. Please read them all before continuing!
dry-run exit=0
```

`grep -c '^planned: write'` = 26. Observed row order, extracted from those lines:
`01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26` -- rank
order (`ORDER BY ?rank`, oxigraph engine). The query now also binds `?destructive`,
`?idempotency_mechanism`, `?spec_deviation`; all 26 rows bound (a row missing any of the
seven properties would have been dropped from the join and the count would be < 26).

The driver form was also run once: `sh test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh
--dry-run` → `== matrix_run: pwd=.../test/fixtures/book_library`, the same 26 lines,
`== matrix_run: sync exit=0`, driver exit 0.

## Step 2b: receipt bodies render (rows 3 and 22, real engine path)

`mix run` of a script calling `GgenIgniter.Pack.discover_template/1` →
`GgenIgniter.Frontmatter.split_template/1` → `GgenIgniter.Ontology.load!/1` →
`GgenIgniter.Query.Oxigraph.run/2` (`rows=26`) → `GgenIgniter.Render.render/2` on `to:` and
body. Row 3 rendered (trimmed):

```text
--- to: .ash-validation-receipts/03-BookLibrary.BaseResource-ash.gen.base_resource.sh
# rank:                  3
# mix_task:              ash.gen.base_resource
# mix_args:              Elixir.BookLibrary.BaseResource --yes
# destructive:           false
# idempotency_mechanism: NONE: info/0 is `positional: [:resource]` only (deps/ash/lib/mix/tasks/gen/ash.gen.base_resource.ex:24); create_module -> Igniter.create_new_file on_exists :error (deps/igniter/lib/igniter.ex:878). Run 2 is expected to exit nonzero.
# spec_deviation:        ticket 02 literal `--ignore-if-exists` dropped: ... + --yes.
set -e
mix ash.gen.base_resource Elixir.BookLibrary.BaseResource --yes
```

Row 22 rendered `# destructive: true`, `# spec_deviation: (none -- equals ticket 02's literal
row)`, `mix ash_postgres.rollback -n 1`.

## Step 3: `--dry-run` executed and wrote nothing

`find . -not -path './deps/*' -not -path './_build/*' -type f | sort` snapshot before, after
the dry run, and after the negative run:

```text
$ diff before.txt after1.txt ; echo "diff exit=$?"
diff exit=0
$ diff before.txt after2.txt ; echo "diff exit=$?"
diff exit=0
$ ls -d .ash-validation-receipts
ls: .ash-validation-receipts: No such file or directory
$ ls -la .ggen_igniter          # empty dir left by GgenIgniter.Lock (lib/ggen_igniter/lock.ex:71,92-93,144)
total 0                          # 0 entries, no manifest.json; removed with rmdir afterwards
```

`.ggen_igniter/` and `.ash-validation-receipts/` are now both listed in the fixture's
`.gitignore`. `git status --short --untracked-files=all test/fixtures/book_library` lists
exactly 10 fixture source files (`.formatter.exs`, `.gitignore`, `config/{config,dev,prod,test}.exs`,
`lib/book_library.ex`, `mix.exs`, `mix.lock`, `test/test_helper.exs`) -- `lib/book_library/`
no longer exists. `git diff --stat | wc -l` = 0 in the repo.

## Step 4: negative path -- refused without `--allow-sh`

```text
$ cd test/fixtures/book_library
$ mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
    --dry-run ; echo "negative exit=$?"
** (ArgumentError) ggen_igniter: refusing to sync -- ../ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex declares sh_after: "sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh" in its frontmatter. A sh_before:/sh_after: command runs an arbitrary real shell command that is NOT covered by GgenIgniter.PendingActuation's admission gate (:admit) and NOT tracked by compensation/undo -- a disclosed, intentional limitation (see this module's moduledoc, "## sh_before:/sh_after: shell hooks"). Nothing was actuated this run. Pass --allow-sh to explicitly opt in and run this sync with shell hooks enabled.
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:1166: Mix.Tasks.GgenIgniter.Sync.check_allow_sh!/3
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:787: Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:756: Mix.Tasks.GgenIgniter.Sync.run_sync/3
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:199: Mix.Tasks.GgenIgniter.Sync."run (overridable 1)"/1
negative exit=1
```

`grep -c '^planned:'` on that log = 0; the `==> book_library` line is not reached; the
post-run `find` diff was empty (above) and `.ash-validation-receipts` absent. No
`erl_crash.dump` was produced by either run this pass.

## Step 5: runner exercised standalone (fake receipts, destructive path included)

In a scratch tree shaped `repo/test/fixtures/book_library/{deps,_build,lib,mix.exs}` with
three fake receipts (`01` plain; `02` `# destructive: true`, touches `DESTROYED`; `03`
`# destructive: true`, `exit 3`):

```text
== run_pending_receipts: .ash-validation-receipts/01-a-t.sh
ok-one
<scratch>/repo/test/fixtures/book_library
== run_pending_receipts: .ash-validation-receipts/02-b-t.sh
== run_pending_receipts: disposable fixture copy at <TMPDIR>/book_library_disposable.0gUvDt
== run_pending_receipts: destructive row, cwd=<TMPDIR>/book_library_disposable.0gUvDt
in-copy
lrwxr-xr-x ... _build -> <scratch>/repo/test/fixtures/book_library/_build
lrwxr-xr-x ... deps -> <scratch>/repo/test/fixtures/book_library/deps
x = {:ggen_igniter, path: "<scratch>/repo"}
== run_pending_receipts: .ash-validation-receipts/03-c-t.sh
second
DESTROYED
== run_pending_receipts: .ash-validation-receipts/03-c-t.sh FAILED (exit 3)
runner exit=3
```

Fixture tree afterwards: `_build deps lib mix.exs` (no `DESTROYED`). Markers: `01`/`02`
`.done`, `03` `.failed`. Second invocation ran only `03` again (same exit 3).

## Chicago-style grep (fixture + pack)

```text
$ grep -rn "unittest.mock\|Mock(\|MagicMock\|patch(\|monkeypatch\|Mox\b\|:meck\|meck\." \
    test/fixtures/book_library/lib test/fixtures/book_library/test \
    test/fixtures/book_library/config test/fixtures/ash_tier_matrix_pack
mock grep exit=1            # no matches
```

## Not verified in dry-run mode (honest gap list)

1. That any of the 26 `mix ash.*`/`mix ash_postgres.*` commands actually succeed against
   the fixture -- ticket 04's non-dry two-run protocol, not performed. Expected by reading,
   unconfirmed by running: rows 3, 5, 6, 7, 8 exit nonzero on run 2 (`alp:idempotencyMechanism
   NONE`); `ShellHook`'s 60 s per-hook timeout vs. `ash.setup`/`ash.reset` on a cold
   `_build`; rows 23/25 destroy `book_library_dev` even though the tree is a disposable copy.
2. That `sh_after:` fires 26 times in a real run -- only the runner's standalone behavior
   was exercised with fake receipts; the real reactor-to-runner handoff was not.
3. Idempotency (run 2 zero new files / zero changed lines / no duplicate `config.exs`
   entries) -- ticket 04, not started. `matrix_run.sh` is the invocation it will use.
4. Per-row receipt bodies were rendered for rows 3 and 22 only through the engine path; the
   other 24 were seen only as `planned: write` paths.
5. `book_library_test` / `book_library_dev` databases: not touched this pass (no repo config
   exists at day zero; row 11 creates it).
6. The manifest write path (`.ggen_igniter/manifest.json`) was never exercised; the dir is
   now gitignored in the fixture either way.

## Third-pass reproduction (completeness critic, 2026-09-08, same HEAD `1738ad1`)

Run independently of the passes above, with `deps/`/`_build/` already present (no
`mix deps.get` this pass -- see `00-OVERVIEW.md`'s fresh-clone prerequisites). Trimmed
to the checked signals:

```text
$ cd test/fixtures/book_library && pwd
/<repo>/test/fixtures/book_library
$ ELIXIR_ERL_OPTIONS="+S 1" mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack \
    --for-each ash_tier_task_query --allow-sh --dry-run > dry.log 2>&1 ; echo "dry-run exit=$?"
dry-run exit=0
$ grep -c '^planned: write' dry.log
26
$ grep '^planned: write' dry.log | sed -E 's/.*receipts\/([0-9]+)-.*/\1/' | tr '\n' ' '
01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26
$ ls -d .ash-validation-receipts
ls: .ash-validation-receipts: No such file or directory

$ mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
    --dry-run > neg.log 2>&1 ; echo "negative exit=$?"
negative exit=1
$ grep -c '^planned:' neg.log
0
$ grep -o "ArgumentError) ggen_igniter: refusing to sync -- [^ ]*" neg.log
ArgumentError) ggen_igniter: refusing to sync -- ../ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex
$ grep -n "check_allow_sh" neg.log
126:    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:1166: Mix.Tasks.GgenIgniter.Sync.check_allow_sh!/3

$ cd ../../.. && sh test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh --dry-run > drv.log 2>&1 ; echo "driver exit=$?"
driver exit=0
$ grep -E "^== matrix_run" drv.log
== matrix_run: pwd=/<repo>/test/fixtures/book_library
== matrix_run: sync exit=0
== matrix_run: git status --short (fixture)
== matrix_run: git diff --stat (fixture)
$ grep -c '^planned: write' drv.log
26
```

Same results as Steps 2 and 4 (`.ggen_igniter/` empty dir left behind each time and
`rmdir`'d). Line-number anchors cited across this directory were re-checked against the
working tree: `ggen_igniter.sync.ex` `:236` (`allow_sh: :boolean`), `:709` (help text),
`:787` (`check_allow_sh!` call in `run_via_reactor/3`), `:1161` (def), `:1166` (raise);
`test/ggen_igniter_sync_sh_hooks_test.exs:71` (`System.cmd("mix", args, cd: File.cwd!(), ...)`).
Two citations inside the pack's shell scripts (`04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md:42-59`
for the two-run protocol) are stale -- that section now starts at line 60 after the status
paragraph was inserted above it; the scripts are code and were not edited in this pass.

## See also

- `00-OVERVIEW.md` -- "Reproducing the dry run and the negative path": fresh-clone
  prerequisites (`mix deps.get` in the fixture, Rust/`cargo` for the oxigraph NIF, no Postgres).
- `03-SH-AFTER-ALLOW-SH-HARNESS.md` -- the invocation this receipt executes (dry-run only).
- `04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md` -- the non-dry two-run protocol still owed.
- `test/fixtures/ash_tier_matrix_pack/README.md` -- runner/serialization/deviation rationale.
