# ggen_igniter v26.11.10 Production Release — Overview

Index charter and standings ledger for the `ggen_igniter` v26.11.10 production release.
This release shores up the codebase under CalVer `26.11.10`, formalizes the 5-expert architectural
evaluation suite across Ash, Elixir, BEAM concurrency, testing/audit, and release packaging,
verifies two-run tree idempotency and OCEL 2.0 telemetry projection, and prepares the package for
production distribution on Hex.pm.

- **Release Date:** 2026-11-10
- **Version:** `26.11.10`
- **Repo / Commit SHA:** `1a6e60d6fed9c2adb06a2c097bbc83e8529f007e`
- **Host Runtime:** Elixir 1.19.5, Erlang/OTP 27 [erts-15.2.2]
- **Core Dependencies (from mix.lock):** `ash 3.33.11`, `igniter 0.8.4`, `spark 2.7.3`, `ash_postgres 2.13.1`, `ecto 3.14.2`
- **Mechanical Citation Audit:** [bin/check_doc_citations.sh](bin/check_doc_citations.sh) (100% verified, 0 broken citations)
- **Machine-Readable Receipt:** [evidence/receipt.json](evidence/receipt.json)

---

## 1. Verified Standings Ledger

Every standing recorded below is derived from an observed, reproducible execution against the exact commit SHA `1a6e60d6fed9c2adb06a2c097bbc83e8529f007e`. In accordance with repository doctrine ($A = \mu(O^*), R = \text{receipt}(A)$), bare prose assertions are prohibited; each entry references verifiable evidence in this release suite.

| Standing | Result | What Established It | Evidence Citation |
|---|---|---|---|
| `COMPILATION_ALIVE` | `true` | `mix compile --warnings-as-errors --force` exited 0 with 0 warnings and 0 errors across 219 Elixir modules and the `ggen_graph_nif` Rustler crate | [01-RELEASE-SHORE-UP-AND-COMPILATION.md](01-RELEASE-SHORE-UP-AND-COMPILATION.md) |
| `TEST_SUITE_ALIVE` | `true` | Full ExUnit test suite executed cleanly: 20 doctests, 41 property tests, 1,763 tests passed, 0 failures, 5 skipped | [evidence/test_run.log](evidence/test_run.log) |
| `VERSION_CONTRACT_ALIVE` | `true` | CalVer consistency confirmed across `mix.exs` (`version: "26.11.10"`, `source_ref: "v26.11.10"`) and `CHANGELOG.md` (`## v26.11.10`) | `test/ws5_contracts/16_version_contract_test.exs` |
| `FLEET_RECEIPT_ALIVE` | `true` | Byte-for-byte identity of `priv/schema/fleet-receipt.v2.json` and sha256 digest `a2c7510b91e59410ae46415a5f95f9cf3913a5c0ac42f473fcb6c794edfe4def` | `test/ggen_igniter_fleet_receipt_conformance_test.exs` |
| `ASH_MANUFACTURE_ALIVE` | `true` | Upstream Ash/Igniter tasks driven via `Igniter.compose_task/4` without shelling out; zero handwritten Ash resources | [02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md](02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md) |
| `IDEMPOTENCY_ALIVE` | `true` | Two-run protocol verified: run 2 produces 0 file modifications, 0 new files, tree digest equality ($T1 == T2$), and `--check` exits 0 | [03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md](03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md) |
| `OCEL_PROCESS_ALIVE` | `true` | OCEL 2.0 telemetry logging verified; log sealed via `mix ggen_igniter.ocel.seal`; `beam4pm` conformance clean with 0 violations | [04-OBSERVABILITY-AND-OCEL-PROJECTION.md](04-OBSERVABILITY-AND-OCEL-PROJECTION.md), [evidence/conformance.json](evidence/conformance.json) |
| `HEX_PACKAGE_ALIVE` | `true` | `mix hex.build --unpack` successfully builds 501-file package tarball; `shipped_packs/0` enforces Ash-free packaging fence | [09-REVIEW-LENS-RELEASE-PACKAGING.md](09-REVIEW-LENS-RELEASE-PACKAGING.md), [evidence/hex_package_manifest.txt](evidence/hex_package_manifest.txt) |
| `HEX_RUNBOOK_ALIVE` | `true` | Step-by-step pre-flight, dry-run, publication, and verification runbook established for Hex.pm production release | [10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md](10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md) |

---

## 2. Master Ticket & Artifact Matrix

This directory (`docs/jira/v26.11.10/`) contains the complete 14-artifact release documentation suite:

| # | Artifact / Ticket | Purpose | Primary Evidence | Status |
|---|---|---|---|---|
| 00 | [00-OVERVIEW.md](00-OVERVIEW.md) | Release charter, standings ledger, DoD, and cross-reference index | Standings table & git HEAD | `ALIVE` |
| 01 | [01-RELEASE-SHORE-UP-AND-COMPILATION.md](01-RELEASE-SHORE-UP-AND-COMPILATION.md) | Requirement R1: Version sync, compilation hygiene, ExUnit execution ladder | [evidence/test_run.log](evidence/test_run.log) | `ALIVE` |
| 02 | [02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md](02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md) | Upstream Ash/Igniter task capability matrix, standing classifications, typed refusals | 21 generator capability evaluations | `ALIVE` |
| 03 | [03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md](03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md) | 5-part idempotency definition, two-run protocol, Igniter `--check` oracle | Phase 1 & 2 tree hashes ($T1 == T2$) | `ALIVE` |
| 04 | [04-OBSERVABILITY-AND-OCEL-PROJECTION.md](04-OBSERVABILITY-AND-OCEL-PROJECTION.md) | OCEL 2.0 telemetry logging, process mining validation, `ocel.seal` protocol | [evidence/conformance.json](evidence/conformance.json) | `ALIVE` |
| 05 | [05-REVIEW-LENS-ZACH-DANIEL-ASH.md](05-REVIEW-LENS-ZACH-DANIEL-ASH.md) | Zach Daniel maintainer review: Spark DSL, Igniter composition, base resources | Ranked findings (B, M, m) & refutations | `ALIVE` |
| 06 | [06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md](06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md) | José Valim core review: Idiomatic Elixir, Mix tasks, ExDoc extras collision avoidance | AST standards & Mix architecture | `ALIVE` |
| 07 | [07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md](07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md) | Joe Armstrong concurrency review: BEAM process isolation, Reactor compensation | Crash boundary & NIF isolation | `ALIVE` |
| 08 | [08-REVIEW-LENS-TESTING-AUDIT.md](08-REVIEW-LENS-TESTING-AUDIT.md) | Testing & Audit review: Chicago-style testing, anti-vacuity mutation, receipt schemas | ExUnit falsifiers & gate coverage | `ALIVE` |
| 09 | [09-REVIEW-LENS-RELEASE-PACKAGING.md](09-REVIEW-LENS-RELEASE-PACKAGING.md) | Release packaging review: Ash-free packaging fence, shipped_packs/0, tarball size | [evidence/hex_package_manifest.txt](evidence/hex_package_manifest.txt) | `ALIVE` |
| 10 | [10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md](10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md) | Requirement R3: Pre-flight checks, hex.build, dry-run, publish protocol | Step-by-step operational runbook | `ALIVE` |
| 11 | [RECEIPT.md](RECEIPT.md) | Formal Chatman Equation receipt ($R = \{\text{identity}, \text{authority}, \text{consequence}, \text{replay}, \text{standing}\}$) | Cryptographic hashes & commands | `ALIVE` |
| 12 | [bin/check_doc_citations.sh](bin/check_doc_citations.sh) | Executable bash citation verification tool | Mechanical exit code 0 | `ALIVE` |
| 13 | [evidence/](evidence/) | Machine-readable evidence repository | JSON schemas, manifests, test logs | `ALIVE` |

---

## 3. Five Expert Lenses Summary

To ensure maximum architectural integrity and compliance with ecosystem standards, this release underwent evaluation through 5 distinct expert lenses:

```
+--------------------------------------------------------------------------------------------------+
|                                    GGEN_IGNITER v26.11.10                                       |
+--------------------------------------------------------------------------------------------------+
          |                                   |                                   |
          v                                   v                                   v
+-----------------------+           +-----------------------+           +-----------------------+
|   Zach Daniel Lens    |           |    José Valim Lens    |           |   Joe Armstrong Lens  |
|      (Ash 3.x)        |           |    (Elixir Core)      |           |   (BEAM Concurrency)  |
| - Igniter composition |           | - Mix task behaviours |           | - Process isolation   |
| - Zero handwritten Ash|           | - Sourceror AST mods  |           | - Reactor compensation|
| - base_resources order|           | - ExDoc disambiguation|           | - NIF crash boundaries|
+-----------------------+           +-----------------------+           +-----------------------+
                    \                       |                       /
                     \                      |                      /
                      v                     v                     v
            +-----------------------------------+-----------------------------------+
            |        Testing & Audit Lens       |      Release Packaging Lens       |
            | - Anti-vacuity mutation gates     | - Ash-free Hex fence (shipped_packs)
            | - Chicago-style integration tests | - ExDoc collision-free extras     |
            | - Receipt schema verification     | - 501-file package manifest       |
            +-----------------------------------+-----------------------------------+
```

### 1. Zach Daniel (Ash Framework Creator / Maintainer Lens) — [05-REVIEW-LENS-ZACH-DANIEL-ASH.md](05-REVIEW-LENS-ZACH-DANIEL-ASH.md)
- **Verdict:** APPROVED WITH REPAIRS.
- **Core Stance:** Hostile to reimplementing Ash domain logic in templates. Insists on upstream generator composition via `Igniter.compose_task/4` and Spark DSL integrity.
- **Key Findings:**
  - Confirmed the two-phase manufacture protocol (`--phase base` then `--phase core`) is required to ensure `base_resources` config is loaded before child resources compile.
  - Confirmed typed refusal of `mix ash.gen.custom_expression` as `BUILD_BROKEN` due to upstream `opts[:arguments]` ArgumentError.
  - Validated that `refuse-handwritten-ash.sh` successfully prevents agents from introducing fragile handwritten Ash resources.

### 2. José Valim (Elixir Language Creator / Core Lens) — [06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md](06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md)
- **Verdict:** APPROVED.
- **Core Stance:** Enforces idiomatic Mix task architecture, robust Sourceror AST transformations, and ExDoc documentation hygiene.
- **Key Findings:**
  - Verified that ExDoc documentation configuration uses slugged path derivation (`filename: ...`) to eliminate basename collisions (e.g. multiple `README.md` files) that cause Hexdocs 404s.
  - Verified that Sourceror-based AST modifications preserve developer comments and source formatting during code patching.
  - Confirmed zero compiler warnings under Elixir 1.19.5 with `--warnings-as-errors`.

### 3. Joe Armstrong (BEAM Concurrency & Fault Tolerance Lens) — [07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md](07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md)
- **Verdict:** APPROVED.
- **Core Stance:** "Let it crash", process isolation, compensation on failure, and bulletproof native crash boundaries.
- **Key Findings:**
  - Confirmed that `GgenIgniter.Reactors.ReconcileReactor` provides rollback and error compensation when multi-step reconciliations fail mid-pipeline.
  - Verified that Rustler NIF (`native/ggen_graph_nif`) and Cranelift WASM runtimes operate within isolated process boundaries with serialized test execution (`async: false`, timeout: 600,000ms) to prevent scheduler starvation.

### 4. Testing & Audit Expert Lens — [08-REVIEW-LENS-TESTING-AUDIT.md](08-REVIEW-LENS-TESTING-AUDIT.md)
- **Verdict:** APPROVED.
- **Core Stance:** Skeptical auditor. "A check with no consumer or a gate with no witnessed refusal carries no bits."
- **Key Findings:**
  - Validated Chicago-style testing discipline: tests execute real `mix` subprocesses against real unpacked trees and real configuration files rather than mock doubles.
  - Verified anti-vacuity mutation testing: guard hooks and version contracts are proven to fail closed when provided invalid payloads or mutated files.
  - Confirmed machine-readable receipt validation against `priv/schema/fleet-receipt.v2.json`.

### 5. Release Packaging Expert Lens — [09-REVIEW-LENS-RELEASE-PACKAGING.md](09-REVIEW-LENS-RELEASE-PACKAGING.md)
- **Verdict:** APPROVED.
- **Core Stance:** Meticulous package engineer. Protects Hex tarball integrity, prevents build product leakage, and verifies dependencies.
- **Key Findings:**
  - Confirmed `shipped_packs/0` in `mix.exs:163-171` strictly excludes forbidden `ash-*` packs, shipping only the admitted `ash-manufacture-pack`.
  - Confirmed that compiled native artifacts (`priv/native/*.so`) are excluded from the Hex tarball, ensuring consumers compile via Rustler during installation.
  - Verified package manifest contains exactly 501 regular files totaling ~1.2MB compressed.

---

## 4. Definition of Done (DoD)

The v26.11.10 production release satisfies all acceptance criteria established in `ORIGINAL_REQUEST.md`:

### Requirement R1: Shore Up v26.11.10 Release
- [x] `mix.exs` specifies `version: "26.11.10"` and `source_ref: "v26.11.10"`.
- [x] `CHANGELOG.md` topmost release header is `## v26.11.10 (2026-11-10)`.
- [x] `mix compile --warnings-as-errors --force` passes with 0 warnings, 0 errors, exit 0.
- [x] Full test suite passes: 1,763 passed, 0 failures, 5 skipped (100% green).
- [x] Cranelift WASM concurrency timeout stabilized in `test/ggen_igniter_gall_ticket_test.exs`.
- [x] Fleet receipt schema drift resolved and synchronized with `priv/schema/fleet-receipt.v2.json`.

### Requirement R2: Release Documentation Suite
- [x] Master index charter established in `00-OVERVIEW.md`.
- [x] Technical specifications complete (`01`, `02`, `03`, `04`).
- [x] 5 expert lenses authored with ranked findings and maintainer vision (`05`, `06`, `07`, `08`, `09`).
- [x] Production publication runbook established in `10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md`.
- [x] Formal release receipt authored in `RECEIPT.md` and validated in `evidence/receipt.json`.
- [x] Mechanical citation verification tool `bin/check_doc_citations.sh` executed with exit code 0.
- [x] Machine-readable evidence suite populated (`evidence/receipt.json`, `evidence/conformance.json`, `evidence/hex_package_manifest.txt`, `evidence/test_run.log`).

### Requirement R3: Hex Packaging & Publishing Runbook
- [x] Package tarball verified via `mix hex.build --unpack` producing 501 clean files.
- [x] Ash-free packaging fence verified by `test/ggen_igniter_package_ash_free_test.exs`.
- [x] Comprehensive publication runbook detailing pre-flight checks, dry-run, and publication protocol delivered in `10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md`.

---

## 5. Non-Goals & Boundaries

To preserve strict scope boundaries, the following items are explicitly non-goals for this release:
1. **Downstream Application Migration:** Migrating external consumer applications (such as `xaas` or external client repos) to v26.11.10 is out of scope; this release delivers the shored-up core engine.
2. **Patching Upstream Ash Bugs:** Workarounds for upstream defects (e.g. `ash.gen.custom_expression` `opts[:arguments]` mismatch) are handled via typed refusals and recorded capabilities in the pack ontology, not by monkey-patching upstream dependencies.
3. **Database Migration Idempotency:** The idempotency guarantee established herein covers the **generated source tree** ($T1 == T2$); live database migration idempotency across repeated `ash.setup` or `ash_postgres.migrate` depends on external PostgreSQL state and is treated separately.

---

## 6. See Also

- `AGENTS.md` — Mandatory repository doctrine prohibiting agents from handwriting Ash resources.
- `CLAUDE.md` — Repository architecture, pipeline internals, verification gates, and worktree protocols.
- `docs/archive/jira/v26.9.8/` — Reference validation fixture and historical capability study.
- `docs/jira/v26.10.20/` — Lane-oriented execution documentation and staged landing pipeline.
- `docs/architecture/adr/ADR-001-reactor-coordination-kernel.md` — Reactor-based reconciliation architecture.
- `docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md` — Staged landing pipeline architecture.
