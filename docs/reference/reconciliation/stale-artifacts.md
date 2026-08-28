# Stale Artifacts and `--on-stale` Policy

A **stale artifact** is a real on-disk file that a prior execution of a `(template, out_template)` recipe generated (as recorded in the manifest), but which the current execution no longer generates. This is the mechanical footprint of an upstream rename or deletion in the ontology.

---

## 1. Formal Definition & Detection

Stale artifacts are formally defined as the set difference between previously owned paths and currently generated paths for a given recipe:

$$\text{stale} = \text{output\_paths}(\text{old\_entry}) \setminus \text{MapSet.new}(\text{new\_paths})$$

In code (`lib/ggen_igniter/manifest.ex:197-199`):

```elixir
@spec stale_paths(entry() | nil, Enum.t()) :: MapSet.t(String.t())
def stale_paths(entry, new_paths) do
  MapSet.difference(output_paths(entry), MapSet.new(new_paths))
end
```

If `old_entry` is `nil` (first run), `output_paths(nil)` returns `MapSet.new()`, resulting in an empty stale set.

---

## 2. Stale Handling Policies (`--on-stale`)

The `--on-stale` option controls behavior when $\text{stale} \neq \emptyset$. Validated by `Mix.Tasks.GgenIgniter.Sync.resolve_on_stale!/1`:

```elixir
@spec resolve_on_stale!(String.t() | nil) :: :refuse | :prune | :preserve
defp resolve_on_stale!(nil), do: :refuse
defp resolve_on_stale!("refuse"), do: :refuse
defp resolve_on_stale!("prune"), do: :prune
defp resolve_on_stale!("preserve"), do: :preserve
defp resolve_on_stale!(other) do
  raise ArgumentError,
        "--on-stale must be \"refuse\", \"prune\", or \"preserve\", got: #{inspect(other)}"
end
```

Any unrecognized value immediately raises `ArgumentError`.

---

### Policy 1: `refuse` (Fail-Closed Default)

- **Behavior:** Aborts the synchronization process **before writing any files or mutating disk**.
- **Rationale:** Prevents silent artifact orphaning without taking destructive actions that the user did not explicitly authorize.
- **Trigger:** Checked immediately after render computation (`lib/mix/tasks/ggen_igniter.sync.ex:665-667`):

```elixir
if reconcile? and on_stale == :refuse and MapSet.size(stale) > 0 do
  raise ArgumentError, refuse_stale_message(stale, recipe_key)
end
```

- **Error Format:**
```text
ggen_igniter: refusing to sync -- 1 stale output path(s) from a PRIOR run of this recipe ("...") are not written by this run (a rename or removal upstream in the ontology, most likely):

  - lib/support_desk/support/ticket.ex

Nothing was written this run (complete reconciliation or refusal before any partial actuation -- never a silent orphan). Re-run with --on-stale prune to really delete the stale path(s) above, or --on-stale preserve to leave them on disk (with a warning) and proceed.
```

- **Integrity Guarantee:**
  - No new files created (e.g. `case.ex` is NOT created).
  - Stale files untouched (e.g. `ticket.ex` remains with original content).
  - Existing manifest untouched.

---

### Policy 2: `prune` (Automated Garbage Collection)

- **Behavior:** Completes all new file writes, then deletes each stale file using `Manifest.prune!/1` (`File.rm/1`).
- **Manifest State:** Stale paths are dropped from the recipe's `outputs` map in the manifest.
- **Reporting:** Each deleted file is logged via `Mix.shell().info/1`:
  - `"pruned: <path>"` when deleted.
  - `"pruned (already absent): <path>"` if already missing.

```elixir
def prune!(paths) do
  paths
  |> Enum.sort()
  |> Enum.map(fn path ->
    case File.rm(path) do
      :ok ->
        {path, :pruned}

      {:error, :enoent} ->
        {path, :absent}

      {:error, reason} ->
        raise RuntimeError,
              "ggen_igniter: --on-stale prune could not delete stale output #{path}: #{inspect(reason)}"
    end
  end)
end
```

---

### Policy 3: `preserve` (Unmanage & Retain)

- **Behavior:** Writes new files, retains stale files on disk untouched, and logs a warning for each stale file.
- **Manifest State:** Stale paths are **dropped from manifest tracking**. The generator relinquishes ownership so subsequent runs will not attempt to manage or prune them.
- **Warning Message:**
```text
WARNING: ggen_igniter left 1 stale output path(s) on disk (see --on-stale preserve):
  - lib/support_desk/support/ticket.ex
```

---

## 3. `--dry-run` Behavior

When `--dry-run` is passed alongside `--on-stale`:
- `:refuse` (default): Still raises `ArgumentError` if stale paths exist (dry runs preview real decisions, including refusals).
- `:prune`: Prints `"planned: prune <path>"` for each stale artifact without deleting anything.
- `:preserve`: Prints `"planned: preserve <N> stale path(s) (see --on-stale preserve): ..."` without altering manifest state.
- Manifest file is never written under `--dry-run`.

---

## 4. Execution Timing: CLI vs. Reactor Coordinator

| Coordinator | Pruning Execution Point | Verification Gate |
|---|---|---|
| **CLI Inline Pipeline** (`sync.ex`) | Immediately after writing rendered outputs | None (assumes rendered files are valid) |
| **Reactor Coordinator** (`ReconcileReactor`) | During `:finalize_evidence` step | Runs **after** `:verify` (`mix compile --warnings-as-errors`) confirms build integrity |

In `ReconcileReactor`, if compilation fails, the step compensation mechanism triggers before pruning can occur, preventing deletion of legacy code in broken builds.

---

## 5. Verification & Test Evidence

Verified by real integration tests:
- `test/ggen_igniter_reconciliation_manifest_test.exs`:
  - Test 3: Default `refuse` aborts before write.
  - Test 4: `prune` deletes `ticket.ex` and writes `case.ex`.
  - Test 5: `preserve` retains `ticket.ex` on disk and releases manifest tracking.
  - Test 6: `dry-run` raises refusal identically.
- `test/ggen_igniter_destructive_change_agent3_test.exs`:
  - Cases 7 & 8: Verify `refute File.exists?(ticket_path)` after `--on-stale prune`.
