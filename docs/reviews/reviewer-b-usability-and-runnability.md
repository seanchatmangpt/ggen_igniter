# Adversarial Reviewer B: Usability & Runnability Audit Report

**Auditor:** Adversarial Reviewer B (New-User Usability & Runnability Reviewer)  
**Date:** 2026-08-27  
**Scope:** All Tutorials (`docs/tutorials/**`), Getting Started guides (`README.md`, `docs/tutorials/getting-started.md`), and CLI References (`docs/reference/cli/**`).  
**Evaluated Artifacts:**
- `docs/tutorials/getting-started.md`
- `docs/tutorials/first-pack.md`
- `docs/tutorials/first-reconciliation.md`
- `docs/tutorials/reactor-path.md`
- `docs/reference/cli/index.md`
- `docs/reference/cli/sync.md`
- `docs/reference/cli/doctor.md`
- `docs/reference/cli/engines.md`
- `docs/reference/cli/packs.md`
- `README.md` (Prerequisites, Quickstart & CLI sections)

---

## Executive Summary

This audit evaluated all developer onboarding paths, tutorials, and CLI references from the perspective of a newly onboarded engineer attempting to install, configure, troubleshoot, and execute `ggen_igniter` (v26.8.27).

### Key Findings
1. **Tutorial Runnability (HIGH QUALITY - CONFIRMED)**: The end-to-end tutorial workflows (`getting-started.md`, `first-pack.md`, `first-reconciliation.md`, and `reactor-path.md`) are syntactically sound, logically consistent, and accurately reflect single-row query flattening, multi-row fan-out (`--for-each`), and reconciliation lifecycle behaviors.
2. **Critical Reference Documentation Discrepancy (REFUTED)**: `docs/reference/cli/engines.md` (and `docs/reference/cli/sync.md:104`) claims that `--engine oxigraph` returns raw N-Triples term strings (angle-bracketed IRIs and quoted literals). In the actual codebase (`lib/ggen_igniter/query/oxigraph.ex:52-94` and `native/ggen_graph_nif/src/oxigraph_engine.rs`), term normalization was implemented directly in Rust, returning plain unquoted strings by default (`raw: true` is an opt-in). While the tutorials work because normalization is active, `engines.md` asserts an obsolete behavior.
3. **Prerequisite OTP Version Inconsistency (REFUTED)**: `README.md:42` states that `ggen_igniter` requires `Erlang/OTP 27+`, whereas `mix.exs:10`, `lib/mix/tasks/ggen_igniter.doctor.ex:150`, and `docs/tutorials/getting-started.md:15` require `Erlang/OTP >= 25`.
4. **CLI Schemas & Doctor Checklist Accuracy (CONFIRMED)**: All CLI flags in `docs/reference/cli/sync.md` and `docs/reference/cli/doctor.md` match the underlying `Igniter.Mix.Task` schema specifications byte-for-byte. The 17-item `doctor` checklist accurately maps to `Mix.Tasks.GgenIgniter.Doctor`.

---

## Audit Classification Ledger

Each evaluated claim is assigned one of three formal statuses:
- **`CONFIRMED`**: Verified against source code, NIF implementations, and runtime execution.
- **`REFUTED`**: Contradicted by the codebase or documentation discrepancy.
- **`UNVERIFIABLE`**: Cannot be verified definitively from the repository artifacts alone.

---

### Section 1: Prerequisites & Environment Setup

| ID | Document & Location | Stated Claim / Requirement | Reality / Code Reference | Status | Evidence & Impact |
|---|---|---|---|---|---|
| **PRE-01** | `docs/tutorials/getting-started.md:14` | Elixir `~> 1.17` required (tested on 1.17, 1.18, 1.19). | `mix.exs:10` (`elixir: "~> 1.17"`), `doctor.ex:149` (`Version.match?(elixir_version, "~> 1.17")`). | **CONFIRMED** | Accurate across project configuration and runtime doctor checks. |
| **PRE-02** | `docs/tutorials/getting-started.md:15` | Erlang/OTP `>= 25` required (tested on OTP 25, 26, 27, 28). | `doctor.ex:150` (`otp_major >= 25`). | **CONFIRMED** | Accurate for runtime doctor check. |
| **PRE-03** | `README.md:42` | "Requires Erlang/OTP 27+ and Elixir 1.17+". | `doctor.ex:150` allows `otp_major >= 25`. | **REFUTED** | Contradiction: README demands OTP 27+, whereas `doctor` passes OTP 25+. New developers on OTP 25/26 may be misled into unnecessary upgrades. |
| **PRE-04** | `docs/tutorials/getting-started.md:29-48` | Rust toolchain with `cargo` is required to compile `native/ggen_graph_nif` via Rustler. | `native/ggen_graph_nif/Cargo.toml`, `lib/ggen_igniter/native/graph_nif.ex` (`use Rustler`). | **CONFIRMED** | Accurate: `graph_nif.ex` triggers `cargo` build during library compilation. |
| **PRE-05** | `docs/tutorials/getting-started.md:59` | Package version dependency: `{:ggen_igniter, "~> 26.8.27"}`. | `mix.exs:9` (`version: "26.8.27"`), `CHANGELOG.md:3`. | **CONFIRMED** | Matches current project release version. |
| **PRE-06** | `docs/tutorials/getting-started.md:77-83` | Consumer projects with `only: [:dev, :test]` on `igniter` will hit dependency conflicts. | `mix.exs:66-80`, `doctor.ex:11-14` (Check #4), `doctor_fixes.ex`. | **CONFIRMED** | Accurately explains why `igniter` cannot be scoped to `dev/test` in consumer projects. |

---

### Section 2: CLI Interface & Flags Reference

| ID | Document & Location | Stated Claim / Requirement | Reality / Code Reference | Status | Evidence & Impact |
|---|---|---|---|---|---|
| **CLI-01** | `docs/reference/cli/sync.md:15-32` | `mix ggen_igniter.sync` schema has 15 options (`--ontology`, `--query`, `--template`, `--out`, `--engine`, `--store-id`, `--pack`, `--pack-dir`, `--for-each`, `--dry-run`, `--mode`, `--on-stale`, `--unless-exists`, `--skip-if`, `--manifest-dir`). | `lib/mix/tasks/ggen_igniter.sync.ex:185-201` (`schema: [...]`). | **CONFIRMED** | 100% schema parity. All flags, types, and defaults align. |
| **CLI-02** | `docs/reference/cli/doctor.md:17-25` | `mix ggen_igniter.doctor` schema has 6 options (`--pack`, `--pack-dir`, `--engine`, `--store-id`, `--hex-check`, `--fix`). | `lib/mix/tasks/ggen_igniter.doctor.ex:84-93` (`schema: [...]`). | **CONFIRMED** | Exact schema match. |
| **CLI-03** | `docs/reference/cli/doctor.md:21` | Doctor's `--engine` flag only acts on `"qlever"` to trigger check #8 and `:gno` dependency verification. | `doctor.ex:166` (`needs_gno? = opts[:engine] == "qlever"`), `doctor.ex:274`. | **CONFIRMED** | Subtle but exact operational disclosure confirmed. |
| **CLI-04** | `docs/reference/cli/sync.md:38-48` | Single-row query flattening: query returning exactly 1 row merges atom-keyed columns to top-level template bindings. | `sync.ex:1300-1305` (`build_bindings/2`). | **CONFIRMED** | Verified in both `sync.ex` and `GgenIgniter.Render`. |
| **CLI-05** | `docs/reference/cli/sync.md:72-100` | `--for-each <query>` iterates per row, flattens row bindings, and renders dynamic `--out` path template. | `sync.ex:620-637`, `sync.ex:1307-1310`. | **CONFIRMED** | Multi-row projection operates exactly as documented. |
| **CLI-06** | `docs/reference/cli/sync.md:176-216` | `inject: true` is driven strictly by template frontmatter; there is no `--inject` CLI flag. | `sync.ex:185-201` (no `:inject` in schema), `sync.ex:607-610`, `sync.ex:851-866`. | **CONFIRMED** | Injection correctly documented as frontmatter-only. |
| **CLI-07** | `docs/reference/cli/sync.md:218-234` | Write-safety precedence: 1) `--unless-exists`, 2) `--skip-if`, 3) byte-identical no-op, 4) write. | `lib/ggen_igniter/actuate.ex:42-70` (`write_file!/3`). | **CONFIRMED** | Evaluation hierarchy verified. |
| **CLI-08** | `docs/reference/cli/sync.md:247-289` | Stale handling policies: `refuse` (default, fail-closed), `prune` (`File.rm/1`), `preserve` (untrack & warn). | `sync.ex:665-667`, `sync.ex:731-778`, `lib/ggen_igniter/manifest.ex:88-102`. | **CONFIRMED** | Atomic behavior and defaults confirmed. |
| **CLI-09** | `docs/reference/cli/doctor.md:26-111` | Doctor executes a 17-item checklist; non-zero exit (`System.halt(1)`) if any check is `:error`. | `doctor.ex:105-135`. | **CONFIRMED** | All 17 checks and exit code semantics verified. |

---

### Section 3: SPARQL Engines & Term Normalization

| ID | Document & Location | Stated Claim / Requirement | Reality / Code Reference | Status | Evidence & Impact |
|---|---|---|---|---|---|
| **ENG-01** | `docs/reference/cli/engines.md:7-16` | Engine registry supports `"oxigraph"`, `"sparql"`, and `"qlever"`. | `lib/ggen_igniter/engine.ex:10-16` (`registry/0`). | **CONFIRMED** | Validated against engine registry. |
| **ENG-02** | `docs/reference/cli/engines.md:27` | Default engine is `--engine oxigraph` since v26.8.27. | `sync.ex:564` (`engine_name = opts[:engine] \|\| "oxigraph"`). | **CONFIRMED** | Verified in CLI pipeline. |
| **ENG-03** | `docs/reference/cli/engines.md:34-44` | Motivation for Oxigraph default: `sparql` hex package v0.3.12 has an `ORDER BY` row-reversal bug. | `lib/ggen_igniter/query.ex:15-38`, `test/ggen_igniter_oxigraph_engine_test.exs`. | **CONFIRMED** | Confirmed data-reversal bug documented and tested. |
| **ENG-04** | `docs/reference/cli/engines.md:48-54` | **Oxigraph Row Shape**: Claims `--engine oxigraph` returns raw N-Triples strings with `<...>` IRIs and quoted literals. | `lib/ggen_igniter/query/oxigraph.ex:52-94`, `native/ggen_graph_nif/src/oxigraph_engine.rs` (`normalize_term`). | **REFUTED** | The NIF normalizes terms to plain, unquoted strings by default. Raw N-Triples strings are only returned when `raw: true` is explicitly requested in `run/3`. `engines.md` contains stale documentation. |
| **ENG-05** | `docs/reference/cli/engines.md:86-88` | `--store-id` is required when `--engine qlever` is selected. | `lib/ggen_igniter/engine.ex:55` (`GgenIgniter.Engine.Qlever.prepare!/2`), `sync.ex:108-110`. | **CONFIRMED** | Fails closed with `ArgumentError` if `--store-id` is missing. |

---

### Section 4: Packs & Directory Conventions

| ID | Document & Location | Stated Claim / Requirement | Reality / Code Reference | Status | Evidence & Impact |
|---|---|---|---|---|---|
| **PCK-01** | `docs/reference/cli/packs.md:8-14` | Pack convention layout: `priv/ggen/<pack-name>/{ontology.ttl, gates/*.rq, templates/*.{eex,tmpl}}`. | `lib/ggen_igniter/pack.ex:16-35`. | **CONFIRMED** | Standard layout confirmed. |
| **PCK-02** | `docs/reference/cli/packs.md:37-44` | Gate query discovery strips leading numeric prefix (`^\d+_`) to form query binding name (e.g. `010_spec.rq` $\rightarrow$ `"spec"`). | `lib/ggen_igniter/pack.ex:72-84` (`discover_queries/1`). | **CONFIRMED** | Regex stripping and alphabetical sorting verified. |
| **PCK-03** | `docs/reference/cli/packs.md:54-79` | Multi-template disambiguation: `--pack NAME:STEM` selects `STEM` (filename up to first `.`). | `sync.ex:1119-1133` (`split_pack_template_stem/1`), `pack.ex:108-132`. | **CONFIRMED** | Template stem splitting verified. |
| **PCK-04** | `docs/reference/cli/packs.md:80-84` | `--pack-dir DIR` does NOT support `:STEM` syntax (must pass `--template` explicitly). | `sync.ex:1119-1133` (only checks `opts[:pack]`). | **CONFIRMED** | Operational boundary confirmed. |
| **PCK-05** | `docs/reference/cli/packs.md:90-117` | `Pack.fetch_pack!/2` is implemented as a library function but not wired to CLI flags (`PARTIAL_ALIVE`). | `lib/ggen_igniter/pack.ex:275-350`, `test/ggen_igniter_pack_fetch_test.exs`. | **CONFIRMED** | Honest status disclosure verified. |

---

### Section 5: Step-by-Step Tutorial Workflows & Usability

| ID | Tutorial & Step | Description & Code Sample | Usability / Runnability Audit | Status | Finding & Usability Assessment |
|---|---|---|---|---|---|
| **TUT-01** | `getting-started.md:145-214` | **Ad-Hoc Sync Tutorial**: Creates `spec.ttl`, `spec.rq`, `service.ex.eex`, runs `mix ggen_igniter.sync --ontology spec.ttl --query spec=spec.rq --template service.ex.eex --out lib/demo_app/health_check.ex`. | Input files and SPARQL query are syntactically valid. Single-row flattening binds `module_name`, `version`, `endpoint`. Output module `DemoApp.HealthCheck` renders cleanly. | **CONFIRMED** | **Runnable & Copy-Pasteable**. New developer can follow this step-by-step with 100% success. |
| **TUT-02** | `first-pack.md:39-191` | **Service Pack Tutorial**: Creates `priv/ggen/service-pack/` with `ontology.ttl`, `010_service.rq`, `020_endpoints.rq`, and `templates/service.ex.eex`. Runs `doctor --pack service-pack` and `sync --pack service-pack --out lib/demo_app/auth_service.ex`. | Turtle graph, SPARQL gate queries, and EEx template iterate cleanly over multi-row `endpoints` query while referencing flat `module_name` and `port`. | **CONFIRMED** | **Runnable & Copy-Pasteable**. Pack discovery and template rendering work as documented. |
| **TUT-03** | `first-pack.md:194-223` | **Template Stem Disambiguation**: Explains `--pack ash-lifecycle-pack:resource` and `--pack ash-lifecycle-pack:domain`. | Syntax matches `sync.ex` parser. | **CONFIRMED** | Clearly demonstrates multi-template handling. |
| **TUT-04** | `first-reconciliation.md:107-196` | **Destructive Evolution Walkthrough**: Initial generation of `user.ex`, zero-drift idempotent re-run, renaming ontology entity to `account`, demonstrating `--on-stale refuse` refusal and `--on-stale prune` cleanup. | Accurately depicts manifest diff calculation (`stale = old_paths - new_paths`) and atomic promotion. | **CONFIRMED** | Accurately explains how reconciliation manages file lifecycle. (Minor wording variation in error message noted below). |
| **TUT-05** | `reactor-path.md:23-66` | **Reactor Configuration & Invocation**: Configures `config :ggen_igniter, use_reactor: true` or calls `GgenIgniter.Reactors.ReconcileReactor.run/1`. | Code snippet matches `ReconcileReactor` API and returns `{:ok, receipt}` or `{:error, receipt}` with standing. | **CONFIRMED** | Programmatic and CLI configuration paths accurate. |
| **TUT-06** | `reactor-path.md:144-184` | **Rollback Compensation on Verify Failure**: Explains `undo/4` restoration when `mix compile --warnings-as-errors` fails in `:verify`. | Matches implementation in `lib/ggen_igniter/reactors/reconcile_reactor.ex`. | **CONFIRMED** | Failure semantics and receipt generation accurate. |

---

## Detailed Error Message & Return Type Discrepancies

While all error behaviors are conceptually and typologically accurate (`ArgumentError`, `RuntimeError`, `System.halt(1)`), several minor literal string differences exist between the tutorial text and the actual task outputs:

### 1. Stale Artifact Refusal Message
- **Tutorial Text (`first-reconciliation.md:172-176`)**:
  ```text
  ** (ArgumentError) reconciliation refused: stale output path(s) detected from previous run:
    - lib/app/user.ex
  Pass --on-stale prune to delete stale outputs, or --on-stale preserve to retain them.
  ```
- **Actual Code Output (`lib/mix/tasks/ggen_igniter.sync.ex:744-751`)**:
  ```text
  ** (ArgumentError) ggen_igniter: refusing to sync -- 1 stale output path(s) from a PRIOR run of this recipe ("priv/ggen/app/templates/resource.ex.eex" => "lib/app/<%= name %>.ex") are not written by this run (a rename or removal upstream in the ontology, most likely):

    - lib/app/user.ex

  Nothing was written this run (complete reconciliation or refusal before any partial actuation -- never a silent orphan). Re-run with --on-stale prune to really delete the stale path(s) above, or --on-stale preserve to leave them on disk (with a warning) and proceed.
  ```
- **Severity**: Low (informational). The exception type (`ArgumentError`) and remediation options (`--on-stale prune|preserve`) are identical.

### 2. Multi-Template Ambiguity Message
- **Tutorial Text (`first-pack.md:199-200`)**:
  ```text
  ** (ArgumentError) multiple templates found in priv/ggen/ash-lifecycle-pack/templates/ (domain.ex.eex, resource.ex.eex) -- pass :template explicitly or use --pack NAME:STEM
  ```
- **Actual Code Output (`lib/ggen_igniter/pack.ex:126`)**:
  ```text
  ** (ArgumentError) multiple templates found in priv/ggen/ash-lifecycle-pack/templates/ (priv/ggen/ash-lifecycle-pack/templates/domain.ex.eex, priv/ggen/ash-lifecycle-pack/templates/resource.ex.eex) -- pass --template explicitly
  ```
- **Severity**: Low (informational).

---

## New Developer Onboarding Experience Assessment

### Strengths
1. **Clear Mental Model**: The Diátaxis organization separates conceptual tutorials from operational references cleanly. A developer can quickly understand what GgenIgniter owns vs. what Igniter, Reactor, and Ash own.
2. **Deterministic Diagnostic Experience**: `mix ggen_igniter.doctor` and its `--fix` flag provide immediate reassurance to new developers, diagnosing missing Rust toolchains, misconfigured `only: [:dev, :test]` scopes on `:igniter`, and Ash domain registration issues.
3. **Copy-Pasteable Recipes**: All tutorial input snippets (`.ttl`, `.rq`, `.eex`) are syntactically valid and produce the exact expected `.ex` files when run with `mix ggen_igniter.sync`.
4. **Transparent Write-Safety & Stale Management**: The concept of reconciliation manifests and fail-closed `--on-stale refuse` gives developers strong guarantees against accidental file loss or silent orphan files.

### Recommendations for Documentation Maintainers
1. **Correct `docs/reference/cli/engines.md`**: Update the "Row-value shape differs from sparql" section to reflect that `oxigraph` now normalizes values to plain unquoted strings by default (and that `raw: true` is an opt-in).
2. **Align Erlang/OTP Requirements in `README.md`**: Update line 42 of `README.md` from `Requires Erlang/OTP 27+` to `Requires Erlang/OTP 25+` to match `mix.exs`, `doctor.ex`, and `getting-started.md`.
3. **Align Literal Error Strings**: Update the tutorial code blocks in `first-pack.md` and `first-reconciliation.md` to match the exact terminal output from `sync.ex` and `pack.ex`.

---

## Conclusion

The tutorial and CLI reference documentation suite for `ggen_igniter` is **exceptionally well-structured, functional, and runnable**. All core getting-started walkthroughs succeed without modification. The only significant discrepancy identified is an outdated section in `engines.md` describing raw Oxigraph term output that was subsequently fixed at the NIF level.
