# `sh_after:`/`--allow-sh` harness for the Tier-1 Ash task matrix

> **SUPERSEDED — pre-execution history, and the harness no longer exists.** The
> `sh_after:` + `--allow-sh` 26-shell-out design specified here was replaced by a
> single composed `Igniter.Mix.Task`:
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) §"What changed and why"
> states the reason — every shelled row spawned its own BEAM, so a subprocess exit
> code became the only available idempotency signal, and that signal is not an
> oracle. The directory this ticket documents,
> `test/fixtures/ash_tier_matrix_pack/`, has since been **deleted from the repo**, so
> nothing below can be run. It is retained for the design rationale, not as
> instructions. [00-OVERVIEW.md](00-OVERVIEW.md)'s status table governs on conflict.

## Status (pre-execution, superseded)

**DRY-RUN VERIFIED (not executed).** As of 2026-09-08 (HEAD `1738ad1`) the harness existed on
disk, untracked and uncommitted, at `test/fixtures/ash_tier_matrix_pack/` (since deleted):

```text
test/fixtures/ash_tier_matrix_pack/README.md
test/fixtures/ash_tier_matrix_pack/ontology.ttl                      # 26 alp:AshTierTask individuals
test/fixtures/ash_tier_matrix_pack/gates/010_ash_tier_task_query.rq  # the for-each query
test/fixtures/ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex
test/fixtures/ash_tier_matrix_pack/bin/run_pending_receipts.sh       # the single sh_after: target
test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh                 # ticket 04's driver wrapper
```

The exact invocation below has been run with `--dry-run` and plans 26 receipts in rank order;
the same invocation without `--allow-sh` is refused. **No shell hook has fired for real and no
`mix ash.*` task has been executed** — "verified" here covers the plan and the refusal gate,
nothing more. Evidence: [DRY-RUN-RECEIPT.md](DRY-RUN-RECEIPT.md) Steps 2–5.

## Scope note

This is the harness design that ticket 02's Tier-1 Ash-task matrix actually executes against
ticket 01's `test/fixtures/book_library/` fixture (ticket 01 is DRY-RUN VERIFIED; ticket 02
remains PLANNED/NOT STARTED — see `00-OVERVIEW.md`). This ticket's job is the invocation shape: ontology, query, frontmatter,
CLI, and the negative-path note — not the matrix content itself (ticket 02) or the two-run
idempotency protocol's pass/fail evidence (ticket 04, which consumes this ticket's invocation
verbatim).

## Mode decision: `sh_after:`/`--allow-sh`, not `mode: file`

Already decided this session, restated here as this ticket's load-bearing premise. This repo
has two real EEx-template actuation modes:

1. **`mode: file`** — the template hand-renders a full Elixir module (e.g.
   `test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex`). For an Ash domain/resource this
   means re-implementing what `mix ash.gen.domain`/`mix ash.gen.resource` already do — and
   doing it worse: `domain.ex.eex`'s own moduledoc documents that it produces the module file
   but does not wire `config.exs`'s `ash_domains:` list, a gap the real Igniter task closes for
   free via AST-aware editing (`deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex`, 91 lines).
2. **`sh_before:`/`sh_after:` frontmatter** — shells a real command via `System.cmd`, gated
   behind `--allow-sh` (schema key `lib/mix/tasks/ggen_igniter.sync.ex:236`, help text
   `lib/mix/tasks/ggen_igniter.sync.ex:709`, refusal gate `check_allow_sh!/3` around line 1161).
   Verified real end-to-end in `test/ggen_igniter_sync_sh_hooks_test.exs:71`, whose `run/1`
   helper is exactly `System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)` — the
   same shape this ticket's `sh_after:` lines reuse.

**Decision: mode 2 for every Tier-1 Ash task.** `ash.gen.domain` and `ash.gen.resource` (and
the rest of the Tier-1 list) are themselves real Igniter tasks doing correct AST-aware work
(`config.exs` editing, domain resource-reference registration). Re-implementing that in an EEx
template duplicates it, worse, per the `domain.ex.eex` gap above. `sh_after:` calls the real
task instead of re-deriving its output.

## Ontology shape

**Recommendation: extend `test/fixtures/ash-lifecycle-pack`'s existing `alp:` vocabulary**
rather than mint a new one, scoped by adding a new class (working name `alp:AshTierTask`) for
this ticket set's rows, distinct from whatever `alp:` classes the lifecycle-pack fixture
already uses for its own `mode: file` rows. Rationale: `alp:` is already the real, loaded
vocabulary this repo's `GgenIgniter.Ontology.load!/1` path exercises for Ash-shaped fixtures;
a second parallel vocabulary would duplicate prefix/namespace bookkeeping for no real
semantic gain, and ticket 01's `book_library` fixture is a genuine Ash project (unlike
`ash-lifecycle-pack`, which per this ticket set's grounding notes has no `mix.exs` and is
never compiled against a real `ash` dep) — reusing `alp:` keeps the two fixtures'
vocabularies comparable rather than accidentally divergent. **Resolved:** the
`alp:AshTierTask` individuals live in a new file, `test/fixtures/ash_tier_matrix_pack/ontology.ttl`
(a sibling pack, not inside `book_library/` and not appended to the lifecycle-pack file), using
the same `alp:` prefix `<http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>`. It holds
exactly 26 individuals with `alp:rank` 1..26 and, beyond the four properties sketched below,
three more per row: `alp:destructive`, `alp:idempotencyMechanism`, and `alp:specDeviation`
(the last records, per row, every difference from ticket 02's literal args and the `deps/`
file:line forcing it — see the receipt's "Repairs applied" §1–2).

## SPARQL query shape

One row per Tier-1 task. The real query, `test/fixtures/ash_tier_matrix_pack/gates/010_ash_tier_task_query.rq`
(26 rows — ticket 02's matrix has 26 rows, not the 28 names listed in `00-OVERVIEW.md`'s
Tier-1 prose: `ash.migrate` and `ash.rollback` have no row of their own in ticket 02, which
carries only the `ash_postgres.migrate`/`ash_postgres.rollback` rows; the pack follows ticket 02.
Two further task-name differences from ticket 02's literal, both forced by what exists in
`deps/` and recorded in `alp:specDeviation`: row 20 is `ash.generate_policy_chart` (singular;
only `deps/ash/lib/mix/tasks/ash.generate_policy_chart.ex` exists) and row 23 is `ash.reset`
(no `ash_postgres.reset` task exists in `deps/ash_postgres/lib/mix/tasks`)):

```sparql
PREFIX alp: <http://seanchatmangpt.github.io/packs/ash-lifecycle-pack#>
SELECT ?module_name ?mix_task ?mix_args ?rank ?destructive ?idempotency_mechanism ?spec_deviation WHERE {
  ?task a alp:AshTierTask ;
        alp:moduleName           ?module_name ;
        alp:mixTask              ?mix_task ;
        alp:mixArgs              ?mix_args ;
        alp:rank                 ?rank ;
        alp:destructive          ?destructive ;
        alp:idempotencyMechanism ?idempotency_mechanism ;
        alp:specDeviation        ?spec_deviation .
}
ORDER BY ?rank
```

**`ORDER BY` on the oxigraph engine — resolved by observation, not by reading.** The concern
was that this repo's oxigraph-backed engine (`GgenIgniter.Query.Oxigraph.run/2`) is a different
SPARQL implementation from the Rust `ggen` CLI's engine referenced in
`docs/jira/v26.9.1/PARITY-VALIDATION.md`, so `ORDER BY` semantics could not be assumed to
transfer. The dry run answers it for this query: the 26 `planned: write` lines came out as
`01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26` — ascending,
contiguous rank order — under `(engine: oxigraph, 1 query, 26 total row(s))`, reproduced
independently by three verifier passes with `ELIXIR_ERL_OPTIONS="+S 1"`. All seven variables
bound on all 26 rows (a row missing any property would have dropped from the join and the count
would be under 26). What this does **not** prove: stability of `ORDER BY` for ties (ranks are
unique here) or any strict-mode query-form rule beyond this one query.

## Template frontmatter shape

The sketch was `out: "receipts/{{module_name}}.json"` with a per-row
`sh_after: "mix {{mix_task}} ..."`. The real frontmatter, in
`test/fixtures/ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex`, keeps the
one-receipt-per-row shape but routes execution through a single runner script:

```yaml
---
to: ".ash-validation-receipts/<%= rank |> to_string() |> String.pad_leading(2, \"0\") %>-<%= module_name %>-<%= mix_task %>.sh"
for_each: ash_tier_task_query
mode: file
sh_after: "sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh"
---
```

- `for_each` fans out one render per query row (existing mechanism, per
  `ggen_igniter.sync.ex`'s own help text) — observed: 26 `planned: write` lines.
- `to:` is a per-row receipt path (`.ash-validation-receipts/NN-<module>-<task>.sh`) so each
  Tier-1 task's command is individually inspectable — matches ticket 04's per-run, per-task
  evidence requirement. Each receipt body renders all seven query variables as a header plus
  the literal `mix <mix_task> <mix_args>` line (receipt Step 2b shows rows 3 and 22 rendered).
- `sh_after:` is one fixed command rather than the per-row `mix` line: the runner
  (`bin/run_pending_receipts.sh`) executes every not-yet-run receipt in rank order, serialized
  within one sync run via `.done`/`.failed` markers, and runs rows whose header says
  `# destructive: true` (22–26) inside a disposable `mktemp -d` copy of the fixture. The
  per-row `mix` command still flows from the ontology into the executed script; only the hook
  string is shared. The runner has been exercised standalone with three fake receipts (receipt
  Step 5); the real reactor→`sh_after:`→runner handoff has **not** fired (dry-run only).

**Working-directory decision, stated and justified**: the harness invocation runs `mix
ggen_igniter.sync` **from inside** `test/fixtures/book_library/` (i.e. `cd:` is the fixture
root), rather than running from `~/ggen_igniter`'s own root and having `sh_after:` `cd` into
the fixture via the shell command. Rationale: `mix ash.gen.domain`/`mix ash.gen.resource` are
real Igniter tasks that resolve and edit `config.exs` relative to the *invoking* project's
root (per `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex`'s real behavior) — running them from
inside `book_library/` means no relative-path translation is needed in the `sh_after:` command
line itself, matching `check_nif_compiles/0`'s `cd:`-explicit precedent
(`lib/mix/tasks/ggen_igniter.doctor.ex:815-833`, cited in `v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md`)
rather than reproducing that pattern's own explicit-`cd:` discipline via an embedded `cd &&`
shell idiom.

## Full CLI invocation (ticket 04's two-run protocol)

The exact command, the same one `test/fixtures/ash_tier_matrix_pack/README.md` documents under
"Exact invocation" (the README's fenced block under that heading, written with `\` line
continuations):

```text
cd test/fixtures/book_library && mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query --allow-sh
```

`test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh` wraps that same line (plus `"$@"`),
after removing `.ash-validation-receipts/` so run 2 re-renders and re-executes every receipt;
ticket 04 invokes the wrapper. Run twice, unmodified, against the same post-first-run fixture
state — the invocation ticket 04's idempotency protocol is defined against.

**What has actually been run** is that line with `--dry-run` appended (receipt Step 2), from
inside the fixture, with `ELIXIR_ERL_OPTIONS="+S 1"` in the environment:

```text
$ cd test/fixtures/book_library
$ mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
    --allow-sh --dry-run ; echo "dry-run exit=$?"
==> book_library
planned: write .ash-validation-receipts/01-BookLibrary.Catalog-ash.gen.domain.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
planned: write .ash-validation-receipts/02-BookLibrary.Catalog.Book-ash.gen.resource.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh
  ... (rows 03–25 in order; full 26-line preview in DRY-RUN-RECEIPT.md Step 2)
planned: write .ash-validation-receipts/26-BookLibrary.Repo-ash_postgres.squash_snapshots.sh; planned: run sh_after: sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh

Igniter:

    No proposed content changes!
  ... (engine: oxigraph, 1 query, 26 total row(s)) -- summary: planned to write 26 (via reactor)
dry-run exit=0
```

`grep -c '^planned: write'` = 26. After the run: `.ash-validation-receipts/` absent,
`lib/book_library/` and `priv/` absent, `find`-snapshot diff of the fixture tree before vs
after → exit 0 (identical). The only side effect is an empty `.ggen_igniter/` directory
(created by `GgenIgniter.Lock`, gitignored in the fixture). The non-dry two-run protocol has
**not** been performed; the 26 `mix` commands are planned, not executed.

## Negative path: refuse without `--allow-sh`

`check_allow_sh!/3` (`lib/mix/tasks/ggen_igniter.sync.ex`, around line 1161) already raises
`ArgumentError` whenever a template's `sh_before:`/`sh_after:` frontmatter is present and
`opts[:allow_sh]` is falsy, before any actuation — this general mechanism already has its own
real test coverage (`test/ggen_igniter_sync_sh_hooks_test.exs`). This ticket's job is
confirming that refusal path specifically for the Ash-task templates above (the same
invocation with `--allow-sh` omitted must raise, never silently no-op or partially actuate) —
not re-proving the gate mechanism itself, which is already covered.

**Confirmed by running** (receipt Step 4; reproduced by all three verifier passes):

```text
$ cd test/fixtures/book_library
$ mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query \
    --dry-run ; echo "negative exit=$?"
** (ArgumentError) ggen_igniter: refusing to sync -- ../ash_tier_matrix_pack/templates/ash_tier_task_receipt.sh.eex declares sh_after: "sh ../ash_tier_matrix_pack/bin/run_pending_receipts.sh" in its frontmatter. ... Nothing was actuated this run. Pass --allow-sh to explicitly opt in and run this sync with shell hooks enabled.
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:1166: Mix.Tasks.GgenIgniter.Sync.check_allow_sh!/3
    (ggen_igniter 26.9.3) lib/mix/tasks/ggen_igniter.sync.ex:787: Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3
negative exit=1
```

`grep -c '^planned:'` on that log = 0; `.ash-validation-receipts/` not created; fixture tree
unchanged. What remains open for this section: the refusal is shown by a real command run, not
yet asserted by an ExUnit test in this repo's `test/` tree (ticket 04's protocol-level
checkbox stays unchecked).

## See also

- `DRY-RUN-RECEIPT.md` — the real transcript behind this ticket's DRY-RUN VERIFIED status.
- `00-OVERVIEW.md` — index, charter, and the full Tier-1/Tier-2 task lists.
- `01-BOOK-CASE-STUDY-FIXTURE.md` — the `test/fixtures/book_library/` real Ash project this
  ticket's harness runs against.
- `02-ASH-TASK-VALIDATION-MATRIX.md` — the row content (module names, args, rank) this
  ticket's query shape is written against; per-row deviations from its literal args are
  recorded in `ontology.ttl`'s `alp:specDeviation`.
- `04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md` — consumes this ticket's CLI invocation
  (via `bin/matrix_run.sh`) for its pass/fail evidence.
- `test/fixtures/ash_tier_matrix_pack/README.md` — runner/serialization/deviation rationale.
- `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` — the `cd:`-explicit,
  typed-return subprocess-shellout precedent this ticket's working-directory decision follows.
