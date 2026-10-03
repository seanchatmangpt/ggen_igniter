# Explanation: why ggen_igniter has four engines, a manifest, and a receipt

`ggen_igniter` is a build-time generator: it keeps generated Elixir
synchronized with an RDF/Turtle ontology as that ontology evolves —
including destructive evolution (renames, removals). Three design decisions
explain most of its shape.

## Why four SPARQL engines instead of one

A generated file is only as trustworthy as the query result it was rendered
from. The repo learned this empirically: the pure-Elixir `sparql` hex
package (v0.3.12) returned an `ORDER BY` query in reverse row order —
silent corruption for any `--for-each` template that assumes row order. The
response was not "pick the best engine" but "make engine identity explicit
and comparable" (ADR-0001, ADR-0008).

So `GgenIgniter.Engine` (`lib/ggen_igniter/engine.ex`) is a two-callback
behaviour — `prepare!/2` for once-per-run setup, `run/2` for one query —
with four registered implementations: the native oxigraph NIF (default,
since v26.8.27), the `sparql` hex package, a remote QLever endpoint, and
the graphlaw WebAssembly module (`lib/ggen_igniter/engine/graphlaw.ex`,
hosted in-process by `wasmex` over a WASI store, artifact shipped at
`priv/graphlaw_wasm.wasm`).

The graphlaw engine's purpose is *differential court*: it shares no code
with oxigraph or `sparql`, so `--engine oxigraph,graphlaw` can require the
two identities to agree on row-set and refuse the run (nonzero exit) when
they do not — correctness decoupled from any single engine's reliability.
`GgenIgniter.EngineRegistry.run_all/4` fans the query out concurrently,
captures each engine's rows, errors, and elapsed time into a
`GgenIgniter.EngineComparisonReport`, and treats one engine's crash as
data (`status: :error`) rather than aborting the others. The first named
engine stays the primary whose rows actually render — comparison mode is
strictly additive to a normal run.

## Why a manifest AND a receipt

Two durable records, deliberately different
(`lib/ggen_igniter/manifest.ex`, `lib/ggen_igniter/receipt.ex`):

- The **manifest** (`.ggen_igniter/manifest.json`) is the current-state
  cache: what this recipe's most recent successful run wrote, keyed by the
  `(template, out_template)` recipe pair. Comparing a new run's planned
  output paths against it yields `stale = old_paths - new_paths` — the
  mechanical signature of a rename or removal upstream in the ontology,
  handled by `--on-stale refuse|prune|preserve`.
- The **receipt** (`.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`) is the
  history: one JSON line per admitted attempt, on every path, success or
  failure. The manifest alone loses real evidence — when verification
  fails after files were written and undo restores the prior bytes, the
  manifest never moved and the files are back, yet disk was written twice.
  The receipt keeps that operational history with a five-atom standing
  vocabulary: `:alive`, `:refused`, `:compensated`, `:build_broken`,
  `:compensation_failed`. Only `:alive` advances the manifest;
  `:compensation_failed` is the one standing treated as an
  operator-facing incident rather than a routine self-healed failure.

`mix ggen_igniter.replay` closes the loop: it recomputes current hashes of
exactly what a receipt recorded (output files via `post_run_hash`, the pack
ontology via `metadata["graph_hash"]`, a tracked work order via
`metadata["work_order"]`) and reports per-category drift — and it refuses
to fabricate comparisons for categories the schema never baselined
(template files, engines, run config).

## Why fail-open gates get a fail-closed twin

`mix ggen_igniter.sync` scores a gate as passing when it returns at least
one row. For conjunctive SELECT gates that rule fails open: deleting one
triple (e.g. `amp:primaryKeyKind`) drops a gate from 2 rows to 1 while
other gates still pass, so an individual silently vanishes from the
generated output — and a typed refusal can silently become a skip
(`lib/mix/tasks/ggen_igniter.verify.ex` moduledoc, which documents three
measured instances of exactly this).

`mix ggen_igniter.verify` is the complementary, fail-closed surface:
inverted `verify/*.unbound.rq` queries whose pass condition is zero rows,
plus per-gate cardinality contracts. It lives in `verify/`, not `gates/`,
so it is invisible to `GgenIgniter.Pack.discover_queries/1`'s `gates/*.rq`
glob and can never inject `subject`/`missing_property` into a template
namespace.

## Why verify and refuse rather than warn

Everything machine-facing speaks one contract
(`lib/ggen_igniter/task_contract.ex`): five exit codes mapped to a standing
vocabulary (`ALIVE`/`REFUSED`/`UNKNOWN`/`UNSUPPORTED`/`BLOCKED`) and one
deterministic JSON envelope. A disagreement between engines, a stale
artifact, and a bad flag are different facts, so they get different exit
codes — a CI job can branch on the code alone. `sync --check` reuses the
dry-run pipeline so "is the committed tree in sync with the ontology?"
(`exit 4`, `BLOCKED`) is answered by the same decision procedure that would
have written the files, not a second, weaker one.

## Disclosed limits

- `inject: true` template frontmatter is a marker-based line splice, not an
  AST patch (ADR-0006).
- The reconciliation manifest closes the orphan-file gap only for the
  recipe's *own* tracked outputs; there is no cross-file stale-reference
  repair.
- The Reactor coordination path (`ReconcileReactor`, receipts written
  before manifest promotion, `undo/4` rollback) is real but opt-in via
  `config :ggen_igniter, use_reactor: true` — it is not the default path.
