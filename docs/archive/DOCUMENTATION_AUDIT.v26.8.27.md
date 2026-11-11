# Documentation Audit

Every `.md` file found in this repo as of 2026-08-27 (HEAD `c27008c`,
`mix.exs` version `26.8.27`), classified CURRENT / STALE / DUPLICATE /
MISLEADING / SUPERSEDED / KEEP / DELETE-CANDIDATE with one real, cited
reason each. **Nothing listed here was deleted or moved by this pass** —
classification only, per this task's own scope.

A file may carry more than one label (e.g. "SUPERSEDED, KEEP") when the
honest read is nuanced — a single forced label would misstate the finding.

## Top-level and package docs

| File | Classification | Reason |
|---|---|---|
| `README.md` | **STALE (partial), otherwise CURRENT** | The `### mix ggen_igniter.doctor` section (lines 131–155) describes a **9-check** list ("1. Elixir/OTP... 9. Target git status"). The real `lib/mix/tasks/ggen_igniter.doctor.ex` moduledoc and `igniter/1` implementation now run **17** checks (added: two more dep-fix rules, version-policy check, NIF-compile check, oxigraph smoke test, hex-publish check, plus the qlever-reachability check moved and renumbered). Every other section (installation, `sync` usage, engines, `--for-each`, `--dry-run`, `--pack`, `mix e2e`, Known Limitations) was verified directly against current source (`sync.ex`, `pack.ex`, `frontmatter.ex`) and matches. Follow-up: replace the doctor section with a pointer to `docs/reference/cli/doctor.md` (agent 3's scope) or `docs/operations/debugging.md`'s table, rather than re-maintaining a second copy of the checklist here. |
| `CHANGELOG.md` | **CURRENT** | Topmost entry `## v26.8.27` matches `mix.exs:9`'s `version: "26.8.27"` exactly (verified byte-for-byte) — this file is the project's own real, checked source of truth for its release-version convention (see `GgenIgniter.DoctorFixes.check_version_policy/1`, which reads this file directly for the same reason). |
| `wasm-artifacts/README.md` | **CURRENT, narrow scope** | Describes a real, dated (2026-08-26) build-artifact snapshot of `ggen-graph-wasm`, explicitly discloses the crate exposes zero `#[wasm_bindgen]`/`extern "C"` entry points and that `RemoteEngine::query()` is a `todo!()` stub — an honest, current disclosure, not stale or misleading. Explicitly and correctly scoped as unrelated to `ggen_igniter`'s own native integration path (`native/ggen_graph_nif`, which uses the native `oxigraph-engine` feature, not this WASM build). |

## `.ggen_igniter_factory/` — factory-cell working documents

| File | Classification | Reason |
|---|---|---|
| `.ggen_igniter_factory/AUTHORITY.md` | **CURRENT, KEEP** | A short, still-accurate authority/permission boundary statement for this factory cell (allowed vs. forbidden-without-explicit-authority actions). Nothing in it references a stale fact. |
| `.ggen_igniter_factory/ADVERSARIAL.md` | **CURRENT (time-boxed synthesis)** | Real, dated (2026-08-27), consolidated synthesis of 10 independent adversarial reports plus `capability_matrix.md`/`version_check.md`, with an explicit verdict ("PARTIAL, not ALIVE") and six real MUST-FIX findings, each with cited commands/output. This is the single most authoritative and current standing-verification document in the repo today. Caveat stated honestly in its own text: multiple agents were editing the tree concurrently while the underlying reports ran, so any given row's evidence is a snapshot, not a permanent fact — re-verify before citing an individual row as still true on a later date. |
| `.ggen_igniter_factory/capability_matrix.md` | **SUPERSEDED (partially), KEEP as raw source** | Explicitly an earlier-timestamped pass (~14:2x–22:0xZ) than the 10 adversarial reports; its own header says "9 other agents are editing this tree concurrently right now; some findings below may already have changed." At least one of its findings (the `already_present_at?/4` arity-mismatch `BUILD_BROKEN` row) is directly superseded by three later, independent reports that found it fixed — `ADVERSARIAL.md`'s "MUST FIX #6" documents this exact supersession explicitly rather than silently dropping the earlier finding. Kept as the raw source `ADVERSARIAL.md` itself cites; do not read this file's per-row STANDING column as current without cross-checking `ADVERSARIAL.md` first. |
| `.ggen_igniter_factory/version_check.md` | **DUPLICATE, KEEP as raw source** | Its entire content (the `v26.7.27` requested vs. `26.8.27` real `mix.exs` mismatch) is fully reproduced and cross-confirmed inside `ADVERSARIAL.md`'s "MUST FIX #5" and its "Release/version framing" ledger row. No information here is not already in the consolidated file; kept as the original single-agent source, not because it adds anything `ADVERSARIAL.md` lacks. |
| `.ggen_igniter_factory/zach_chris_acceptance.md` | **CURRENT, KEEP** | Distinct scope not duplicated elsewhere: a real, source-quoted acceptance review of generated-code idiomaticity (Ash DSL fidelity, `GgenIgniter.*` namespace-leakage grep, CLI ergonomics against a stated "one clean `--pack NAME` call" bar). Its two real findings (Stage-7 rename breaking a separately-generated LiveView; the real e2e invocation using 4 CLI flags, not the stated 1) are referenced from `docs/operations/failure-recovery.md` and `docs/contributing/adding-a-pack.md` respectively in this pass, rather than restated — no drift found between this document and current template/test content it quotes. |
| `.ggen_igniter_factory/adversarial/01_edits_on_disk.md` through `10_package_contents.md` (10 files) | **DUPLICATE (by design), KEEP as evidence trail** | These are the 10 raw, independent per-domain verification reports `ADVERSARIAL.md` explicitly synthesizes and cites by filename throughout (e.g. "report `05_exit_codes.md`"). Their findings are not additional to `ADVERSARIAL.md` — they are its inputs. This is intentional evidentiary redundancy (the methodology's own design: independent verifiers, then one honest synthesis), not accidental doc drift, so none of the 10 is a delete-candidate; each remains the primary citable source for its own domain's real command output. |

## `docs/` — work in progress by other, concurrently-running agents

| File | Classification | Reason |
|---|---|---|
| `docs/reference/cli/index.md` | **CURRENT** | Outside this audit's own write-scope (owned by the CLI-reference agent per `.ggen_igniter_factory/docs-ownership.json`); read for cross-reference only. Its "Status label: everything in this tree is IMPLEMENTED" claim was spot-checked against the same `sync.ex`/`doctor.ex` moduledocs this audit read directly and is consistent with them as of this pass. |

Other `docs/**` paths owned by concurrently-running agents
(`docs/architecture/**`, `docs/tutorials/**`, `docs/integrations/**`,
`docs/reference/reactor/**`, `docs/reference/reconciliation/**`,
`docs/reference/evidence/**`, `docs/testing/**`, `docs/reviews/**`, and the
top-level `docs/README.md`/`docs/index.md`/`docs/glossary.md`/`docs/status.md`/
`docs/how-to/**`) were not yet populated, or were only partially populated,
at the time this audit ran (per a real `find docs -type f` listing taken
during this pass) — not classified here since there was no file content yet
to classify; re-run this audit's file enumeration later if a full-repo
picture is needed after those agents finish.

## Net finding

No file in this repo is MISLEADING in the sense of asserting something
demonstrably false about current behavior — the one real drift found
(`README.md`'s doctor checklist under-counting real checks 10→17) is
ordinary staleness from the doctor task growing after the README section
was last edited, not a fabricated or contradicted claim. The
`.ggen_igniter_factory/` tree's apparent redundancy (capability matrix +
version check + 10 adversarial reports + one synthesis) is intentional
methodology, not accidental duplication, and is disclosed as such inside
`ADVERSARIAL.md` itself.

## See Also

- `docs/operations/*.md`, `docs/contributing/*.md` — this pass's own new deliverables, cross-referenced above where they absorb a fact from an audited file
- `.ggen_igniter_factory/docs-findings.jsonl` — this pass's per-claim evidence ledger (agent 10 rows)
- `.ggen_igniter_factory/docs-ownership.json` — the write-scope map this audit's `docs/` section is read against
