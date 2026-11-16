# Expert Review — Pragmatic Programmers Lens (Andy Hunt & Dave Thomas)

Architectural evaluation of `ggen_igniter` v26.11.10 from the perspective of *The Pragmatic Programmer*
authors Andy Hunt and Dave Thomas.

- **Review Date:** 2026-11-10
- **Target Release:** `ggen_igniter` v26.11.10 (`3487755919b4c919d132644f47b275f464d44a29`)
- **Toolchain Grounding:** `elixir 1.19.5`, `erlang 27`, `ash 3.33.11`, `igniter 0.8.4`, `graphlaw wasm`
- **Review Persona:** Authors of *The Pragmatic Programmer*. Relentless proponents of Orthogonality,
  DRY (Don't Repeat Yourself), Tracer Bullets, Design by Contract, Pragmatic Quality, and fixing
  Broken Windows immediately.

---

## Executive Summary & Stance

> "Tip 11: Don't Live with Broken Windows. Tip 17: Program Close to the Problem Domain.
> Tip 31: Design by Contract. Tip 34: Use Tracer Bullets to Find the Target. An ontology is the
> ultimate DRY artifact—provided your pipeline preserves orthogonality and respects contracts."

This review evaluated `ggen_igniter` against core pragmatic software engineering principles.
The architecture receives an **APPROVED** verdict. The repository demonstrates exceptional adherence
to DRY via RDF ontology grounding, clean pipeline orthogonality, robust tracer bullets, and
fail-closed contract enforcement.

---

## Section 1 — CONFIRMED Findings (Ranked)

### Majors

#### M1. Single Source of Truth & Radical DRY via RDF Ontology
- **Observation:** In `priv/ggen/ash-manufacture-pack/ontology.ttl`, domain resources, attributes,
  relationships, actions, and primary keys are declared once as RDF triples.
- **Pragmatic Assessment:** Every piece of business knowledge must have a single, unambiguous,
  authoritative representation. In `priv/ggen/ash-manufacture-pack/templates/manufacture.ex.eex:30-85`, generator arguments are
  derived directly from semantic facts:
  - `amp:isPublic true` -> `public` attribute modifier (line 34).
  - `amp:primaryKeyKind "uuid"` -> `--uuid-primary-key` (lines 57-63).
  - `amp:usesBaseResource true` -> `--base <module>` (line 83).
  Changing an attribute in `ontology.ttl` updates the Elixir resource, action definitions, and database migrations simultaneously without semantic duplication.
- **Standing:** `ALIVE`.

#### M2. Tracer Bullet Architecture in `book_library/`
- **Observation:** `test/fixtures/book_library/` implements a complete, functioning vertical slice
  from Turtle triples through SPARQL extraction, template rendering, Igniter AST composition, and Ecto
  migrations to real database CRUD tests (`test/fixtures/book_library/test/book_library/catalog/book_exec.exs:43-50`).
- **Pragmatic Assessment:** Tracer bullets build an immediate, runnable end-to-end path through the
  architecture, proving that the components integrate successfully before full-scale manufacturing.

#### M3. Orthogonal Pipeline Architecture
- **Observation:** In `lib/ggen_igniter/reactors/reconcile_reactor.ex:1-8`, the pipeline is decoupled into
  independent stages: `observe -> load -> resolve -> manifest admission -> SHACL admission -> query -> render -> admit -> actuate -> verify -> finalize evidence`.
- **Pragmatic Assessment:** Orthogonality ensures that changing one component does not ripple across
  unrelated areas. Standardizing on `GgenIgniter.Engine.Graphlaw` (`lib/ggen_igniter/engine.ex:9-24`)
  swapped the query engine without requiring changes to template rendering or file actuation.

#### M4. Design by Contract via SHACL and Frontmatter Shapes
- **Observation:** `lib/ggen_igniter/semantic_jira/shacl.ex:37-46` implements strict precondition and
  invariant enforcement. Unsupported SHACL constructs fail closed (`exit 1`) rather than silently skipping
  checks. Furthermore, `lib/ggen_igniter/frontmatter.ex:79-100` enforces `@enforce_keys [:to]` and raises
  an explicit `ArgumentError` when anchor combinations are ambiguous (lines 52-74).
- **Pragmatic Assessment:** Software that crashes early when preconditions fail is far easier to debug
  than software that silently attempts to proceed with invalid inputs.

---

### Minors

#### m1. Zero Tolerance for Broken Windows
- **Observation:** The project compiles with zero warnings under `mix compile --warnings-as-errors`
  (`mix.exs:22`), enforces strict Dialyzer type specifications with `@dialyzer {:no_return, ...}`
  explicitly justified (`lib/mix/tasks/ggen_igniter.doctor.ex:1-13`), and encapsulates upstream quirks
  as typed refusals rather than silent workarounds.

---

## Section 2 — REFUTED Findings

### R1. Refuted Claim: "Declarative RDF is too abstract compared to hand-written code"
- **Claim:** Writing Elixir code directly is simpler and faster than maintaining an RDF ontology and SPARQL queries.
- **Investigation:** Hand-written code violates DRY across domain models, JSON APIs, database schemas,
  and documentation. When domain rules evolve, hand-written code rots and introduces broken windows.
  Declarative RDF centralizes the single source of truth and guarantees all projections stay synchronized.
- **Verdict:** REFUTED.

---

## Section 3 — Expert Recommendations & Vision

1. **Expand the Tracer Bullet Corpus:** Introduce a second vertical slice demonstrating event-sourced
   domain logic.
2. **Compile-Time Contract Validation:** Leverage Spark DSL extensions or macros to validate frontmatter
   contracts at compile time.
3. **Pipeline Visualization Tooling:** Add a Mix task (`mix ggen_igniter.graph`) to output Graphviz/Mermaid
   diagrams of pipeline dependencies.

---

## Section 4 — What This Review Did NOT Check

- Cross-language code generation (Python or TypeScript targets).

---

## Section 5 — Evidence Ledger & Mechanical Citations

| Subject / Artifact | Exact Location | Finding / Invariant Verified | Standing / Result |
|---|---|---|---|
| Single source of truth ontology | `priv/ggen/ash-manufacture-pack/ontology.ttl:1-120` | Domain entities, attributes, and actions as RDF triples | `ALIVE` |
| Generator flag derivation | `priv/ggen/ash-manufacture-pack/templates/manufacture.ex.eex:30-85` | Derivation of flags from ontology facts | `ALIVE` |
| Tracer bullet CRUD test | `test/fixtures/book_library/test/book_library/catalog/book_exec.exs:43-50` | End-to-end execution of manufactured stack | Passed |
| Orthogonal pipeline spine | `lib/ggen_igniter/reactors/reconcile_reactor.ex:1-8` | Decoupled 10-step reconciliation reactor | `ALIVE` |
| Fail-closed SHACL validator | `lib/ggen_igniter/semantic_jira/shacl.ex:37-46` | Strict contract validation failing closed on unsupported shapes | Enforced |
| Frontmatter contract keys | `lib/ggen_igniter/frontmatter.ex:79-100` | Precondition enforcement for template target routing | Enforced |
| Overview charter | `00-OVERVIEW.md` | Master architectural overview and release charter | Verified |
| Idempotency methodology | `03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md` | Invariant verification and zero-diff proof | Verified |
