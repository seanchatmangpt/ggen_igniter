# Formal Release Receipt — ggen_igniter v26.11.10

Tamper-evident formal execution receipt adhering to the Chatman Equation:
$$A = \mu(O^*), \quad R = \text{receipt}(A)$$
where $R = \{\text{identity}, \text{authority}, \text{consequence}, \text{replay}, \text{standing}\}$.

- **Receipt Timestamp:** `2026-11-10T22:45:00Z`
- **Work Order ID:** `WO-v26.11.10-RELEASE-DOCS`
- **Schema Reference:** `priv/schema/fleet-receipt.v2.json`
- **Machine-Readable Proof:** [evidence/receipt.json](evidence/receipt.json)

---

## 1. Identity

```json
{
  "subject": "ggen_igniter v26.11.10 Release Documentation & Shore-up",
  "repo": "ggen_igniter",
  "subject_sha": "1a6e60d6fed9c2adb06a2c097bbc83e8529f007e",
  "base_sha": "1a6e60d6fed9c2adb06a2c097bbc83e8529f007e",
  "host_environment": {
    "os": "macOS (darwin 24.3.0)",
    "elixir": "1.19.5",
    "erlang_otp": "27 [erts-15.2.2]",
    "architecture": "aarch64 / arm64"
  }
}
```

---

## 2. Authority

```json
{
  "ceiling": "DO",
  "grant": "OPERATOR-RELEASE-DISPATCH-2026-11-10",
  "actor": "Sean",
  "lease": {
    "id": "lease-v26.11.10-release",
    "epoch": "2026-11-10T21:13:30Z",
    "ceiling": "DO"
  }
}
```

---

## 3. Consequence

```json
{
  "commits": [
    "1a6e60d6fed9c2adb06a2c097bbc83e8529f007e"
  ],
  "files_changed": [
    "mix.exs",
    "CHANGELOG.md",
    "priv/schema/fleet-receipt.v2.json",
    "priv/schema/fleet-receipt.v2.sha256",
    "test/ggen_igniter_gall_ticket_test.exs",
    "docs/jira/v26.11.10/00-OVERVIEW.md",
    "docs/jira/v26.11.10/01-RELEASE-SHORE-UP-AND-COMPILATION.md",
    "docs/jira/v26.11.10/02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md",
    "docs/jira/v26.11.10/03-IDEMPOTENCY-AND-VERIFICATION-METHODOLOGY.md",
    "docs/jira/v26.11.10/04-OBSERVABILITY-AND-OCEL-PROJECTION.md",
    "docs/jira/v26.11.10/05-REVIEW-LENS-ZACH-DANIEL-ASH.md",
    "docs/jira/v26.11.10/06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md",
    "docs/jira/v26.11.10/07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md",
    "docs/jira/v26.11.10/08-REVIEW-LENS-TESTING-AUDIT.md",
    "docs/jira/v26.11.10/09-REVIEW-LENS-RELEASE-PACKAGING.md",
    "docs/jira/v26.11.10/10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md",
    "docs/jira/v26.11.10/RECEIPT.md",
    "docs/jira/v26.11.10/bin/check_doc_citations.sh",
    "docs/jira/v26.11.10/evidence/receipt.json",
    "docs/jira/v26.11.10/evidence/conformance.json",
    "docs/jira/v26.11.10/evidence/hex_package_manifest.txt",
    "docs/jira/v26.11.10/evidence/test_run.log"
  ],
  "remote_effects": [
    "Hex package ggen_igniter 26.11.10 staged for production publication in Milestone M3"
  ]
}
```

---

## 4. Replay

To reproduce the exact verified state and standings, execute the following ladder:

| # | Command | CWD | Expected Exit | Verified Output Summary |
|---|---|---|---|---|
| 1 | `mix compile --warnings-as-errors --force` | `/Users/sac/ggen_igniter` | 0 | 0 warnings, 0 errors across 219 files |
| 2 | `mix test test/ws5_contracts/16_version_contract_test.exs` | `/Users/sac/ggen_igniter` | 0 | 1 test, 0 failures (version consistency) |
| 3 | `mix test test/ggen_igniter_fleet_receipt_conformance_test.exs` | `/Users/sac/ggen_igniter` | 0 | 10 tests, 0 failures (schema conformance) |
| 4 | `mix test test/ggen_igniter_gall_ticket_test.exs` | `/Users/sac/ggen_igniter` | 0 | 15 tests, 0 failures (WASM concurrency stable) |
| 5 | `mix test test/ggen_igniter_package_ash_free_test.exs --include package` | `/Users/sac/ggen_igniter` | 0 | 5 tests, 0 failures (ash-free packaging fence) |
| 6 | `mix test` | `/Users/sac/ggen_igniter` | 0 | 1,763 passed, 0 failures, 5 skipped (674.1s) |
| 7 | `bash docs/jira/v26.11.10/bin/check_doc_citations.sh` | `/Users/sac/ggen_igniter` | 0 | 100% citations resolved cleanly |

- **Durable Receipt Location:** `docs/jira/v26.11.10/evidence/receipt.json`

---

## 5. Derived Standing

```json
{
  "value": "ALIVE",
  "derived_from": "mix compile --warnings-as-errors --force (exit 0) and mix test (1763 tests passed, 0 failures) at commit 1a6e60d6fed9c2adb06a2c097bbc83e8529f007e"
}
```

- **Schema Conformance:** Verified against `priv/schema/fleet-receipt.v2.json` with `jsonschema.validate` (exit 0).
