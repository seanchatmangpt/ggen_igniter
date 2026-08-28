# Write-Safety Guarantees & Decision Tables

## Overview

A core requirement for automated code generation tools is ensuring **write-safety**: preventing unintended file overwrites, detecting conflicts, avoiding duplicate writes on repeat runs, and ensuring dry-run honesty.

`ggen_igniter` implements a multi-tiered safety model spanning:
1. **Upstream Whole-Plan Invariants**: Handled during admission (`admit` step in `ReconcileReactor`).
2. **File Actuation Decision Table**: Evaluated per-file in `GgenIgniter.Actuate.write_file!/3`.
3. **Injection Anchor Gates**: Evaluated in `GgenIgniter.Actuate.inject_content!/5`.

---

## 1. Whole-File Write Decision Table (`Actuate.write_file!/3`)

When actuating whole files (`mode: file`, no `inject: true`), `GgenIgniter.Actuate.write_file!/3` (`lib/ggen_igniter/actuate.ex:75-101`) applies the following decision rules in strict priority order (first match wins):

```elixir
cond do
  # 1. unless_exists guard: skip if file already exists
  unless_exists and exists ->
    {:ok, :skipped_exists}

  # 2. skip_if guard: skip if existing file matches pattern
  exists and skip_if != nil and matches?(existing, skip_if) ->
    {:ok, :skipped_match}

  # 3. Idempotency guard: skip if file content is byte-identical
  exists and existing == content ->
    {:ok, :unchanged}

  # 4. Dry-run mode: report write without performing disk IO
  dry_run ->
    {:ok, :written}

  # 5. Execute write: create directories and write file
  true ->
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    {:ok, :written}
end
```

### Outcome Definitions

| Outcome Atom | Meaning | Manifest Ownership Status |
|---|---|---|
| `:written` | File did not exist (or existed with different content) and was written to disk. | **Tracked** (Recorded in `manifest.json`) |
| `:unchanged` | File already existed with byte-identical content; write skipped. | **Tracked** (Reconfirmed in `manifest.json`) |
| `:skipped_exists` | `unless_exists: true` and the file existed; write skipped. | **Excluded** (Not owned by this recipe) |
| `:skipped_match` | `skip_if: pattern` matched the existing file; write skipped. | **Excluded** (Not owned by this recipe) |

> [!IMPORTANT]
> A file skipped due to `:skipped_exists` or `:skipped_match` is **never recorded** as owned in `manifest.json`. If it were tracked, a subsequent change in the ontology that removes the entity would cause `--on-stale prune` to delete a pre-existing user file that `ggen_igniter` never wrote.

---

## 2. Dry-Run Honesty (`--dry-run`)

`--dry-run` is designed as a true simulation of the actuation phase, not an error-suppressing mock:
- **Full Validation**: Reads actual disk contents, checks existing file hashes, evaluates regex patterns, and verifies anchor uniqueness.
- **Real Error Surfacing**: If an injection anchor is missing or ambiguous, `--dry-run` **raises the real error** immediately.
- **Zero Disk Mutation**: Calls to `File.mkdir_p!/1`, `File.write!/2`, `File.rm/1`, and `Manifest.persist!/2` are skipped.
- **Notice Formatting**: Outputs `planned: write <path>`, `planned: inject <path>`, `planned: skip <path> (unchanged)`, or `planned: prune <path>`.

---

## 3. Conflict Detection & Idempotency

### Cross-Target Conflict Detection
In `GgenIgniter.Reactors.ReconcileReactor`, collision detection prevents write conflicts across multiple queries or fan-out rows:
- If two targets evaluate to the identical output path in a single execution plan, admission fails closed (`{:error, {:refused_duplicate_output_path, collisions}}`).
- Eliminates non-deterministic race conditions during parallel file writes (`Task.async_stream/3`).

### Repeat Execution Idempotency
- **Whole-File**: If the generated content matches the current disk content byte-for-byte, `write_file!/3` returns `:unchanged`. `Manifest.persist!/2` detects that `outputs` are identical via `Manifest.same_outputs?/2` and avoids rewriting `manifest.json` or changing file timestamps.
- **Code Injection**: `inject_content!/5` verifies whether the slice of lines to be injected is already present before/after the anchor. If present, it skips insertion and returns `:unchanged`.

---

## 4. `mode: eval` Trust Boundary

When a template specifies `mode: eval` (in frontmatter or via `--mode eval`), the rendered template body is treated as Elixir source code and evaluated in-process via `GgenIgniter.Actuate.eval_code!/2`:

```elixir
def eval_code!(code, bindings) when is_binary(code) and is_list(bindings) do
  {value, _bindings} = Code.eval_string(code, bindings)
  {:ok, value}
rescue
  e in [CompileError, SyntaxError, TokenMissingError] ->
    reraise RuntimeError,
            "mode: eval template failed to compile: #{Exception.message(e)}",
            __STACKTRACE__
end
```

### Trust Boundary Security Notice
- `mode: eval` allows **arbitrary code execution** in the host BEAM process.
- Ontologies, queries, and templates are treated as trusted inputs (equivalent to standard EEx templates, which can execute arbitrary Elixir expressions inside `<%= %>`).
- No sandboxing or restricted evaluation environment is applied.
- `mode: eval` never writes to disk and is completely excluded from manifest reconciliation tracking.
