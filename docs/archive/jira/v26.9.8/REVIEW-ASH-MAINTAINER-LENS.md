# Adversarial review — Ash/Igniter maintainer lens (v26.9.8)

> **SUPERSEDED TARGET, FINDINGS STILL LIVE.** This review attacks the `sh_after:` +
> `--allow-sh` shell-out design (tickets 02/03/04 and `DRY-RUN-RECEIPT.md`), which no
> longer exists. Its five blockers were the input that produced the redesign, and
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) §"The five blockers,
> resolved" closes each one with an observed execution. Two are worth naming here
> because the review's *direction* was right while its *mechanism* was not:
> B1 (`--ignore-if-exists` on `ash.gen.domain`) is a real CLI-boundary defect and a
> non-defect through `Igniter.compose_task/4`; B5 (`base_resource` ordering) turned
> out to be the `included_all_elixir_files?` latch, which is worse than an ordering
> mistake because it fails silently at exit 0.
>
> The second review, of the design that replaced this one, is
> [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md). One artifact this
> review targets, `test/fixtures/ash_tier_matrix_pack/`, has since been deleted from
> the repo. Retained in full: the `file:line` findings against ash 3.33.1 /
> ash_postgres 2.13.1 / igniter 0.8.4 are real and independently checkable, and a
> refutation record is worth more kept than tidied away.

- **Date:** 2026-09-08
- **Repo / HEAD:** `/Users/sac/ggen_igniter` @ `1738ad1`
- **Deps ground truth (vendored under `test/fixtures/book_library/deps/`):**
  ash 3.33.1, ash_postgres 2.13.1, igniter 0.8.4, spark 2.7.2, ecto 3.14.2
- **Review target:** `docs/jira/v26.9.8/*.md` (esp. 02, 03, 04, DRY-RUN-RECEIPT),
  `test/fixtures/ash_tier_matrix_pack/` (ontology.ttl, gates/, templates/, bin/, README),
  `test/fixtures/book_library/` (mix.exs, config/, lib/, .formatter.exs)
- **Method:** six review lenses (Igniter composition vs shelling out; per-task flag
  correctness and idempotency claims; ash_postgres lifecycle ordering; Spark DSL patching
  and resource shape; what the ontology adds; doc-claim truth against deps) produced raw
  findings; each finding was then adversarially verified against the real dependency
  source with `file:line` citations, and a small number of `--dry-run` / `mix help` /
  `elixir -e` probes run inside `test/fixtures/book_library`. No non-dry `mix ash.*` was
  executed. Findings that did not survive verification are kept in Section 2. Overlapping
  findings from different lenses are merged below; where a lens overstated, the verifier's
  corrected claim is what appears.
- **Persona:** the review lens is "what would the Ash/Igniter maintainer object to" —
  Igniter composition semantics, Spark DSL patching, the ash_postgres snapshot/migration
  lifecycle, and generators being driven in ways that fight the framework. No quotes are
  attributed to any real person.

Paths below are relative to `/Users/sac/ggen_igniter`; `deps/...` means
`test/fixtures/book_library/deps/...`; `pack/...` means `test/fixtures/ash_tier_matrix_pack/...`.

## Section 1 — CONFIRMED findings (ranked)

Summary: 5 blockers, 11 majors, 9 minors after dedup.

### Blockers

#### B1. Row 1 `ash.gen.domain --ignore-if-exists` is rejected by Igniter's strict argv validation; run 1 exits 1 at receipt 01 and the whole matrix halts

- **Claim.** `mix ash.gen.domain Elixir.BookLibrary.Catalog --ignore-if-exists --yes`
  (`pack/ontology.ttl:50`) fails during Igniter's argv validation, before `igniter/1` runs,
  with `--ignore-if-exists : Unknown option` (exit 1). `ash.gen.domain`'s `info/0` declares
  no schema and leaves `extra_args?` at its `false` default, so `validate!` parses `:strict`
  after merging only Igniter's global switches. The flag is honored only when
  `ash.gen.domain` is composed from `ash.gen.resource`, which bypasses CLI validation.
  Because `run_pending_receipts.sh` exits on the first nonzero receipt, no later row
  executes. `ontology.ttl:39-41` and `README.md:39-40` incorrectly list `ash.gen.domain`
  alongside `ash.gen.resource` and `ash.gen.enum`, which are the only two tasks whose
  schemas declare `ignore_if_exists: :boolean`.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex:22-27` (positional only, no
  schema), `:36` (reads `igniter.args.argv_flags`, reachable only post-validation);
  `deps/igniter/lib/mix/task.ex:97-103` (merge global switches, `validate!`);
  `deps/igniter/lib/mix/task/info.ex:77-91` (globals), `:106` (`extra_args?: false`);
  `deps/igniter/lib/igniter/util/info.ex:348-368` (`:strict` unless `extra_args?`);
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:76` and `ash.gen.enum.ex:31` (the two
  tasks that do declare the flag); `ash.gen.resource.ex:185` (composed path with the
  flag); `pack/bin/run_pending_receipts.sh:85-91` (`exit "$status"`). Real probe from
  `test/fixtures/book_library`: `mix ash.gen.domain Elixir.BookLibrary.Catalog
  --ignore-if-exists --yes --dry-run` → `** (Mix) Could not invoke task "ash.gen.domain":
  1 error found! --ignore-if-exists : Unknown option`, exit 1.
- **Why it matters.** The matrix is dead on arrival: the pack's stated premise ("drive the
  real generators unmodified") is falsified at row 1, and the README's competing
  explanation ("Igniter parses non-strict, task.ex:237, and would silently drop it") is
  also wrong — `task.ex:237` runs after the strict `validate!` has already raised.
- **Fix.** Drop `--ignore-if-exists` from Row01 `alp:mixArgs`; set its
  `alp:idempotencyMechanism` to the `create_module -> create_new_file on_exists :error`
  path (see B2 for the real exit code) or drop row 1 and let row 2's
  `ash.gen.resource --domain ... --ignore-if-exists` compose it (`ash.gen.resource.ex:185`).
  Correct `ontology.ttl:39-41`, `README.md:39-43`, `00-OVERVIEW.md:65`, ticket 02 row 1.
  Add a falsifier that runs each Igniter row with `--dry-run` and asserts no `Unknown
  option` before the matrix is driven. Upstream-shaped fix: `schema:
  [ignore_if_exists: :boolean]` in `ash.gen.domain`'s `info/0` (as `ash.gen.enum` does).

#### B2. "Run 2 of rows 3/5/6/7/8 is expected to exit nonzero" is false: an Igniter file-exists issue exits 0, so the harness marks `.done` and defs (c)/(d) pass vacuously

- **Claim.** Rows 3/5/6/7/8 (`ash.gen.base_resource/change/preparation/validation/
  custom_expression`) all go through `Igniter.Project.Module.create_module ->
  Igniter.create_new_file` with default `on_exists: :error`, so a second invocation against
  an existing file adds an Igniter *issue*, not a failure: `do_or_dry_run/2` prints
  `Issues:` to stderr and returns `:issues`, `Igniter.Mix.Task.run/1` returns that atom,
  Mix discards it, and nothing outside the `--check` branch calls `System.halt`. `mix
  ash.gen.<x> ... --yes` therefore exits 0 on run 2 with nothing written. The receipt
  template runs a bare `mix` under `set -e` and the runner writes `.done` on exit 0 without
  inspecting the log, so any run 2 (via ticket 04's manual protocol, or after `.done`
  removal) records exit 0 on both runs — def (d) satisfied vacuously, `Issues:` visible only
  in the `.log`. Note the runner itself skips receipts with `.done`, so the false green
  materialises when the two-run protocol is executed, not on first sync. The
  `specDeviation` rationale for dropping the flag on these rows ("Igniter parses non-strict
  (task.ex:237) and would silently discard it") is also wrong — the flag is rejected loudly
  with exit 1 (see B1).
- **Evidence.** `deps/igniter/lib/igniter/project/module.ex:168-169` (`create_new_file`,
  no opts); `deps/igniter/lib/igniter.ex:878,890,913-915` (`already_exists(..., :error) ->
  add_issue`), `:1163,1279-1281` (`display_issues; :issues`), `:1291-1335` (only `--check`
  halts: 3 on issues, 1 on pending changes, 2 on warnings), `:1918-1925` (stderr only);
  `deps/igniter/lib/mix/task.ex:112-119` (returns `do_or_dry_run` result; only exits are
  arg-parse errors at `:278,:303`); `deps/igniter/lib/mix/task/info.ex:84` (`check` is a
  global switch); `pack/templates/ash_tier_task_receipt.sh.eex:26-28`; `pack/bin/
  run_pending_receipts.sh:76` (skip on `.done`), `:85-91`; ontology claim at
  `pack/ontology.ttl:27,70,88,97,106,115`; `README.md:42-48`; `04:21-25,57`;
  `DRY-RUN-RECEIPT.md:34-37,246-247`; `02:22`. Real probes from `test/fixtures/
  book_library`: `mix ash.gen.change Elixir.BookLibrary --yes --dry-run` (module exists) →
  `Issues: * lib/book_library.ex: File already exists`, exit 0; with `--check` → exit 3;
  `mix ash.gen.base_resource Elixir.BookLibrary.BaseResource --ignore-if-exists --yes
  --dry-run` → `Unknown option`, exit 1.
- **Why it matters.** The idempotency protocol's only signal for these rows is exit code,
  and the exit code cannot distinguish "generator did nothing because it refused" from
  "generator did nothing because it was idempotent". Igniter has a first-class assertion
  for exactly this question (`--check`) and the pack does not use it.
- **Fix.** Append `--check` to every Igniter-based row's run-2 invocation so
  `halt_if_fails_check!/3` yields real exit codes (0 only when already in post-state).
  Independently, have `run_pending_receipts.sh` `grep -q '^Issues:'` each `.log` and treat
  a hit as failure. Rewrite rows 3/5/6/7/8 `alp:idempotencyMechanism` to "`create_new_file
  on_exists :error` -> Igniter Issue `File already exists`, no write, exit 0 without
  `--check`", replace the `task.ex:237` citation with `info.ex:348-368` + exit-1 rejection,
  and amend `README.md:42-48`, `04:21-25`, `DRY-RUN-RECEIPT.md:34-37,246-247`, `02:22`.

#### B3. Row 8 `ash.gen.custom_expression` emits `args:` but `Ash.CustomExpression` requires `arguments:`; the generated module cannot compile and every later compile-first row fails

- **Claim.** In ash 3.33.1 the generator writes `use Ash.CustomExpression, name: ...,
  args: [...]`, but `Ash.CustomExpression.__using__` raises `ArgumentError "You must
  provide arguments for the custom expression"` when `opts[:arguments]` is absent. Row 8
  (rank 8, no `--args`) therefore succeeds on run 1 (its own compile runs before the write)
  but leaves an uncompilable module in `lib/`. Row 9 (`ash.extend`) runs `Mix.Task.run
  ("compile")` first, fails, and the runner aborts the sequence, so rows 10-26 never
  execute on run 1. The mismatch is inside the vendored library; no `alp:mixArgs` value on
  row 8 avoids it.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.custom_expression.ex:42-45`;
  `deps/ash/lib/ash/custom_expression.ex:112-114`; `deps/ash/mix.exs:13` (`3.33.1`);
  compile-first sites: `deps/igniter/lib/mix/task.ex:89-91`, `deps/ash/lib/mix/tasks/
  ash.extend.ex:57`, `ash.codegen.ex:41-42`, `ash.setup.ex:19`, `ash.tear_down.ex:14`,
  `ash.reset.ex:14`, `ash.manifest.dump.ex:29`, `ash.generate_resource_diagrams.ex:34`,
  `ash.generate_policy_chart.ex:32`, `ash.generate_livebook.ex:20`; `pack/ontology.ttl:
  109-116`; `pack/bin/run_pending_receipts.sh:85-91`. Real probe in `test/fixtures/
  book_library`: `mix run --no-deps-check -e 'defmodule TCE do use Ash.CustomExpression,
  name: :x, args: [] end'` → `** (ArgumentError) You must provide arguments for the custom
  expression`, exit 1.
- **Why it matters.** An upstream generator/library mismatch sits in the middle of a
  fail-fast, compile-coupled sequence; the matrix will attribute the failure to row 9.
- **Fix.** Remove Row08 from Tier 1 and record it in 02/05 as a disclosed deferral citing
  `ash.gen.custom_expression.ex:44` vs `custom_expression.ex:113`; or move it to rank 26+
  and mark it destructive so it runs only in the disposable copy. Do not paper over it with
  a post-run `sed`.

#### B4. "Disposable copy" isolates only the tree: rows 22-25 rollback/reset/drop the one shared `book_library_dev`, so run 2 cannot satisfy rows 12/14/16 idempotency claims

- **Claim.** Destructive rows run in a `mktemp` tar copy whose `config/` is copied verbatim
  and whose Repo `database:` — written into the real fixture by row 11 (`ash_postgres.
  install` emits `"#{otp_app}_dev"`; the checked-in `dev.exs` is `import Config` only) —
  names the same Postgres database the non-destructive rows built. Row 22 rolls back one
  migration (using the copy's `priv/repo/migrations`, since `source_repo_priv` falls back
  to `File.cwd!()`), row 23 drops+recreates, row 24 (`ash.tear_down` -> `AshPostgres.
  DataLayer.tear_down/1` -> `ash_postgres.drop`) drops it, row 25 drops again. After run 1
  the database does not exist, so run 2's row 12 performs a real `CREATE DATABASE`, row 14
  applies every migration to an empty `schema_migrations`, and row 16 does both. Ticket
  02's "earlier rows' state is never permanently lost" (`:125-127`), row 12/14/16 run-2
  expectations (`02:106,108,110`; `ontology.ttl:153,171,190`), and ticket 04's "already
  applied" log-pattern exception (`04:89-93`) are unattainable by construction. The harness
  already discloses the shared DB (`run_pending_receipts.sh:30-31`, `ontology.ttl:25`,
  `DRY-RUN-RECEIPT.md:246-248`) but tickets 02/04 were not amended. Additionally, under the
  current runner rows 12/14/16 would likely not execute on run 2 at all, because rows
  3/5/6/7/8 sit earlier (see B2). No real two-run pass has been performed
  (`DRY-RUN-RECEIPT.md:243-255`).
- **Evidence.** `pack/bin/run_pending_receipts.sh:30-31,52-70` (tar incl. `config/`,
  `deps`/`_build` symlinks, only `mix.exs` path literal rewritten at `:66`), `:76-80`;
  `pack/bin/matrix_run.sh:2-4,26-36` (identical 26-row set both runs; no DB isolation);
  `test/fixtures/book_library/config/dev.exs` (= `import Config`); `deps/ash_postgres/lib/
  mix/tasks/ash_postgres.install.ex:244-261`; `deps/ash/lib/mix/tasks/ash.reset.ex:14-17`;
  `deps/ash/lib/mix/tasks/ash.tear_down.ex:16-29`; `deps/ash_postgres/lib/data_layer.ex:
  659-662`; `deps/ash_postgres/lib/mix/tasks/ash_postgres.rollback.ex:103-108`;
  `deps/ash_postgres/lib/mix/helpers.ex:210-215`; `deps/ash_postgres/lib/mix/tasks/
  ash_postgres.create.ex:57-58`.
- **Why it matters.** The two-run protocol is the ticket set's whole evidence model for
  idempotency; for the three database rows it is structurally incapable of producing the
  evidence it names.
- **Fix.** Isolate the database, not just the tree: in `disposable_copy()` also rewrite the
  copy's `config/dev.exs` (`database: "book_library_dev"` -> `"book_library_disposable_$$"`)
  and have `matrix_run.sh` drop that name when it removes the copy; or split the protocol
  (rows 1-21 twice, then 22-26 once against post-run-2 state); or `pg_dump`/restore around
  the destructive group. Then amend `02:125-127`, `ontology.ttl:25`, rows 12/14/16
  mechanism text and `04:89-93` to state what the harness actually guarantees. If not
  isolating, delete the run-2 claims for rows 12/14/16 and the migrate log-pattern exception.

#### B5. Row 3 `ash.gen.base_resource` silently rewrites Book's `use` after row 2 — an undisclosed mid-matrix resource-shape mutation that contradicts ticket 01

- **Claim.** `ash.gen.base_resource` unconditionally runs `Igniter.update_all_elixir_files`
  and replaces the first argument of `use Ash.Resource` with the new base module in every
  source file, and adds `base_resources: [BookLibrary.BaseResource]` to `config.exs`.
  Because row 2 has already created `BookLibrary.Catalog.Book`, row 3 mutates Book
  mid-matrix. This rewrite is disclosed nowhere in the ontology, pack README, or tickets
  01/02/04 (grep for `base_resource|BaseResource|update_all_elixir|rewrite` in those files
  hits only receipt names), and it contradicts `01:89-91` ("Plain Ash.Resource directly ...
  no custom base-resource wrapper"). Ticket 02 row 2's "resource file byte-identical"
  (`02:96`) still holds for the run1-vs-run2 diff (row 2 skips, row 3 errors before
  writing), but the file row 2 produced does not survive run 1 unmodified. Row 3's run-2
  behaviour (exit 0 with an Issue, per B2; the pack believes nonzero) is separately
  disclosed at `README.md:40-48,107-108`.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.base_resource.ex:38-45` (create_module),
  `:47-58` (config `base_resources`), `:59-80` (`update_all_elixir_files` ->
  `move_to_module_using(zipper, Ash.Resource)` -> `Sourceror.Zipper.replace`);
  `deps/igniter/lib/igniter.ex:1112-1121` (globs source folders + `{test,config}`);
  `deps/ash/lib/ash/resource/igniter.ex:87-91` (later rows do see the rewritten `use`);
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:36,155-165` (`--base`, validated against
  config `:base_resources`); `pack/ontology.ttl:64-71`; `01:89-91`; `02:96-97`;
  `lib/ggen_igniter/reactors/reconcile_reactor.ex:2056-2070` (`{:hook_failed, e}` ->
  compensation on runner exit).
- **Why it matters.** The matrix's resource shape changes under it between rows 2 and 4,
  and the ticket set explicitly says it would not. Combined with B2, rows with `NONE`
  idempotency also sit in the middle of a fail-fast runner.
- **Fix.** Either move row 3 ahead of row 2 and pass `--base Elixir.BookLibrary.
  BaseResource` to `ash.gen.resource` so Book is *created* on the base resource instead of
  rewritten; or drop row 3 from Tier 1 per ticket 01. In either case give `NONE`-idempotency
  rows (3/5/6/7/8) an explicit expected-run-2 marker the runner honours, or move them after
  the destructive tail.

### Majors

#### M1. Rows 9/10 are inverted relative to the framework's install flow: `ash.extend` writes `repo BookLibrary.Repo` two rows before row 11 creates that Repo; it compiles only because Spark's `{:behaviour, Ecto.Repo}` check is atom-only

- **Claim.** `mix ash.extend Book AshPostgres.DataLayer` (row 9) invokes
  `AshPostgres.DataLayer.install/5`, which writes `postgres do table "books"; repo
  BookLibrary.Repo end` with the repo name derived from the mix.exs module prefix; it never
  creates a Repo, Application child, or `ecto_repos` config — those come only from
  `ash_postgres.install` (row 11). The fixture was explicitly stripped of any Repo
  (`DRY-RUN-RECEIPT.md:48-53`). Nothing in ash_postgres rejects the dangling atom at
  compile time: the `repo` option is validated by Spark as `is_atom/1` without
  `Code.ensure_loaded`, and no ash_postgres verifier dereferences the repo. Whether the
  fixture actually compiles between rows 9 and 11 is UNVERIFIED (no run); the permissive
  mechanism is confirmed. The installer's own pipeline (repo, config, Application child,
  `prepend_to_section_order`, then `codegen "initialize"`) assumes it precedes resources
  referencing the repo; the documented order is `mix igniter.install ash_postgres` first,
  then `ash.gen.resource ... --extend postgres`. The 9-10-before-11 order is copied
  faithfully from ticket 02 (`:122-127`), whose own "dependency-first" label its row order
  contradicts.
- **Evidence.** `deps/ash_postgres/lib/data_layer.ex:4550-4575` (install/5),
  `:298-303` (repo type), `:438-445` (verifiers, none touch repo; `grep -rn repo
  deps/ash_postgres/lib/verifiers/` → doc string only); `deps/spark/lib/spark/options/
  options.ex:1497-1505`; `deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:27-60,
  396-441`; `deps/ash/lib/mix/tasks/ash.extend.ex:57,167-181`; `deps/ash/lib/mix/tasks/
  gen/ash.gen.resource.ex:6-16,194-208`; `deps/ash_postgres/documentation/tutorials/
  get-started-with-ash-postgres.md:20`; `pack/ontology.ttl:56-62,119-145`; `02:103-105,
  122-127`.
- **Why it matters.** Driving the extension before the installer is the direct cause of
  M2 (row 11 performing the initial codegen) and leaves a phantom-repo state that only
  survives thanks to lax validation.
- **Fix.** Reorder so `ash_postgres.install` runs right after `ash.gen.domain` and before
  `ash.gen.resource`; give row 2 `--extend Elixir.AshPostgres.DataLayer` (composes
  `ash.extend`). Keep a standalone `ash.extend` row only to test extend-after-the-fact, and
  then pass the same `--repo` to both tasks so the two defaults (`data_layer.ex:4563` vs
  `install.ex:33`) cannot diverge. Record in `alp:specDeviation` that ticket 02's order was
  framework-hostile.

#### M2. Row 11 `ash_postgres.install` queues `mix ash.codegen initialize`, so the first migration and snapshots land at row 11; rows 13 and 15 emit nothing on run 1 and row 11 re-runs `deps.get` + codegen on every run

- **Claim.** The installer's `igniter/1` ends unconditionally with `Ash.Igniter.codegen
  ("initialize")` -> `Igniter.add_task("ash.codegen", ["initialize"])`. Igniter enters its
  write branch whenever tasks are nonempty, runs `mix deps.get` (unless the first task is
  deps.get), then shells `mix ash.codegen initialize`, which forwards `--name initialize`
  to `AshPostgres.DataLayer.codegen/1` = `ash_postgres.generate_migrations`. Because row 9
  already gave Book a postgres table/repo, run 1 of row 11 is expected (by source reading;
  no run yet) to write `priv/repo/migrations/*_initialize.exs` and `priv/resource_snapshots/`.
  Rows 13 (`--name add_book_and_author`) and 15 (`ash.codegen --name book_library_v1`)
  then hit "No changes detected, so no migrations or snapshots have been created." on run 1
  as well as run 2, so their run-2 evidence is indistinguishable from run 1 and the
  snapshot-comparison mechanism ticket 04 assigns to row 13 (`04:77-88`) is first exercised
  at row 11. If the child codegen exits nonzero, Igniter only logs "Task failed" — row 11's
  captured stdout is required to know which case occurred. Neither `ontology.ttl:144`
  (row 11 mechanism) nor row 13/15 text nor `02:107,109` records any of this; the nested
  compile+codegen also runs inside row 11's 60 s ShellHook budget. `add_book_and_author`
  is also false to its contents — no Author resource exists.
- **Evidence.** `deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:59-60`;
  `deps/ash/lib/ash/igniter.ex:10-33`; `deps/igniter/lib/igniter.ex:1207-1225,1229-1238,
  1257,2178-2205`; `deps/ash/lib/mix/tasks/ash.codegen.ex:44-76`; `deps/ash_postgres/lib/
  data_layer.ex:637-640,4551-4573`; `deps/ash_postgres/lib/migration_generator/
  migration_generator.ex:29-40,90-94,226-235` (`grep -n initialize` there: no
  special-casing); `pack/ontology.ttl:138-146,156-166,173-181`; `02:105-109`; `04:67-88`;
  `ls test/fixtures/book_library/priv` → absent.
- **Why it matters.** The matrix attributes the first migration to the wrong row, ticket 04's
  named evidence for row 13 is vacuous, and row 11 has a hidden `deps.get` + nested compile
  side effect on both runs.
- **Fix.** Either reorder per M1 so `ash_postgres.install` runs against zero postgres
  resources (documented no-op codegen) and row 13 becomes the real first generation; or
  keep the order and record in Row11 that it produces `*_initialize.exs` + snapshots and
  re-runs `deps.get`, change row 13/15's run-1 expectation to "no changes", rename
  `--name add_book_and_author` to something true (`--name books`), and make row 11's
  receipt assert the presence of the initialize migration. Raise the ShellHook timeout for
  row 11 (see m8).

#### M3. Row 25 `ash_postgres.drop` "second run exits nonzero" is false (ecto.drop treats already-dropped as success), row 24 has already dropped the DB before row 25 runs, and the `--force` rationale is wrong

- **Claim.** `ash_postgres.drop` delegates to `ecto.drop`, whose `drop_database/2` handles
  `{:error, :already_down}` (the Postgres adapter's mapping of `invalid_catalog_name`) with
  `Mix.shell().info("... has already been dropped")` and a normal return — exit 0. Row 24
  `ash.tear_down` == `AshPostgres.DataLayer.tear_down/1` == `ash_postgres.drop`, and the
  runner executes receipts in numeric order against a shared DB, so row 25's *first* run
  is already the already-dropped path; no run of row 25 in this ordering exercises a real
  `DROP DATABASE`. Ticket 02 row 25 ("nonzero exit, DB-does-not-exist error surfaced",
  `:119`) and `ontology.ttl:273` are unsatisfiable — doubly so because the receipt is
  `set -e; mix ...` and the runner aborts on any nonzero exit. `--force` is harmless but
  its stated justification ("without it ecto.drop asks for confirmation") is wrong:
  `ecto.drop` prompts only when `start_permanent` is true, and the fixture sets it only
  for `:prod`. Ticket 02 row 12's mechanism text (`:106`) is also self-contradictory
  ("fails loud if DB exists; task treats already exists as success") — `ontology.ttl:153`
  has it right.
- **Evidence.** `deps/ecto/lib/mix/tasks/ecto.drop.ex:65-80,94-102`; `deps/ecto_sql/lib/
  ecto/adapters/postgres.ex:276-277`; `deps/ash_postgres/lib/mix/tasks/ash_postgres.
  drop.ex:50-66`; `deps/ash_postgres/lib/repo.ex:194`; `deps/ash_postgres/lib/data_layer.
  ex:659-662`; `deps/ash/lib/mix/tasks/ash.tear_down.ex:12-30`; `test/fixtures/
  book_library/mix.exs:10`; `02:106,118-119`; `pack/ontology.ttl:258-274`;
  `pack/README.md:58`; `pack/bin/run_pending_receipts.sh:73,85-89`; `pack/templates/
  ash_tier_task_receipt.sh.eex:26-28`; `DRY-RUN-RECEIPT.md:117-118`.
- **Why it matters.** The one "expected loud failure" in the destructive group cannot occur,
  and the group contains two identical drops with the second validating nothing.
- **Fix.** Reword row 25 as "idempotent: `already_down` reported, exit 0" and verify by the
  log line or a state check (`psql -lqt`, or a following `ash_postgres.create` printing
  "has been created"). Either drop row 24 or move row 25 ahead of it so exactly one real
  drop occurs per lifecycle. Rewrite the `--force` specDeviation as defensive-only. Fix
  `02:106` to match `ontology.ttl:153`.

#### M4. Ticket 02 misdescribes what `ash.setup`, `ash.codegen`, `ash.reset` and `ash.tear_down` compose; row 16 adds no discriminating evidence and row 15 is a byte-for-byte replay of row 13

- **Claim.** `ash.setup` = compile + each extension's `setup/1`; `AshPostgres.setup/1` =
  `ash_postgres.create` + `ash_postgres.migrate` (+ `--tenants` rerun) — no installer
  (row 16 says "install + create + migrate", composes row 11; `ontology.ttl:190` already
  says only 12/14, so the markdown and ontology disagree). `ash.codegen` only calls
  `extension.codegen/1`; the only `codegen/1` in the deps tree is
  `AshPostgres.DataLayer.codegen/1` = `ash_postgres.generate_migrations`, so row 15 with
  `--name book_library_v1` reaches the same OptionParser and `MigrationGenerator.generate`
  as row 13 (two extra info lines aside); no diagrams (row 15 says "resource diagrams +
  Postgres migrations"; diagrams are `ash.generate_resource_diagrams`). A second migration
  named `book_library_v1` appears iff resources drifted between rows 13 and 15 — i.e.
  exactly when the harness is broken. `ash.reset` = compile + `ash.tear_down` +
  `ash.setup`; `ash.tear_down` = `extension.tear_down/1` = `ash_postgres.drop` on the dev
  DB, not "remove scaffolding for a resource" (row 24; the ontology already records this).
  Extensions are discovered via `extensions!/1` without `in_use?`, i.e. every deps_tree app
  depending on `:spark`/`:ash`, including the `ggen_igniter` path dep. Because rows 12/14
  precede 16 with no resource change, row 16's run 1 exercises the same already-created /
  already-migrated state as its run 2. Ticket 04's log-pattern exception (`04:89-93`) is
  underspecified rather than wrong: "already up"/"nothing to do" are Ecto migrator strings;
  the generator's no-op is "No changes detected, so no migrations or snapshots have been
  created."
- **Evidence.** `deps/ash/lib/mix/tasks/ash.setup.ex:18-41,50-72`; `deps/ash_postgres/lib/
  data_layer.ex:637-662`; `deps/ash/lib/mix/tasks/ash.codegen.ex:40-80` (`grep -rln "def
  codegen(" deps/*/lib` → only `data_layer.ex`); `deps/ash/lib/mix/tasks/
  ash.generate_resource_diagrams.ex:5`; `deps/ash/lib/mix/tasks/ash.reset.ex:13-17`;
  `deps/ash/lib/mix/tasks/ash.tear_down.ex:13-31`; `deps/ash/lib/mix/tasks/helpers.ex:
  14-51,64-70`; `deps/ash_postgres/lib/mix/tasks/ash_postgres.generate_migrations.ex:
  88-130`; `deps/ash_postgres/lib/migration_generator/migration_generator.ex:87-94,
  113-115,737-740`; `deps/ecto_sql/lib/ecto/migrator.ex:750`; `deps/ecto/lib/mix/tasks/
  ecto.create.ex:81`; `test/fixtures/book_library/mix.exs:38`; `02:109-110,118`;
  `04:89-93,127-129`; `pack/ontology.ttl:156-193,255,262-265`. `mix help ash.setup` in
  the fixture: "Runs all setup tasks for any extension..." (no install).
- **Why it matters.** Three rows (15, 16, and effectively 10 — see m7) consume matrix slots
  while re-exercising a path an earlier row already covered, and the ticket's composition
  model is wrong in the places ticket 04's evidence rules depend on.
- **Fix.** Correct rows 15/16/24 purpose text citing the deps lines above. Keep one
  migration-generation row; if both task names are wanted, make row 15 `mix ash.codegen
  --check` (exit 1 iff snapshots and resources disagree, no name required) — the
  framework's own idempotency oracle for this step, satisfying def (a)/(e) directly. Either
  drop rows 12/14 and let 16 be the create+migrate step, or drop 16. In ticket 04 name the
  concrete run-2 strings: `The database for <Repo> has already been created`, `Migrations
  already up`, `No changes detected, so no migrations or snapshots have been created.`

#### M5. 26 subprocesses each re-run `Mix.Task.run("compile")`; compile state between rows is load-bearing, whereas one composed Igniter shares an in-memory rewrite and compiles once

- **Claim.** Every `use Igniter.Mix.Task` `run/1` compiles first, `ash.extend` compiles
  again inside `igniter/1`, and the reactor's `:verify` compiles once more — roughly 28
  mix boot + incremental-compile passes, each also loading the `ggen_igniter` path dep
  (Rustler NIF). Incremental compile recompiles only files earlier rows wrote, but that is
  exactly the coupling: row N's boot compiles row N-1's output, so a non-compiling generated
  file (B3) fails rows N..26 at boot and `sh_after` attributes the failure to the wrong
  row. A single composed Igniter has none of this: `ash.gen.resource` composes
  `ash.gen.domain` and resolves modules against `igniter.rewrite`, so the domain created
  earlier in the same igniter is visible with no compile, one diff is previewed, one
  `Rewrite.write_all` happens, and queued plain-Mix tasks (`add_task`) run after the single
  write.
- **Evidence.** `deps/igniter/lib/mix/task.ex:89-91`; `deps/ash/lib/mix/tasks/
  ash.extend.ex:57`; `lib/ggen_igniter/reactors/reconcile_reactor.ex:613`;
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:101,185,259`; `deps/igniter/lib/
  igniter.ex:425-427,481-499,1227,1257,1295`; `deps/ash/lib/mix/tasks/ash.codegen.ex:36`,
  `ash.setup.ex:13`, `deps/ash_postgres/lib/mix/tasks/ash_postgres.create.ex:6` (`use
  Mix.Task`); `pack/ontology.ttl:46-277` (ranks 1..26); `pack/templates/
  ash_tier_task_receipt.sh.eex`; `pack/bin/run_pending_receipts.sh:79,82`;
  `test/fixtures/book_library/mix.exs:38`; `mix.exs:110` (rustler);
  `DRY-RUN-RECEIPT.md:69-77`.
- **Why it matters.** The harness converts every composable step into its own OS process,
  which is the framework's composition model turned inside out, and every workaround in
  m8 exists to compensate.
- **Fix.** Let the ontology target a composed Igniter task: scaffold
  `lib/mix/tasks/book_library.matrix.ex` (`mix igniter.gen.task`), make that file the
  `mode: file` output of a new `templates/matrix_task.ex.eex` iterating the same query;
  for rows 1-11/17 render `|> Igniter.compose_task("<%= mix_task %>", ~w(<%= mix_args
  %>))` in rank order (declared in `info/0` `composes:`); for the plain `Mix.Task` rows
  (12-16, 18-21) render `|> Igniter.add_task(...)`; keep destructive rows 22-26 as
  disposable-copy receipts. `sh_after` becomes `mix book_library.matrix --yes` (run 1)
  and `mix book_library.matrix --check` (run 2). See also M6 for the in-process eval-mode
  alternative.

#### M6. Receipt-as-shell-script with a fixed `sh_after` runner works around ggen_igniter's own Igniter-composing eval mode instead of using it

- **Claim.** The pack routes every row, including the Igniter-based ones, through a
  `mode: file` `.sh` receipt plus a fixed, non-EEx `sh_after:` runner, so each row costs
  sh -> mix -> Igniter -> fresh BEAM and needs a mkdir lock, `.done`/`.failed` markers, a
  disposable-copy protocol, `ELIXIR_ERL_OPTIONS="+S 1"`, and lives under ShellHook's 60 s
  timeout. ggen_igniter already supports `mode: eval` with a live `igniter:` binding folded
  sequentially in row order across `--for-each` rows, and since sync runs from inside
  `book_library`, `Mix.Task.get("ash.gen.*")` resolves in that VM, so `igniter |>
  Igniter.compose_task("<%= mix_task %>", args)` would compose the Igniter rows
  in-process. Caveats: the reactor does NOT write the final accumulator (it only reports
  `igniter_paths`), so the eval body must call `Igniter.do_or_dry_run/2` itself; eval
  bodies are skipped under `--dry-run`; and `--yes` redundancy (m2) holds only when
  `MIX_ENV != test`. Non-Igniter rows still need the shell path.
- **Evidence.** `lib/ggen_igniter/reactors/reconcile_reactor.ex:1413,1451-1455,1553-1558,
  1798-1799,1937-1961,2262`; `lib/ggen_igniter/frontmatter.ex:191`; `test/fixtures/
  eval_mode_for_each.exs.eex`; `test/ggen_igniter_eval_mode_igniter_test.exs:90-120`;
  `grep -rn do_or_dry_run lib test --exclude-dir=deps` → comments only;
  `deps/igniter/lib/igniter.ex:479-560`; `deps/igniter/lib/mix/task.ex:184-192,312-319`;
  `pack/templates/ash_tier_task_receipt.sh.eex:1-5`; `pack/bin/run_pending_receipts.sh:
  36-40,52-68,74-91`; `pack/bin/matrix_run.sh:22-33`; `pack/README.md:81,127,137`;
  `lib/ggen_igniter/shell_hook.ex:55`.
- **Why it matters.** The repo already owns the composition primitive the pack is
  emulating with shell; Igniter issues/warnings would be observable as data, not an exit code.
- **Fix.** Split the pack by an ontology property `alp:taskKind` (`"igniter"` | `"mix"`):
  `templates/igniter_row.exs.eex` with `mode: eval` whose body composes the task and
  returns the `%Igniter{}` (last row calls `Igniter.do_or_dry_run`), and keep the `.sh`
  receipt + runner only for `"mix"` rows. Add a verify query failing if a row tagged
  igniter has a deps file that does not `use Igniter.Mix.Task`.

#### M7. Igniter's native `--dry-run` is bypassed: ggen's `--dry-run` previews receipt-file writes, never the generators' diffs

- **Claim.** `run_sh_hook!/6`'s dry-run clause returns only `planned: run sh_after: ...`
  and never calls ShellHook, so no `mix ash.*` runs and no generator diff is computed.
  Igniter 0.8.4 has a first-class global `--dry-run` that renders the full diff and returns
  before writing, composing with the `--yes` the pack already adds — but nothing in the
  pack passes it (the receipt body is EEx-rendered so it could be templated in; the real
  blocker is the reactor exposes no dry-run signal to the runner). The ticket is honest
  that no `mix ash.*` executed (`DRY-RUN-RECEIPT.md:16,242-260`; `README.md:165`) but
  labels the state "DRY-RUN VERIFIED" (`03:5`) while the reachable inner preview — what
  `ash.gen.resource` would write under `lib/book_library/` and how `ash_postgres.install`
  would edit `config/*.exs` — was never produced. Igniter `--dry-run` covers only the 12
  Igniter-based rows.
- **Evidence.** `lib/ggen_igniter/reactors/reconcile_reactor.ex:2370-2371,2392-2394`;
  `deps/igniter/lib/mix/task/info.ex:77-80`; `deps/igniter/lib/igniter.ex:1169-1178,
  1210-1214`; `pack/templates/ash_tier_task_receipt.sh.eex:5,22`; `pack/bin/
  run_pending_receipts.sh:4-10`; `grep -rn dry pack/templates pack/bin` → only
  `matrix_run.sh:7`; `pack/README.md:37,165`; `DRY-RUN-RECEIPT.md:16,242-260`; `03:5`.
- **Why it matters.** A two-level dry run whose inner level is missing is presented as
  verification of the plan.
- **Fix.** Propagate ggen's dry-run into the row: have the dry-run clause still execute the
  hook with `GGEN_IGNITER_DRY_RUN=1` set and render `mix <task> <args>
  ${GGEN_IGNITER_DRY_RUN:+--dry-run}` for Igniter rows; or with M5's composed task, add a
  `plan` step running `mix book_library.matrix --dry-run` and save the diff as the plan
  artifact. Rename `03:5` to "receipt-render verified; generator preview not performed"
  until the inner dry-run exists.

#### M8. The matrix never runs `ash.install` and bypasses `mix igniter.install ash,ash_postgres`, Igniter's multi-installer single-pass entrypoint; generated files are formatted without `Spark.Formatter`

- **Claim.** Row 11 shells `mix ash_postgres.install --yes` directly; no row, script, or doc
  runs `ash.install` or `mix igniter.install`. `ash_postgres.install` does not compose
  `ash.install` and its own moduledoc says to run it via `mix igniter.install ash_postgres`.
  `mix igniter.install ash,ash_postgres --yes` composes each installer onto one igniter
  and calls `do_or_dry_run` once. Skipping `ash.install` omits `spark.install`'s
  `add_formatter_plugin(Spark.Formatter)`, the Spark `section_order` config for
  `Ash.Resource`/`Ash.Domain`, and the `:ash` dev/test config. Because Igniter formats
  through the project's `.formatter.exs` (which loads plugins) and the fixture's
  `.formatter.exs` has no `plugins:`, every file Igniter writes in rows 2-10 is formatted
  without Spark's DSL section ordering — run-2 stability holds, but artifacts drift from
  framework-bootstrapped defaults and row 11's "real first install" label describes a
  partial install. `ash.install`'s gen.domain/gen.enum/gen.resource chain runs only under
  `--example`, so it is the framework's example-scaffold reference rather than an
  unconditional step.
- **Evidence.** `deps/igniter/lib/mix/tasks/igniter.install.ex:14-16,39-45`;
  `deps/igniter/lib/igniter/util/install.ex:196-233`; `deps/ash/lib/mix/tasks/install/
  ash.install.ex:19,96,114-115,139-147,156-207,225-231,242-270`; `deps/spark/lib/mix/
  tasks/spark.install.ex:27`; `deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:
  7,625` (no `compose_task`); `deps/igniter/lib/igniter.ex:144-160`; `deps/rewrite/lib/
  rewrite/dot_formatter.ex:45,123-124`; `deps/spark/lib/spark/formatter.ex:16-17,175-181`;
  `test/fixtures/book_library/.formatter.exs` (3 lines, no plugins); `pack/ontology.ttl:
  138-146`; grep for `ash.install|igniter.install` over ontology/bin/README/docs → none.
- **Why it matters.** The pack calls itself the "real first install" while skipping the
  install path the framework documents, and the formatting difference is silent.
- **Fix.** Replace row 11 with `mix igniter.install ash,ash_postgres --yes` (same
  `--check`/`--dry-run` switches apply), or add a row 0 `ash.install --yes` ahead of row 1
  and keep row 11 for the standalone check. Add a run-2 assertion that `.formatter.exs`
  contains `Spark.Formatter`.

#### M9. The only Spark relationship-DSL patch in the matrix was deleted instead of fixed; no Author/Loan resource is generated; ticket 02 row 2 is still unrunnable as written

- **Claim.** No matrix row passes `-r`/`--relationship`, so `Ash.Resource.Igniter.
  add_new_relationship` and the generator's relationship path are unexercised; only
  `attributes`/actions sections are patched. Ticket 01's Loan (`book_id -> Book`,
  `01:60-62`) is not generated by any row. Ticket 02 row 2 (`:96`) still carries a
  valueless `--uuid-primary-key` (the switch is `:string`; a real OptionParser parse
  returns `{"--uuid-primary-key", nil}` as invalid) and the dangling Author reference,
  marked open at `:25`. The pack's justification for dropping `-r` (`ontology.ttl:62`,
  "would not compile") is UNVERIFIED and likely overstated: Ash's relationship verifier
  skips a destination that fails `Code.ensure_compiled`.
- **Evidence.** `grep -n "mixArgs.* -r " pack/ontology.ttl` → none; `grep -n Loan` → none;
  `pack/ontology.ttl:60-62`; `pack/README.md:49`; `02:23-25,96`; `01:59-62`;
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:65,424,484-503,666,717-731`;
  `deps/ash/lib/ash/resource/igniter.ex:455-461`; `deps/ash/lib/ash/resource/verifiers/
  validate_relationship_attributes_match.ex:24-31`. Probe: `elixir -e 'IO.inspect
  OptionParser.parse(["X","--uuid-primary-key","--timestamps"], switches:
  [uuid_primary_key: :string, timestamps: :boolean])'` → `{[timestamps: true], ["X"],
  [{"--uuid-primary-key", nil}]}`.
- **Why it matters.** A "Spark DSL patching" validation matrix that never patches a
  `relationships` block, and a spec row that cannot be typed at a shell.
- **Fix.** Add a Loan row after Book: `mix ash.gen.resource Elixir.BookLibrary.Catalog.Loan
  --domain Elixir.BookLibrary.Catalog -a borrower:string:public -a
  checked_out_at:utc_datetime:public -a returned_at:utc_datetime:public -r
  belongs_to:book:Elixir.BookLibrary.Catalog.Book:required:public --uuid-primary-key id
  --timestamps --default-actions read,create,update,destroy --ignore-if-exists`. Amend
  ticket 02 row 2 to the pack's real args.

#### M10. Ontology stores mix CLI strings, not domain facts; the sibling lifecycle pack already has attribute-level `alp:` modeling that is duplicated rather than reused

- **Claim.** All 26 `alp:AshTierTask` rows expose only an opaque `alp:mixArgs` string
  consumed verbatim by the single gate and template. Exactly one row (Tier1Row02,
  `ontology.ttl:60`, ~280-char literal) hard-codes the Book shape (4 attributes with
  modifiers, uuid pk `id`, timestamps, default actions) inside a shell string. The sibling
  `ash-lifecycle-pack` models these as `alp:Resource`/`alp:Attribute`/`alp:Action`/
  `alp:Relationship` with gates and a template deriving DSL from them, so row 2's shape
  could be derived per the real flag grammar. Adding an attribute to Book currently means
  editing a quoted shell fragment. Rows 9/10/24 also repeat the Book module name in
  `alp:moduleName` with no link to a resource individual. This is major design-debt, not a
  runtime blocker; the lifecycle pack is a sibling with a different stated purpose, not a
  prior version, so "regression" is the wrong word.
- **Evidence.** `pack/ontology.ttl:19-21,55-62`; `grep -c 'a alp:AshTierTask'` → 26;
  `pack/gates/010_ash_tier_task_query.rq`; `pack/templates/ash_tier_task_receipt.sh.eex:
  15,25,28`; `test/fixtures/ash-lifecycle-pack/ontology.ttl:15-40,55-70`, `gates/
  020_attributes.rq`, `templates/resource.ex.eex:19-58`; `deps/ash/lib/mix/tasks/gen/
  ash.gen.resource.ex:30-32,63-79`.
- **Why it matters.** The pack is ticket 02's table transliterated to Turtle; the ontology
  does not carry the facts a generator would want to vary.
- **Fix.** Model Book as `alp:Resource` + `alp:Attribute` (add `alp:attributePublic
  xsd:boolean`) and derive row 2's flags in the template (`-a <%= name %>:<%= type %><%= if
  !allow_nil, do: ":required" %><%= if public, do: ":public" %>`, `--uuid-primary-key
  <%= pk %>`, `--default-actions` from `alp:Action`). Keep `alp:AshTierTask` for the 25
  flag-only rows with an optional `alp:targetsResource`. Do not derive `-r
  belongs_to:author` (Author is never generated); derive Loan's `-r` per M9.

#### M11. No drift check between `ontology.ttl` and ticket 02; the 13/26 divergence was found by hand and nothing prevents recurrence

- **Claim.** `DRY-RUN-RECEIPT.md:23` records that 13 of 26 rows silently differed from
  ticket 02 before a manual reconciliation. The repair added `alp:specDeviation` (rdfs:
  domain + comment only; no range, no SHACL/SPARQL constraint). Nothing machine-checks the
  invariant the comment states: `gates/` holds a single plain SELECT with no verify/ASK
  companion, no ExUnit test loads the pack, and ticket 02's markdown table is the only
  other copy. The row-20/23 mismatch class (`ash.generate_policy_chart` singular;
  `ash.reset` not `ash_postgres.reset`, `00-OVERVIEW.md:88-89`, `03:82`) shows
  mixTask-vs-deps drift is a real, previously-hit bug class. The verify-query doctrine is
  in the user's global `~/CLAUDE.md`, not this repo's — so "the repo's own doctrine" is an
  overstatement; severity is major (missing regression guard), not blocker.
- **Evidence.** `ls pack/gates/` → `010_ash_tier_task_query.rq` only; `DRY-RUN-RECEIPT.
  md:23`; `pack/ontology.ttl` `alp:specDeviation` declaration (no `rdfs:range`; contrast
  `alp:rank`/`alp:destructive`); `grep -rln "ash_tier_matrix_pack\|AshTierTask" test/ lib/
  | grep -v fixtures/ash_tier` → `.gitignore` only; `02:76-103`.
- **Why it matters.** The same silent divergence will recur on the next edit of either file.
- **Fix.** Render ticket 02's table from the ontology (`templates/matrix_table.md.eex`,
  `to: docs/jira/v26.9.8/02-matrix-generated.md`) and add an ExUnit test that loads
  `ontology.ttl` via `GgenIgniter.Ontology.load!/1`, runs the query, and asserts (a) ranks
  exactly 1..26, (b) every `alp:mixTask` has a file under `deps/{ash,ash_postgres}/lib/mix/
  tasks/**/<task>.ex`, (c) `specDeviation == ""` implies `mixArgs` equals ticket 02's
  literal. Or add `gates/020_verify_task_exists.rq`.

### Minors

#### m1. Row 2's `--conflicts` mechanism is dead code on run 2

- **Claim.** `ontology.ttl:61` cites `--conflicts defaults to ignore (ash.gen.resource.ex:
  40,120)` alongside `--ignore-if-exists` as run-2 mechanism, but the `--ignore-if-exists
  && exists?` guard at `:103-104` returns before the `conflicts_strategy` case at `:118-120`
  is reached; `--conflicts` is a run-1 mechanism only.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:101-104,118-120`;
  `pack/ontology.ttl:61`.
- **Fix.** Trim Row02's mechanism to the `--ignore-if-exists` short-circuit; move the
  `--conflicts` note to a run-1 remark.

#### m2. `--yes` rationale is inverted and its citation points at consumption sites; Igniter already forces `yes: true` when stdin is not a TTY

- **Claim.** `README.md:37-38` and `ontology.ttl:33-38` (plus each `+ --yes`
  specDeviation) say the flag is required because `sh_after` has no TTY and tasks would
  block on "Proceed with changes?", citing `task.ex:117,189`. Line 189 is the branch of
  `set_yes/2` that injects `yes: true` when `tty?()` is false; the harness's
  `System.cmd("sh", ["-c", ...])` spawn yields a non-device `/dev/stdin` (probe: `:other`),
  so the prompt is already suppressed. `--yes` is redundant, not deps-forced (harmless).
  Caveats: `set_yes` is a no-op under `MIX_ENV=test`; a `< /dev/null` redirect makes
  `/dev/stdin` report `:device`. The switch is declared at `info.ex:77-91`, not `task.ex`.
- **Evidence.** `deps/igniter/lib/mix/task.ex:112-118,182-200,311-318`; `deps/igniter/lib/
  mix/task/info.ex:77-91`; `lib/ggen_igniter/shell_hook.ex:94`; probes from
  `test/fixtures/book_library` (nested `elixir -e` under `System.cmd("sh", ...)` →
  `:other`; `< /dev/null` → `:device`); `ls test/fixtures/book_library/_build` → `dev`.
- **Fix.** Reword to "redundant with Igniter's non-TTY auto-yes (task.ex:187-193); kept as
  an explicit, greppable opt-in — note `< /dev/null` would NOT trigger auto-yes"; point the
  citation at `info.ex:77-91`.

#### m3. Row 20 `ash.generate_policy_chart --all` produces zero files, so its def (b) claim is vacuous

- **Claim.** The task filters to resources with `Ash.Policy.Authorizer`; no matrix row or
  fixture file adds that extension (rows 9/10 extend only `AshPostgres.DataLayer`), so
  `--all` writes nothing and "deterministic regeneration" has no artifact. Row 19's
  `.mmd` beside the domain source is real.
- **Evidence.** `deps/ash/lib/mix/tasks/ash.generate_policy_chart.ex:52-54`;
  `deps/ash/lib/mix/mermaid.ex:17-22,57-67`; `pack/ontology.ttl:124,133,221-228`; `grep
  -rn "Policy.Authorizer" pack/ontology.ttl test/fixtures/book_library/{lib,config}` →
  none.
- **Fix.** Add `Elixir.Ash.Policy.Authorizer` to row 9's extension list so a chart is
  generated, or mark Row20 "vacuous: zero resources match" and drop the def (b) claim.

#### m4. `ash.gen.domain` does not do "domain resource-reference registration"; that is `ash.gen.resource`, which composes `ash.gen.domain`

- **Claim.** `02:36-38`, `03:50-51`, `00-OVERVIEW.md:60-62` justify the shellout decision
  by attributing config editing and resource-reference registration to the pair
  `ash.gen.domain`/`ash.gen.resource`, but cite only `ash.gen.domain.ex`. That task only
  creates the module (empty `resources` block) and prepends to `:ash_domains`; registration
  is `Ash.Domain.Igniter.add_resource_reference/3` at `ash.gen.resource.ex:186`, right
  after the compose at `:185`. `06-OCEL:23-27` makes no such claim.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex:30-57`; `deps/ash/lib/mix/
  tasks/gen/ash.gen.resource.ex:19,185-189`; `mix help ash.gen.domain` in the fixture.
- **Fix.** Attribute registration to `ash.gen.resource` and cite `gen.resource.ex:185-186`
  — the composition is the strongest argument for the shellout decision.

#### m5. Row 10 `ash.patch.extend` is a deprecated alias of row 9 and provably a no-op after it; ticket 02's "interactive patch, non-interactive mode TBD" describes a nonexistent mode

- **Claim.** `info/2` and `igniter/1` delegate verbatim to `Mix.Tasks.Ash.Extend`
  (moduledoc: "Use `ash.extend` instead"). Given the same extension twice, the singleton
  `data_layer:` path replaces the node with an equal alias and skips constructor removal
  (`nodes_equal?` -> `:error`), and `set_option` uses the identity updater on existing
  `table`/`repo` — a byte-level no-op. As written in ticket 02 (subject only) it would
  run with an empty extension list, not prompt. The non-singleton `extensions:` list path
  is covered by neither row.
- **Evidence.** `deps/ash/lib/mix/tasks/patch/ash.patch.extend.ex:7-21`; `mix help
  ash.patch.extend`; `deps/ash/lib/mix/tasks/ash.extend.ex:41-45,176-184,264-267`;
  `deps/spark/lib/spark/igniter.ex:137,191-194,306-336`; `deps/ash_postgres/lib/
  data_layer.ex:4570-4572`; `02:104`.
- **Fix.** Delete row 10 or relabel it "alias check: expect identical output to row 9 run
  2"; if a distinct Spark patch is wanted, extend the Domain so `prepend_new_to_list` is
  exercised.

#### m6. Row 2 attribute/action args are valid, but no golden file records the expected generated `defaults`, so "byte-identical" has no run-1 reference

- **Claim.** For the pack's row 2 args, ash 3.33.1 emits `defaults [:read, :destroy,
  create: [:title, :author, :isbn, :published_year], update: [...same...]]` (accept list
  from `public`-tagged `-a` entries in argv order; defaults stably re-sorted). Ticket 02's
  own row 2 literal would yield `create: [:title, :isbn]`. No `expected/` directory exists,
  so row 2's "byte-identical" is a run-2 self-comparison only.
- **Evidence.** `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:103-105,120-122,137-140,
  167-183,218-230,606-621`; `pack/ontology.ttl:59-62`; `02:96`; `ls pack/expected` →
  absent.
- **Fix.** Add `pack/expected/book.ex` as a golden file and diff run-1 output against it.

#### m7. `ELIXIR_ERL_OPTIONS="+S 1"` and the fixed 60 s hook timeout are workarounds for running composable steps as concurrent subprocesses; the timeout is not threadable from the template

- **Claim.** `matrix_run.sh` forces one scheduler so the reactor's `Task.async_stream`
  (`max_concurrency = schedulers_online`) runs hook-bearing rows sequentially, and the
  runner adds a mkdir lock; both exist because composable steps became concurrent OS
  processes. `ShellHook.run/3` supports `opts[:timeout_ms]` but the reactor calls it with
  two args, so 60 s is the hard per-hook ceiling with no frontmatter/CLI override;
  `README.md:137-139` already warns `ash.setup`/`ash.reset` may exceed it cold. Whether a
  composed task would exceed 60 s is UNVERIFIED.
- **Evidence.** `lib/ggen_igniter/reactors/reconcile_reactor.ex:1747,2399,2408-2410`;
  `lib/ggen_igniter/shell_hook.ex:55,89-90`; `grep -rn sh_timeout lib/ pack/` → only the
  atom at `:2408`; `lib/mix/tasks/ggen_igniter.sync.ex:365-415`; `pack/bin/matrix_run.sh:
  16-17,33`; `pack/bin/run_pending_receipts.sh:40-48`; `pack/README.md:124-129,137-139`.
- **Fix.** Add `sh_timeout_ms:` frontmatter next to `sh_before:`/`sh_after:` and pass it
  through `run_sh_hook!/6`; add `sh_serial: true` so hook-bearing targets actuate
  sequentially without the environment hack. Both become moot for Igniter rows under M5/M6.

#### m8. "Compensated" is false on any hook failure: the reactor reverts only the receipt `.sh`, never the mix task's edits; the ontology cannot name expected paths

- **Claim.** `tracked` is built solely as `%{path: pa.target, ...}`; a runner nonzero exit
  becomes `{:hook_failed, e}` and the run lands on `:compensated` having reverted only
  receipt files. Edits by non-destructive `mix ash.*` rows into `lib/`, `config/`, `priv/`
  are neither tracked nor reverted (a limitation the reactor discloses at
  `DRY-RUN-RECEIPT.md:194`). Destructive rows are exempt (disposable copy). The ontology
  has no path-valued property.
- **Evidence.** `lib/ggen_igniter/reactors/reconcile_reactor.ex:1012-1016,2042-2047,
  2059-2068,2102`; `DRY-RUN-RECEIPT.md:194`; `pack/bin/run_pending_receipts.sh:53-75,82,
  85-89`; `pack/ontology.ttl:16-28`; `grep -rn "expectedPath" pack/ lib/` → none.
- **Fix.** Add multi-valued `alp:expectedPaths` per row derived from domain facts, render
  into the receipt header, and have the runner snapshot `git status --porcelain`
  before/after each receipt into `<receipt>.paths`. Under M6's eval design the Igniter
  accumulator already carries the Rewrite sources.

#### m9. 06-OCEL's wiring design cannot work as described: the sink is an in-VM Agent pid and each `mix ash.*` is a grandchild OS process of a shell script

- **Claim.** The API inventory in 06 is accurate; the wiring (item 4, "calls emit/4 before
  and after the real System.cmd call" per task) is not: `emit/4` appends to an Agent pid
  and fires `:telemetry` in the calling VM; the reactor's `sh_after` is one
  `System.cmd("sh", ["-c", cmd])` launching the runner, which runs each receipt via `sh
  "$f"`. There is no per-task `System.cmd` to wrap and no path from a child `mix` to the
  sink. Item 2's per-invocation `git_diff_empty?` contradicts ticket 04 and
  `matrix_run.sh:41-42`, which diff once per run.
- **Evidence.** `lib/ggen_igniter/telemetry/ocel_emitter.ex:130-133,189-199,233`;
  `lib/ggen_igniter/shell_hook.ex:89-94`; `pack/bin/run_pending_receipts.sh` (loop body);
  `06:~46-62`; `04:65-74`; `pack/bin/matrix_run.sh:41-42`.
- **Fix.** Instrument `GgenIgniter.ShellHook.run/2` (or the reactor's `sh_after` step) to
  `emit/4` `<task>_run` events with the hook's exit code, recovering `mix_task`/`mix_args`
  from the receipt filename; or have the runner append JSONL per receipt and replay through
  `emit/4` post-run. Move `git_diff_empty?` to a per-run event.

## Section 2 — REFUTED findings

Kept as evidence of rigor; each was raised by a lens and did not survive verification.

- **`--yes` suppresses the diff output the evidence bar depends on (major).** Half true
  (`display_diff/2` is a no-op under `--yes`, `igniter.ex:1471-1475,1169`; auto-yes makes
  the flag redundant — see m2), but ticket 04's evidence bar (`04:97-108`) is `git diff
  --stat` + compile + grep + exit codes; the `.log` is not on it and the written-file diff
  is captured by git. Residual is the m2 documentation error.
- **Row 1 is already executed inside row 2 and `prepend_new_to_list` (not
  `--ignore-if-exists`) is what keeps `config.exs` duplicate-free (major).** Composition
  is real (`ash.gen.resource.ex:184-189`), but with row 1 running first the composed
  `ash.gen.domain --ignore-if-exists` hits `exists?` at `ash.gen.domain.ex:36-37` and
  returns before `configure` at `:44-56`, so `prepend_new_to_list` never fires in row 2;
  the ontology's citation of `ash.gen.resource.ex:103` is correct. Residual: row 1 is
  redundant in a composed design, and `add_resource_reference` mutates the domain in row 2
  run 1 (`ash/lib/ash/domain/igniter.ex:48-73`) — neither is mentioned by the matrix.
- **Row 23 `ash.reset` in the disposable copy re-migrates from the copy's `priv/` while
  sharing `_build` and the DB, leaking state into the fixture (major).** The copy is a tar
  snapshot taken after rows 13-16 wrote migrations and rows 22-25 write none, so the
  migration lists are identical; row 25 drops the DB afterwards so nothing row 23 built
  survives; row 26's squash resolves `priv/resource_snapshots` from `File.cwd!()` (the
  copy) which `matrix_run.sh:27-30` removes; `Mix.Project.deps_paths()[:ggen_igniter]`
  resolves to the same absolute path in both trees. The shared-DB destruction is
  disclosed (`run_pending_receipts.sh:30-31`, `DRY-RUN-RECEIPT.md:248`). Superseded by B4.
- **Rows 1, 9, 10 duplicate work `ash.gen.resource` already composes, and the fixture is
  non-compiling between rows 9 and 11 (major).** Row 2's `mixArgs` has no `-e`/`--extend`,
  and `extend(igniter, _, [], _)` (`ash.gen.resource.ex:197-199`) means `ash.extend` is
  never composed, so rows 9/10 are not duplicated by row 2; row 10 as row 9's replay is
  declared at `ontology.ttl:134`. The non-compiling claim is unsupported (Spark
  `{:behaviour, _}` accepts any atom, `options.ex:1496-1499`; no verifier resolves the
  repo). Residual (row 1 vs row 2 redundancy; per-process execution) is covered by M1/M5.

## Section 3 — What the maintainer would change first

Proposed scope for `07-ASH-MAINTAINER-REVIEW-FIXES.md` (not written by this review), in
order:

1. **Make the matrix runnable and honest about exit codes (B1, B2, B3, B5).** Drop
   `--ignore-if-exists` from row 1 (or fold row 1 into row 2's composition); pass `--check`
   on every Igniter row's run 2 and make the runner treat `^Issues:` in a log as failure;
   remove row 8 (upstream `args:`/`arguments:` mismatch) and either move row 3 ahead of row
   2 with `--base` or drop it per ticket 01; correct every "run 2 is expected to exit
   nonzero" sentence and the `task.ex:237` rationale across ontology/README/02/04/receipt.
2. **Reorder to the framework's install lifecycle (M1, M2, M8).** `mix igniter.install
   ash,ash_postgres --yes` (or `ash.install` then `ash_postgres.install`) immediately after
   `ash.gen.domain`, then `ash.gen.resource --extend Elixir.AshPostgres.DataLayer`, then
   migrations. Record that the installer queues `ash.codegen initialize` and re-runs
   `deps.get`; rename `--name add_book_and_author`; assert `Spark.Formatter` in
   `.formatter.exs`.
3. **Isolate the database for destructive rows and fix the drop/setup/codegen claims (B4,
   M3, M4).** Rewrite `database:` in the disposable copy's `config/dev.exs` and drop it on
   cleanup (or split the protocol into 1-21 twice / 22-26 once). Reword row 25 as
   idempotent-exit-0 and remove one of rows 24/25; correct rows 15/16/24 compositions; make
   row 15 `ash.codegen --check`; name the concrete run-2 log strings in ticket 04.
4. **Compose instead of shelling out for Igniter rows (M5, M6, M7, m7).** Add `alp:taskKind`
   and either a generated `book_library.matrix` composed task (`--yes` run 1 / `--check`
   run 2 / `--dry-run` plan) or an `eval`-mode template that composes on the reactor's
   `igniter:` binding and calls `Igniter.do_or_dry_run` itself; keep `.sh` receipts only
   for plain `Mix.Task` rows; add `sh_timeout_ms:` frontmatter. Propagate ggen's dry-run
   into an inner Igniter `--dry-run` and relabel `03:5`.
5. **Make the ontology carry facts and guard against drift (M9, M10, M11, m3, m6, m8).**
   Model Book (and a Loan with `belongs_to:book`) as `alp:Resource`/`alp:Attribute`/
   `alp:Relationship`, derive row 2's flags in the template, add `alp:expectedPaths`,
   render ticket 02's table from the ontology, and add an ExUnit test asserting ranks
   1..26, every `mixTask` resolves to a deps file, and `specDeviation == ""` rows match the
   ticket literal. Add `Ash.Policy.Authorizer` to row 9 (or mark row 20 vacuous) and a
   golden `expected/book.ex`.

## Section 4 — What this review did NOT check

- **No non-dry run was executed.** Every `mix ash.*` invocation cited was either a
  `--dry-run`, `mix help`, a `mix run -e` compile probe of a single module, or an
  `elixir -e` OptionParser/TTY probe inside `test/fixtures/book_library`. No receipt was
  driven through `run_pending_receipts.sh`, no database was created or dropped, and no
  `git status` change resulted. Consequently: whether the fixture compiles between rows 9
  and 11 (M1), whether row 11's queued `ash.codegen initialize` succeeds and emits the
  initialize migration (M2), whether a composed task would exceed 60 s (m7), and whether
  the `-r belongs_to` removal was actually needed (M9) are UNVERIFIED by execution —
  confirmed at the mechanism level from source only.
- **No upstream issues were filed.** The `ash.gen.custom_expression` `args:` vs
  `arguments:` mismatch (B3) and the absence of `ignore_if_exists` from `ash.gen.domain`'s
  schema (B1) are upstream-shaped defects in ash 3.33.1 that this review identifies but
  does not report to the Ash project.
- **Not reviewed:** ticket 05 (Tier-2 deferral / xaas cutover) beyond cross-references;
  `06-OCEL` beyond its wiring paragraph; the ggen_igniter reactor's non-hook code paths;
  the `ash-lifecycle-pack` itself (only used as a comparison point in M10); Igniter
  behaviour under `MIX_ENV=test` (`set_yes` no-op) since the fixture has only a `dev`
  build; rows 17-21 (`ash.set.domains`, `ash.manifest.dump`, diagrams, livebook) beyond
  rows 19/20 in m3.
- **Line numbers** were checked against the vendored deps at HEAD `1738ad1`; several raw
  lens citations were corrected by the verifier (e.g. `igniter.ex:1249-1263` -> `:1229-1238,
  :1257`; `run_pending_receipts.sh:398-458` -> `:36-91`; `DRY-RUN-RECEIPT.md:378` -> `:194`)
  and only the corrected locations appear above.

## See Also

- `docs/jira/v26.9.8/00-OVERVIEW.md` — ticket-set index this review targets.
- `docs/jira/v26.9.8/02-ASH-TASK-VALIDATION-MATRIX.md`,
  `03-SH-AFTER-ALLOW-SH-HARNESS.md`, `04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md`,
  `DRY-RUN-RECEIPT.md` — the reviewed documents.
- `test/fixtures/ash_tier_matrix_pack/README.md` — the harness under review.
- `test/fixtures/book_library/deps/{ash,ash_postgres,igniter,spark}/` — the ground truth
  every `file:line` above resolves against.
