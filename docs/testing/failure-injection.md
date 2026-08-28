# Failure Injection & Recovery Verification

A robust code generation and reconciliation framework must handle invalid inputs, parse failures, engine bugs, and filesystem errors deterministically. `ggen_igniter` verifies failure paths using real error conditions—not mocked exceptions—and evaluates the resulting system state.

Status: **IMPLEMENTED** across unit, property, and Reactor test suites.

---

## 1. Syntax Errors in Templates & Compensation

### Elixir Compile Breaks in `ReconcileReactor`
[`test/ggen_igniter_reconcile_reactor_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_reconcile_reactor_test.exs) injects an invalid EEx template with an unclosed parenthesis:

```elixir
defmodule <%= module_name %> do
  def broken(
end
```

#### Observed Compensation Sequence:
1. **Actuation**: Files are written to disk.
2. **Verification**: The `:verify` step executes `mix compile --warnings-as-errors`, which fails with a syntax error.
3. **Undo Hook (`undo/4`)**: Reactor triggers the `undo/4` callback on `:actuate`. It restores pre-existing files to their exact pre-run content and deletes newly created files via `File.rm/1`.
4. **Receipt Generation**: The receipt is persisted with `standing: :build_broken`.
5. **Hash Invariant**: Pre-run and post-compensation project hashes match identically:
   $$\text{pre\_run\_hash} = \text{post\_run\_hash}$$
6. **Telemetry Trace**: Verifies the strict OCEL event sequence:
   $$\text{ACTUATION\_STARTED} \to \text{FILES\_CHANGED} \to \text{VERIFICATION\_FAILED} \to \text{COMPENSATION\_STARTED} \to \text{FILES\_RESTORED}$$

### Broken Eval Bodies
[`test/ggen_igniter_sync_eval_mode_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_sync_eval_mode_test.exs) tests `mode: eval` templates containing syntax errors (`test/fixtures/eval_mode_broken.exs.eex`). It verifies that `Code.eval_string/2` errors are caught cleanly, emitting clear error diagnostics rather than raw stack trace dumps.

---

## 2. Invalid SPARQL Queries & Malformed Packs

### Malformed SPARQL Syntax
[`test/ggen_igniter_doctor_task_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_doctor_task_test.exs) and [`test/ggen_igniter_pack_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_pack_test.exs) test against `test/fixtures/broken-pack/`:
- `gates/010_bad.rq`: Contains invalid SPARQL syntax (`SELEC ?x WHERE...`).
- When `mix ggen_igniter.doctor --pack-dir test/fixtures/broken-pack` runs, it outputs structured check diagnostics:
  ```text
  ✘ bad (test/fixtures/broken-pack/gates/010_bad.rq) failed to parse
  ✘ ontology.ttl missing at test/fixtures/broken-pack/ontology.ttl
  ✘ no *.eex/*.tmpl files in test/fixtures/broken-pack/templates
  ```
- Ensures non-zero process exit without unhandled BEAM crashes.

---

## 3. Malformed RDF & SPARQL Engine Limitations

### SPARQL 0.3.12 Engine Incompatibility Discovery
In [`test/ash_r2rml_gate_integration_test.exs`](file:///Users/sac/ggen_igniter/test/ash_r2rml_gate_integration_test.exs), real SHACL shape gate queries from `ash_r2rml` are executed against operational RDF shapes.

The test documents an upstream defect in `sparql` 0.3.12:
- Query pattern: `{ FILTER NOT EXISTS { ?shape sh:targetClass ?v } BIND(sh:targetClass AS ?missing) }` inside a `UNION`.
- Result: Evaluates `?v` to an internal `:"$undefined"` atom, causing `Protocol.UndefinedError: protocol SPARQL.Algebra.Expression not implemented for Atom`.
- Testing discipline: Rather than hiding or mocking the collaborator, the failure is pinned as an explicit `assert_raise Protocol.UndefinedError` to surface cross-engine limitations transparently.

---

## 4. Missing & Ambiguous Anchors in Content Injection

[`test/actuate_inject_test.exs`](file:///Users/sac/ggen_igniter/test/actuate_inject_test.exs) exercises fail-closed behavior for `GgenIgniter.Actuate.inject_content!/5`:

```mermaid
flowchart TD
    Req[Injection Request] --> TgtCheck{Target File Exists?}
    TgtCheck -- No --> FailMissing[Fail Closed: RuntimeError 'target file does not exist']
    TgtCheck -- Yes --> AnchorCheck{Anchor Match Count?}
    AnchorCheck -- 0 matches --> FailNoAnchor[Fail Closed: RuntimeError 'anchor not found']
    AnchorCheck -- 2+ matches --> FailAmbiguous[Fail Closed: RuntimeError 'duplicate/ambiguous anchor']
    AnchorCheck -- Exactly 1 match --> PresentCheck{Content Already Injected?}
    PresentCheck -- Yes --> Unchanged[Return {:ok, :unchanged}]
    PresentCheck -- No --> Splice[Splice Content & Return {:ok, :injected}]
```

- **Missing Target File**: Attempting to inject into a non-existent file raises immediately without creating a partial file.
- **Missing Anchor**: Supplying an anchor string that does not appear in the file (`"// nowhere"`) raises `RuntimeError` and leaves the file untouched.
- **Ambiguous / Duplicate Anchors**: If an anchor appears multiple times (`"// SLOT"`), injection fails closed to prevent ambiguous splicing.
- **Dry-Run Anchor Verification**: Running with `dry_run: true` executes the exact anchor resolution gate and raises if the anchor is missing or ambiguous, while guaranteeing 0 bytes are modified on disk.

---

## 5. Unwriteable Paths & Manifest Permission Errors

[`test/ggen_igniter_finalize_evidence_ordering_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_finalize_evidence_ordering_test.exs) injects filesystem permission faults:
- Uses `File.chmod!(dir, 0o555)` to make the manifest storage directory read-only.
- **Verification of Evidence Ordering**:
  1. `Receipt.append!/2` persists the receipt first.
  2. `Manifest.persist!/2` fails due to write permission errors.
  3. The reactor catches the manifest error locally, keeping `standing: :alive` because the actuation and verification succeeded, while leaving the durable receipt as the authoritative recovery anchor.
