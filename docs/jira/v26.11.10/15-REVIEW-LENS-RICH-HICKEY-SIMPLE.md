# Expert Review — Rich Hickey Lens (Clojure Creator & Simplicity Advocate)

Architectural evaluation of `ggen_igniter` v26.11.10 from the perspective of Clojure creator
and author of *Simple Made Easy* Rich Hickey.

- **Review Date:** 2026-11-10
- **Target Release:** `ggen_igniter` v26.11.10 (`3487755919b4c919d132644f47b275f464d44a29`)
- **Toolchain Grounding:** `elixir 1.19.5`, `erlang 27`, `ash 3.33.11`, `igniter 0.8.4`, `graphlaw wasm`
- **Review Persona:** Creator of Clojure and Datomic, author of *Simple Made Easy*. Relentless
  advocate for simplicity (unbraided, uncomplected concepts) versus ease (familiarity, convenience).
  Insists on immutable values, pure data over syntax, clear separation between identity and state,
  and uncomplecting history from current working state.

---

## Executive Summary & Stance

> "Simple is not easy. Simple means unbraided, uncomplected, one concept at a time. Complecting data
> with code, query with actuation, or history with state is the primary source of software complexity.
> When you represent information as immutable data rather than classes or macros, you stop buying
> complexity you don't need."

This review evaluated `ggen_igniter` from the perspective of value semantics, data-driven design,
and conceptual uncomplecting. The architecture receives an **APPROVED WITH REPAIRS** verdict.
The clean separation between append-only history (`receipts.jsonl`) and current working cache (`manifest.json`),
alongside the modeling of actuation plans as pure immutable values (`%PendingActuation{}`), demonstrates
outstanding commitment to simplicity. One identified repair—transitioning line-anchored text splicing
to structural zipper transformations—remains to fully uncomplect code modification from layout formatting.

---

## Section 1 — CONFIRMED Findings (Ranked)

### Blockers (Resolved)

#### B1. Complecting History and Working State
- **Observation:** In earlier generator designs, execution history was intertwined with the working state cache. Receipts were only recorded upon successful manifest advance, making it impossible to audit failed attempts or understand intermediate states.
- **Resolution in ggen_igniter:** `lib/ggen_igniter/receipt.ex:22-44` explicitly uncomplects history from current state:
  > "Receipt vs. manifest -- two different durable records, on purpose. `GgenIgniter.Manifest` (`.ggen_igniter/manifest.json`) is the CURRENT-STATE cache: what does this recipe's most recent SUCCESSFUL run actually write, right now. It only ever advances on a real `:alive` standing... This module is the HISTORY: what was ATTEMPTED, every time, regardless of outcome."
- **Implementation:** History is written as an append-only JSONL stream (`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`), and `lib/ggen_igniter/reactors/reconcile_reactor.ex:60-100` guarantees that the receipt is persisted to disk before any cache promotion.
- **Standing:** `ALIVE`.

---

### Majors

#### M1. Line-Anchored Text Splice in `Actuate.inject_content!/5` Complects Formatting with Semantics
- **Observation:** In `lib/ggen_igniter/actuate.ex:24-28`:
  > "Igniter AST-patch actuation (a real `Sourceror`/`Igniter.Code`-based structural patch, as opposed to this module's line-anchored text splice) for incremental changes to an EXISTING file remains an explicit, disclosed follow-on -- not implemented this pass (see pack.toml)."
- **Hickey's Assessment:** Line-anchored splicing complects code semantics with line numbers, indentation, and trailing whitespace. While full file writes are atomic and safe via `File.rename!/2` (`lib/ggen_igniter/actuate.ex:31-54`), partial injection should be handled via functional zipper AST transformations (`Sourceror.Zipper`).
- **Status:** Disclosed follow-on, marked for upgrade.

#### M2. Pure Value Representation of Actuation Plans (`%PendingActuation{}`)
- **Observation:** In `lib/ggen_igniter/pending_actuation.ex:1-20`, what the `:render`/`:plan` phase of `ReconcileReactor` produces is not a bare string or an imperative I/O action, but an immutable `%PendingActuation{}` struct:
  > "...describing the FULL intended delta (identity, prior vs. desired content hash, the exact operation, ownership, provenance, and how to revert it)..."
- **Canonical Identity:** In `lib/ggen_igniter/pending_actuation.ex:22-42`, `canonical_target` is computed via `GgenIgniter.ArtifactIdentity.canonicalize/2` before evaluation, ensuring the `:admit` gate operates on canonical identity values without aliasing bugs.
- **Hickey's Assessment:** Exemplary uncomplecting. Planning is a pure function returning a value; admission is a pure predicate over that value; actuation is isolated I/O.

---

### Minors

#### m1. Closed Value Set for Receipt Standings
- **Observation:** In `lib/ggen_igniter/receipt.ex:45-86`, `standing` is strictly constrained to 5 closed atoms: `:alive`, `:refused`, `:compensated`, `:build_broken`, `:compensation_failed`.
- **Hickey's Assessment:** Treating standings as discrete enumerated values rather than open-ended string errors avoids ad hoc string parsing and complected control flow.

---

## Section 2 — REFUTED Findings

### R1. Refuted Claim: "RDF Turtle triples are needlessly complex compared to JSON/YAML configuration"
- **Claim:** JSON or YAML files are simpler and more developer-friendly than RDF Turtle syntax.
- **Investigation:** JSON and YAML complect document hierarchy with relational facts. Adding a relationship requires nesting or arbitrary string pointer conventions (`$ref`). RDF uncomplects domain entities, attributes, and relationships into universal open triples $(s, p, o)$, providing genuine relational simplicity.
- **Verdict:** REFUTED.

### R2. Refuted Claim: "Code generation should use interactive wizard prompts"
- **Claim:** Wizards improve usability by asking developers questions interactively.
- **Investigation:** Interactive prompts complect I/O with model transformation, destroying replayability, automated testing, and headless execution. Data-driven configurations preserve idempotency.
- **Verdict:** REFUTED.

---

## Section 3 — Expert Recommendations & Vision

1. **Complete Zipper Transition for AST Injections:** Eliminate line-anchored text splicing in `lib/ggen_igniter/actuate.ex` in favor of pure `Sourceror.Zipper` transformations.
2. **Treat All Work Orders and Receipts as Open Entity Maps:** Model Semantic Jira work orders and receipts using Datomic-style entity-attribute-value maps, enabling open extension without schema rigidity.
3. **Pure Functional Pipeline Compilation:** Ensure all pipeline phases between `load` and `actuate` remain 100% referentially transparent.

---

## Section 4 — What This Review Did NOT Check

- Clojure/JVM interoperability; audit was focused on Elixir data semantics and pipeline purity.

---

## Section 5 — Evidence Ledger & Mechanical Citations

| Subject / Artifact | Exact Location | Finding / Invariant Verified | Standing / Result |
|---|---|---|---|
| Uncomplecting history and state | `lib/ggen_igniter/receipt.ex:22-44` | Separate durable records for append-only history vs current cache | `ALIVE` |
| Receipt standing closed set | `lib/ggen_igniter/receipt.ex:45-86` | 5 closed atoms: `:alive`, `:refused`, `:compensated`, `:build_broken`, `:compensation_failed` | Enforced |
| Immutable actuation plan | `lib/ggen_igniter/pending_actuation.ex:1-20` | `%PendingActuation{}` representation of pure delta | `ALIVE` |
| Canonical identity evaluation | `lib/ggen_igniter/pending_actuation.ex:22-42` | `ArtifactIdentity.canonicalize/2` uncomplects target path from aliasing | Verified |
| Line-anchored splice disclosure | `lib/ggen_igniter/actuate.ex:24-28` | Explicit disclosure of text splice residue vs AST patches | Documented |
| Receipt-first ordering | `lib/ggen_igniter/reactors/reconcile_reactor.ex:60-100` | Receipt appended before manifest cache promotion | Guaranteed |
| Overview charter | `00-OVERVIEW.md` | Master architectural overview and release charter | Verified |
| Idempotency methodology | `03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md` | Verification protocol and value-based idempotency proof | Verified |
