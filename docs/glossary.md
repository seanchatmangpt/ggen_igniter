# Glossary

One canonical definition per term, pulled from the specialist docs that already
use it (cited per entry) — not invented for this page. Where a term in the
requested list is not this codebase's own literal vocabulary, that is stated
honestly rather than papered over with an invented definition.

## admission

The whole-plan, fail-closed check `GgenIgniter.Reactors.ReconcileReactor`'s
`:admit` step performs over the **entire** intended set of
create/replace/eval/delete items — before a single byte is written, not
per-item as writes happen. Refuses the whole run (never a partial refusal) on
a duplicate output-path collision between two targets, an unowned `:delete`
candidate, or a stale-path violation under `--on-stale refuse`. Only the
Reactor pipeline has an explicit admission step; `GgenIgniter.Reconcile.run/1`
and `Mix.Tasks.GgenIgniter.Sync`'s inline pipeline have no equivalent
whole-plan gate. See `docs/reference/reactor/steps.md`,
`docs/integrations/ggen/planning-boundary.md`.

## actuation

The act of a rendered template's content actually touching disk (or being
evaluated, under `mode: eval`). The single filesystem-mutation-boundary step
is `:actuate` in the Reactor pipeline, and `GgenIgniter.Actuate`'s
`write_file!/3` / `inject_content!/5` / `eval_code!/2` functions in both
pipelines. Every step before actuation is a pure read or in-memory
computation; every step after it (`:verify`) only reads what actuation
already wrote. See `docs/reference/reactor/steps.md`,
`docs/integrations/igniter/safety.md`.

## artifact

A generated output file — the concrete thing `mode: file` actuation produces
on disk from a template/query pair. See "stale artifact" below for the
specific, load-bearing sense this term carries in the reconciliation model.

## Chicago test

A test following Chicago-school (classicist) discipline: real collaborators
(real files, real subprocesses, real SPARQL engines), state-based assertions
on real resulting state — never interaction-based mocking ("was this function
called") of a collaborator this codebase owns or can run in-process. Verified
in this repo by a real, re-run grep (`grep -rn "Mock\|mock(\|patch(\|monkeypatch"
test lib native`, exit code 1 — zero matches). See `docs/testing/chicago.md`.

## compensation

Reverting real, already-written files after a later pipeline step fails.
Implemented via Reactor's `undo/4` callback on the `:actuate` step (fires when
a **later** step, `:verify`, fails after `:actuate` already succeeded) and,
separately, `:actuate`'s own internal self-heal inside `run/3` (reverting a
partial write from its own mid-loop failure before ever returning an error).
Produces the `:compensated` or `:build_broken` receipt standing, with
`pre_run_hash == post_run_hash` as the checkable proof restoration was
genuine. Scoped to the opt-in Reactor pipeline only — the default
`GgenIgniter.Reconcile.run/1` pipeline has no compensation mechanism at all.
See `docs/reference/reactor/compensation.md`, `docs/reference/evidence/recovery.md`.

## controller

`GgenIgniter.Controller` — a real, opt-in `GenServer` that holds live
reconciliation state (`last_reconciliations`, keyed by caller-chosen
`pack_key`) **in its own process** across multiple `reconcile/3` calls,
answering "how many times has this recipe actually been reconciled, in this
process" without touching disk. Adds no reconciliation logic of its own —
it dispatches to `GgenIgniter.Reconcile.run/1` (default) or
`GgenIgniter.Reactors.ReconcileReactor.run/1` (opt-in, `use_reactor: true`).
Started only when a consumer sets `config :ggen_igniter, start_controller:
true` (default `false`). See `docs/operations/controller.md`.

## ggen

The real, external Rust project (`~/ggen` /
[seanchatmangpt/ggen](https://github.com/seanchatmangpt/ggen)) this project
bootstraps: ontology-to-code generation via ontology load → SPARQL query →
template render → guarded write. In `ggen_igniter`, this role is fulfilled by
this repo's **own** `GgenIgniter.Ontology`/`Engine`/`Render`/`Actuate` spine —
a from-scratch Elixir port of the same pipeline shape, not a runtime
dependency on (or shell-out to) the real `ggen` binary. One real Rust
component *is* embedded: a Rustler NIF wrapping `ggen`'s own
`ggen-graph-wasm` oxigraph query engine, used by the default `--engine
oxigraph`. See `docs/integrations/ggen/semantic-compilation.md`,
`docs/architecture/overview.md`.

## Igniter

The `igniter` hex package (a real, unconditional `mix.exs` dependency). Both
`mix ggen_igniter.sync` and `mix ggen_igniter.doctor` `use Igniter.Mix.Task`
(CLI-task composition/plumbing) and call `Igniter.add_notice/2`. `ggen_igniter`
does **not** use Igniter's AST-mutation API (`Igniter.Project.Module`,
`Igniter.Code`, `Sourceror.Zipper`-based structural patching) anywhere —
confirmed by a real grep with zero code matches. See
`docs/integrations/igniter/project-actuation.md`.

## manifest

`GgenIgniter.Manifest` — the current-state cache at
`<base_dir>/.ggen_igniter/manifest.json`, atomic-rename-persisted, keyed by
the `(template_path, out_template)` **recipe** identity (deliberately not
ontology path or pack name — see "reconciliation" below). Records what a
recipe's most recent **successful** (`:alive`) run actually wrote; it is not a
history. Consulted and updated by `Mix.Tasks.GgenIgniter.Sync`'s inline
pipeline and by `ReconcileReactor`'s own `observe_prior_manifest`/
`finalize_evidence` steps — never by `GgenIgniter.Reconcile.run/1`, which has
zero manifest awareness. See `docs/reference/reconciliation/manifest.md`.

## manufacturing plan

Not this codebase's own literal term — its real equivalent is
`GgenIgniter.PendingActuation`, the in-memory intermediate representation the
Reactor pipeline's `:render` step builds: one `%PendingActuation{}` struct per
intended output (create/replace/eval, plus one per stale-prune delete
candidate), carrying `operation`, `previous_hash`/`desired_hash`, `ownership`,
and `desired_content`. This is what lets `:admit` reason about the **full**
intended delta before a single byte is written — a real deferred-actuation
plan, not a bare rendered-text map. Modeled on (not calling) the real Rust
`ggen`'s own `PendingWrite`/`SyncReport` IR. Only the Reactor pipeline builds
this plan; `GgenIgniter.Reconcile.run/1` and the CLI's inline pipeline actuate
directly with no intermediate plan representation. See
`docs/integrations/ggen/planning-boundary.md`.

## ontology

The RDF/Turtle input file describing the domain to generate from — loaded via
`GgenIgniter.Ontology.load!/1` (`RDF.Turtle.read_file!/1`, from the `rdf` hex
package) into an in-memory `%RDF.Graph{}`, then queried via one of three
SPARQL engines. See `docs/integrations/ggen/semantic-compilation.md`.

## pack

A directory following the `priv/ggen/<pack-name>/{ontology.ttl, gates/*.rq,
templates/*.{eex,tmpl}}` convention, resolved by `GgenIgniter.Pack` (a pure
helper, no Igniter dependency) so `--ontology`/`--query`/`--template` don't
need to be repeated on every invocation. Selected via `--pack NAME` (resolves
`priv/ggen/NAME/`), `--pack-dir DIR` (uses `DIR` directly), or `--pack
NAME:TEMPLATE_STEM` (disambiguates a multi-template pack). Can also be
fetched from a `github:`/`hex:` marketplace source via
`GgenIgniter.Pack.fetch_pack!/2` (a real, tested library function with no CLI
flag wired to it yet). See `docs/reference/cli/packs.md`,
`docs/integrations/ggen/packs.md`.

## projection

Used precisely in one place in this codebase: `mix ggen_igniter.doctor`'s
check 17 treats `mix.exs`'s `version:` string literal as **a projection of**
this project's real, observed versioning convention — `CHANGELOG.md`'s
topmost `## vX` heading, not an independently maintained field — reporting
`MATCH`/`MISMATCH` rather than trusting `mix.exs` as its own source of truth.
See `docs/reference/cli/doctor.md`.

## Reactor

The `reactor` hex package (a real, unconditional `mix.exs` dependency, used
only at the config level as opt-in). `GgenIgniter.Reactors.ReconcileReactor`
is a plain `use Reactor` module — explicitly **not** `Ash.Reactor` — so
`ggen_igniter` stays usable without Ash. It is the real, tested **target**
coordination pipeline (observe → load → resolve → query → render → admit →
actuate → verify → finalize evidence), reachable only when a consumer sets
`config :ggen_igniter, use_reactor: true` (default `false`). See
`docs/reference/reactor/overview.md`, `docs/integrations/ash/reactor.md`.

## receipt

`GgenIgniter.Receipt` — a durable, append-only record of **one admitted
reconciliation attempt**, one JSON line per attempt regardless of outcome, at
`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`. Carries one of four
closed-set standings (see "standing"), `pre_run_hash`/`post_run_hash`, the
real touched `files`, and an OCEL-shaped `events` list. Written **only** by
`GgenIgniter.Reactors.ReconcileReactor.run/1` — the default pipeline and the
CLI's inline pipeline never write one. See
`docs/reference/evidence/receipts.md`.

## reconciliation

Comparing a recipe's prior manifest-tracked output paths against the current
run's real new output paths to mechanically detect a rename or removal
upstream in the ontology (`stale = old_paths - new_paths`,
`Manifest.stale_paths/2`), then applying one of three named policies
(`--on-stale refuse|prune|preserve`). This is what turns `mix
ggen_igniter.sync` from a stateless generator into a stateful reconciler.
See `docs/reference/reconciliation/manifest.md`,
`docs/reference/reconciliation/stale-artifacts.md`.

## standing

`GgenIgniter.Receipt.standing/0` — a closed set of exactly four atoms
(`:alive`, `:refused`, `:compensated`, `:build_broken`); `Receipt.new/1`
raises `ArgumentError` on any other value. `:alive` = succeeded, manifest
advanced. `:refused` = fail-closed refusal before any actuation, nothing
touched disk. `:compensated` = files were written, verification failed for a
non-compile reason, undo restored prior bytes. `:build_broken` = same shape as
`:compensated`, but specifically because the generated content itself does
not compile. Assigned only by `ReconcileReactor.run/1`; the default pipeline
has no standing concept at all (a failure there is a raised exception). See
`docs/reference/evidence/standing.md`.

## stale artifact

A real, on-disk file that a **prior** run of a given `(template,
out_template)` recipe wrote (per that recipe's manifest entry) that the
**current** run does not write — the mechanical signature of a rename or
removal upstream in the ontology. Computed as
`Manifest.stale_paths(old_entry, new_paths)`. See
`docs/reference/reconciliation/stale-artifacts.md`.

## semantic delta

Not this codebase's own literal phrase — its real equivalent is the stale
path set (`Manifest.stale_paths/2` = old outputs minus new outputs) at the
default pipeline's path-set-vocabulary layer, and `PendingActuation`'s
per-item `previous_hash`/`desired_hash`/`plan_unchanged?/1` comparison at the
Reactor pipeline's richer IR layer — the mechanically-computed difference
between what a recipe previously produced/owned and what the current
ontology-driven run now intends. See
`docs/reference/reconciliation/destructive-evolution.md`.

## semantic compiler

`ggen_igniter`'s own ontology-load → SPARQL-query → EEx-render → guarded-write
pipeline — the "Semantic Compilation Pipeline" — implemented entirely in
Elixir as a from-scratch port of the real Rust `ggen`'s pipeline shape
(sharing no code with it, except for one embedded Rust NIF: the default
oxigraph query engine). See `docs/integrations/ggen/semantic-compilation.md`.

## autonomic software manufacturing

The paradigm realized by `ggen_igniter`: closed-loop software generation and reconciliation where formal knowledge (RDF ontologies) compiles deterministically into verified, self-healing Elixir project state with zero unmanaged drift, fail-closed admission, automated compensation, and persistent audit standing.

## See also

- `docs/status.md` — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status of every
  capability named above
- `docs/index.md` — full documentation map
- `docs/architecture/overview.md` — the ownership table these terms compose
  into (ggen/Igniter/Ash/Reactor/OTP/Controller/Manifest/Receipt)
