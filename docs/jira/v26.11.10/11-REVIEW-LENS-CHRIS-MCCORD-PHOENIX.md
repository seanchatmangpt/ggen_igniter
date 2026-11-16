# Expert Review — Chris McCord Lens (Phoenix Framework Creator)

Architectural evaluation of `ggen_igniter` v26.11.10 from the perspective of Phoenix Framework
and LiveView creator Chris McCord.

- **Review Date:** 2026-11-10
- **Target Release:** `ggen_igniter` v26.11.10 (`3487755919b4c919d132644f47b275f464d44a29`)
- **Toolchain Grounding:** `elixir 1.19.5`, `erlang 27`, `ash 3.33.11`, `igniter 0.8.4`, `spark 2.7.3`
- **Review Persona:** Creator and lead architect of Phoenix Framework and LiveView. Passionate
  advocate for developer ergonomics (DX), operational simplicity, clear mental models, and real-time
  boundaries. Hostile to opaque error traces, confusing CLI options, generic `generated/` directory
  dumping grounds, and unhelpful failure modes. Insists that generated code must be clean, readable,
  and something developers feel proud to own.

---

## Executive Summary & Stance

> "Generators should empower developers, not alienate them with machine-generated sludge. When a
> CLI task fails, it must tell you why in plain language and show you the exact command to fix it.
> And keep your namespaces meaningful—never dump code into a lazy `generated/` bucket."

This review evaluated `ggen_igniter` from the perspective of developer ergonomics, CLI experience,
automated diagnostics, and code readability. The architecture receives an **APPROVED WITH REPAIRS**
verdict. The diagnostic task `mix ggen_igniter.doctor` with automated `--fix` capabilities and
the strict enforcement of domain-meaningful namespaces represent exemplary engineering. One minor
repair is required to align legacy documentation examples in `sync.ex` with the Directory Taxonomy Law.

---

## Section 1 — CONFIRMED Findings (Ranked)

### Majors

#### M1. Actionable Diagnostic Remediation via `mix ggen_igniter.doctor --fix`
- **Observation:** `lib/mix/tasks/ggen_igniter.doctor.ex:95-105` and `lib/ggen_igniter/doctor_fixes.ex:1-60`
  implement 7 automated AST fixes for common developer mistakes. If `igniter` or `sourceror` dependencies
  are accidentally restricted with `only: [:dev, :test]` in `mix.exs`, or if an Ash domain module is missing
  from `config :OTP_APP, ash_domains: [...]`, `mix ggen_igniter.doctor --fix` applies safe, structural
  modifications directly to the user's project files.
- **DX Assessment:** In Phoenix, `phx.routes` and friendly compiler error messages guide developers to
  solutions. `ggen_igniter.doctor` matches this ethos by offering one-command repairs.
- **Implementation Quality:** `lib/ggen_igniter/doctor_fixes.ex:30-58` performs structural codemods via
  `Sourceror.Zipper` and Igniter primitives rather than brittle string regex substitutions, preserving
  comments and formatting.
- **Standing:** `ALIVE` (Verified in `test/ggen_igniter_doctor_fixes_idempotence_test.exs:1-40`).

#### M2. Pre-Validation of CLI Switches & Granular Exit Code Contract
- **Observation:** In `lib/mix/tasks/ggen_igniter.doctor.ex:194-228`, the task intercepts `run(argv)` before
  invoking `super(argv)` to catch unknown flags. Igniter's default behavior raises `OptionParser.ParseError`,
  causing Mix to report a generic "Could not invoke task" with exit code 1. `GgenIgniter.Doctor` fixes this
  by cleanly separating exit codes:
  - `0`: all checks pass.
  - `1`: diagnostic failure found.
  - `2`: invalid invocation / unknown flag.
  - `3`: unsupported platform capability.
  - `4`: blocked by authority or lock.
- **DX Assessment:** Tools that conflate syntax errors with diagnostic findings break automated developer
  tooling. This clear exit-code contract provides predictable CLI integration.

#### M3. Enforcement of Directory Taxonomy Law (Ban on `generated/`)
- **Observation:** Global doctrine and `AGENTS.md` strictly forbid directories named `generated/`. Output
  code must reside in domain-meaningful namespaces (`lib/book_library/catalog/`, `lib/book_library/circulation/`).
  Inspection of `git ls-files` confirms zero instances of `*/generated/*` directories across source and fixtures.
- **DX Assessment:** In Phoenix, context generators (`mix phx.gen.context Accounts User users`) generate code
  into first-class domain namespaces. Dumping output into `generated/` encourages developers to treat generated
  code as a black box rather than maintained domain logic.

---

### Minors

#### m1. Legacy Documentation Example References `lib/generated/`
- **Observation:** In `lib/mix/tasks/ggen_igniter.sync.ex:45, 96, 123`, docstring examples illustrate usage
  with `--out "lib/generated/<%= module_name %>.ex"` and `--out lib/generated.ex`.
- **Impact:** Contradicts the project's Directory Taxonomy Law and confuses developers following task help.
- **Resolution:** Update docstring examples to use domain-meaningful paths (e.g. `lib/my_app/catalog/<%= module_name %>.ex`).

#### m2. POSIX Atomic Write Durability
- **Observation:** In `lib/ggen_igniter/actuate.ex:31-54`, file writes avoid intermediate corruptions by writing
  to a temporary sibling file (`path <> ".ggen_igniter.tmp.<id>"`), calling `:file.sync/1` for fsync durability,
  and atomically replacing the target via `File.rename!/2`.
- **DX Assessment:** Protects developers and file watchers from observing half-written files during compilation.

---

## Section 2 — REFUTED Findings

### R1. Refuted Claim: "ggen_igniter should use Mix.shell().cmd/2 instead of in-memory Igniter tasks"
- **Claim:** Shelling out to `mix ash.gen.resource` is simpler and matches how users run CLI commands.
- **Investigation:** Shelling out triggers N separate compilation cycles and trips CLI option parser validation
  bugs in Ash (e.g., `--ignore-if-exists` is rejected on the CLI of `ash.gen.domain` at
  `deps/igniter/lib/igniter/util/info.ex:354-368`, but accepted in-memory via `Igniter.compose_task/4` at
  `deps/igniter/lib/mix/task.ex:237`). In-memory composition is both orders of magnitude faster and architecturally sound.
- **Verdict:** REFUTED.

### R2. Refuted Claim: "Interactive prompts are needed for generator conflict resolution"
- **Claim:** When files already exist, the CLI should prompt `Overwrite? [Y/n]`.
- **Investigation:** In automated and autonomic AI workflows, interactive stdin prompts hang unattended pipelines.
  `ggen_igniter` uses deterministic flags (`--unless-exists`, `--dry-run`, `--check`) and the reconciliation
  manifest (`manifest.json`) to handle conflicts without human stalling.
- **Verdict:** REFUTED.

---

## Section 3 — Expert Recommendations & Vision

1. **Clean Up Legacy Doc References:** Update `lib/mix/tasks/ggen_igniter.sync.ex:45, 96, 123` to eliminate
   `lib/generated/` references.
2. **Provide Phoenix LiveView Generator Packs:** In future releases, introduce an `ash_phoenix` pack that
   manufactures LiveView CRUD interfaces directly from the RDF ontology.
3. **Add `--diff` Flag to Doctor:** Allow developers to preview exact proposed AST modifications before running
   `mix ggen_igniter.doctor --fix`.

---

## Section 4 — What This Review Did NOT Check

- Web frontend LiveView hooks, CSS/Tailwind asset pipelines, WebSocket transport latency.

---

## Section 5 — Evidence Ledger & Mechanical Citations

| Subject / Artifact | Exact Location | Finding / Invariant Verified | Standing / Result |
|---|---|---|---|
| Doctor exit code contract | `lib/mix/tasks/ggen_igniter.doctor.ex:175-228` | Pre-validation and structured exit codes (0-4) | Enforced |
| Doctor structural codemods | `lib/ggen_igniter/doctor_fixes.ex:30-58` | Sourceror.Zipper AST modifications | `ALIVE` |
| Doctor fixes idempotence | `test/ggen_igniter_doctor_fixes_idempotence_test.exs:1-40` | Idempotent multi-run AST modification | Passed |
| POSIX atomic rename | `lib/ggen_igniter/actuate.ex:31-54` | Tempfile, fsync, and atomic rename | Guaranteed |
| Legacy docstring examples | `lib/mix/tasks/ggen_igniter.sync.ex:45, 96, 123` | Docstrings referencing `lib/generated/` | Confirmed defect |
| Overview charter | `00-OVERVIEW.md` | Release overview and toolchain grounding | Verified |
| Idempotency methodology | `03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md` | Verification protocol and zero-diff invariant | Verified |
