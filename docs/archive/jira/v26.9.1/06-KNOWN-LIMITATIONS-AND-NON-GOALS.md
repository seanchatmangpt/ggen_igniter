# Known limitations and explicit non-goals for the fortune5-ready installer

## Status (updated after real implementation)

No status change needed — this was always a scope-boundary document, not an implementation
ticket with acceptance bullets of its own. Confirmed after the real gi01–gi05 implementation run
(`/tmp/full_results.json`) that its stated non-goals were honored: no general
ggen-core pack-dependency-resolution algebra was built (non-goal 1), `PackComposer`/
`DependencyGraph` were not resurrected (non-goal 2), and `~/beam4pm` itself was not touched by
this work stream (non-goal 4) — the only interaction with beam4pm across the whole run was a
read-only scratch copy of its `ggen.toml`/`ontology.ttl`/`templates`/vendored submodule, built
under `~/.cache/tmp/gi-parity-beam4pm` for the parity-validation stage, confirmed explicitly in
`full_results.json`'s `parity` evidence ("read-only scratch copy of beam4pm's actual ggen.toml/
ontology.ttl/templates/vendor ... ~/beam4pm itself was never modified").

Scope note: this file governs the **fortune5-ready bundle installer** work stream in
this same `docs/jira/v26.9.1/` directory (tickets 01–05: the schema-dispatch
requirement, the bundle-manifest design, `mix ggen_igniter.fortune5_ready`, and the
pack-portability dependencies). It does not govern the *other*, differently-scoped
v26.9.1 work stream in `~/ggen_igniter/docs/v26.9.1-requirements.md` (the process-
mining/OCEL manufacturing-pack expansion release — see that document's own "Release
Theme" section). Both happen to carry the version string `v26.9.1`; they are
independent work streams. See the "See Also" section below for both cross-references.

This is a scope-boundary document, not a story with acceptance bullets — in the same
spirit as this repo's own README "Known Limitations" section, which this repo's
`CLAUDE.md` directs a reader to check before assuming a capability exists. Each item
below states what this work stream will **not** do and cites the real, verified
finding that makes it a deliberate non-goal rather than an oversight.

## 1. No general ggen-core pack-dependency-resolution algebra

This work does not build a general, ggen-core-level pack-to-pack dependency
resolution mechanism (a `[dependencies]` field in `pack.toml`, automatic transitive
pulls, cycle detection wired into a CLI verb). The bundle manifest that
`mix ggen_igniter.fortune5_ready` reads from is a **curated, hand-maintained list of
pack references**, not automatic resolution over a dependency graph.

Reason: `~/ggen/docs/jira/v26.9.1/01-PACK-COMPOSITION-GAP.md` is the source finding
that ggen core has no such mechanism today — `pack.toml`'s schema is closed
(`#[serde(deny_unknown_fields)]` on both `PackToml` and `PackMeta`,
`crates/ggen-engine/src/pack.rs` lines 70–93 at that repo's audited HEAD) and carries
no `dependencies`/`requires`/`packs` field. Zero of the ~150–207 packs in the
marketplace corpus use a `[dependencies]` table. Building that mechanism is out of
scope for an installer feature in a consumer-side tool (`ggen_igniter`); it would be
a ggen-core change, tracked (as aspirational design work only) in that repo's own
`docs/thesis/09-pack-algebra.md`, not here.

## 2. No resurrection of the dead `PackComposer`/`DependencyGraph` Rust subsystem

This work does not wire up, extend, or otherwise resurrect
`ggen-marketplace::packs_registry`'s `PackComposer` (`composer.rs`) or
`DependencyGraph` (`dependency_graph.rs`) — a real, internally-coherent graph
algorithm (cycle detection, topological sort) that exists in that crate but is
unreachable from any CLI verb (per the same `01-PACK-COMPOSITION-GAP.md` finding:
`grep -rln "PackComposer" crates --include="*.rs"` returns exactly one file, no
caller in `ggen-cli`; the real pack-mutating commands `pack add`/`pack remove` each
take one `pack_id` string, never a list).

Reason: this is dead code in a different repo (`ggen-marketplace`), not something
`ggen_igniter`'s bundle installer owns or can safely make load-bearing without a
correctness review this work stream does not budget for. The curated bundle manifest
(non-goal 1) is the workaround adopted instead of reviving this subsystem.

## 3. Does not itself fix the two non-portable fortune5 packs

This work does not fix `fortune5-required-capabilities-pack`'s hardcoded
`../../../../crates/ggen-marketplace` path or `fortune5-testing-bblock-pack`'s
`crates/ggen-cli`/`target/debug/ggen` self-detection. Those defects are tracked
separately, in ggen's own `docs/jira/v26.9.1/02-FORTUNE5-REQUIRED-CAPABILITIES-
PORTABILITY.md` and `03-FORTUNE5-TESTING-BBLOCK-PORTABILITY.md`.

Consequence for this work stream: the bundle manifest may initially ship with only
`fortune5-architecture-pack` and `fortune5-deployment-blocks-pack` — the two packs
that are already portable to an arbitrary consumer project — until the portability
fixes for the other two land upstream. Adding them to the bundle manifest before that
fix lands would silently ship a pack known not to work outside `ggen-marketplace`'s
own repo, which this work stream declines to do.

## 4. Does not run or prove anything against beam4pm itself

This work does not execute `mix ggen_igniter.fortune5_ready` against `~/beam4pm`, and
makes no claim about the installed result working there. That end-to-end proof is
tracked separately in ggen's own `docs/jira/v26.9.1/06-BEAM4PM-TRIAL-AND-GATE-M2-
PREREQUISITE.md`.

That companion ticket also names a **hard, currently-live, unrelated blocking
prerequisite**, restated here because it directly bears on any future beam4pm trial of
this work: `~/beam4pm/scripts/gate_m2_check.sh` is destructively broken on a live run
today. Its delete-then-regenerate step deletes every `GENERATED by ggen`-marked file
(including `lib/beam4pm_ash.ex`, the 31 `Ash.Resource` modules the separate
`ggen_igniter`-engine leg manufactures) before confirming the regenerate step will
succeed; a `build_broken` outcome from the `ggen_igniter` regenerate call leaves those
files deleted and never recreated. An audited run of this left 320 files / 22,636
lines deleted in the beam4pm working tree, caught and reverted by hand with
`git checkout` in the session that found it — a real, reproducible defect, not a
hypothetical one. This must be fixed in `beam4pm` (atomic delete+regenerate per
manufacturing-engine leg, or a staged/temp-directory diff before ever touching the
working tree) before any beam4pm trial of the fortune5-ready installer can be trusted,
independent of anything built in this repo.

## 5. Does not close the wider 7-dimension Fortune-5-readiness gap

This installer wires generateable architecture and deployment-block scaffolding into
a consumer project — nothing more. It does not close beam4pm's own audited
Fortune-5-readiness gaps in the other dimensions that scaffolding cannot reach:
marketplace listing/discoverability, SOC2/pentest evidence, RBAC-scoped Kubernetes
runtime code, or the OCPM/simulation algorithm gaps documented in beam4pm's own
Fortune-5-readiness audit. Those remain open, tracked in beam4pm's own docs, and are
explicitly out of scope for `mix ggen_igniter.fortune5_ready`.

## See Also

- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the **other** v26.9.1 work stream in
  this same repo (process-mining/OCEL manufacturing-pack expansion: incremental DFG
  discovery, sensor-to-event streaming, inductive-miner discovery, token-replay
  conformance, OCEL2/EKG derivation, OLAP slice/dice, Chicago-style OTP fault
  injection packs) — same version string, independent scope, do not conflate the two.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — the source epic
  (stories GGEN-1801 through GGEN-1807) this file's own ticket set is the
  `ggen_igniter`-side implementation detail of.
- `~/ggen/docs/jira/v26.9.1/01-PACK-COMPOSITION-GAP.md` — the pack-dependency-
  resolution-gap finding behind non-goal 1.
- `~/ggen/docs/jira/v26.9.1/02-FORTUNE5-REQUIRED-CAPABILITIES-PORTABILITY.md` and
  `03-FORTUNE5-TESTING-BBLOCK-PORTABILITY.md` — the two pack-portability fixes behind
  non-goal 3.
- `~/ggen/docs/jira/v26.9.1/06-BEAM4PM-TRIAL-AND-GATE-M2-PREREQUISITE.md` — the
  beam4pm end-to-end trial ticket and the `gate_m2_check.sh` prerequisite behind
  non-goal 4.
- `~/ggen_igniter/CLAUDE.md` — this repo's real conventions: status vocabulary
  (IMPLEMENTED / PARTIAL_ALIVE / PLANNED), Chicago-school testing discipline (real
  collaborators, state-based assertions, no `Mock`/`patch`/`monkeypatch`), and the
  `Ontology.load!/1 -> Engine.run/2 -> Render.render/2 -> Actuate.write_file!/3`
  pipeline shape this work stream builds on.
