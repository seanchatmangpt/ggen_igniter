# Idempotency and Write Safety

Idempotency guarantees that executing `mix ggen_igniter.sync` multiple times against identical inputs produces no side effects, causes no unnecessary disk I/O, leaves timestamps intact, and prevents dirty Git diffs.

In `ggen_igniter`, idempotency operates across two distinct layers:
1. **Actuation Layer (`GgenIgniter.Actuate`):** Content-level diffing and conditional guards.
2. **Reconciliation Layer (`GgenIgniter.Manifest`):** Manifest equality checking and write suppression.

---

## 1. Actuation Decision Order (`Actuate.write_file!/3`)

When writing a file, `Actuate.write_file!/3` evaluates guards in strict priority order (first match wins):

```elixir
def write_file!(path, content, opts \\ []) do
  unless_exists = Keyword.get(opts, :unless_exists, false)
  skip_if = Keyword.get(opts, :skip_if)
  dry_run = Keyword.get(opts, :dry_run, false)

  exists = File.exists?(path)
  existing = if exists, do: File.read!(path), else: nil

  cond do
    unless_exists and exists ->
      {:ok, :skipped_exists}

    exists and skip_if != nil and matches?(existing, skip_if) ->
      {:ok, :skipped_match}

    exists and existing == content ->
      {:ok, :unchanged}

    dry_run ->
      {:ok, :written}

    true ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      {:ok, :written}
  end
end
```

### Outcome Matrix

| Step | Condition | Outcome Atom | Action Taken |
|---|---|---|---|
| 1 | `unless_exists: true` and file exists | `:skipped_exists` | Skip write completely (regardless of content). |
| 2 | `skip_if: pattern` and file content matches | `:skipped_match` | Skip write completely. Pattern can be substring or `Regex`. |
| 3 | Target exists and `existing == content` | `:unchanged` | Skip write (byte-identical content). No filesystem mutation. |
| 4 | `--dry-run` is active | `:written` | Simulate write; do not touch disk. |
| 5 | Default / Content differs / File missing | `:written` | Create directories (`File.mkdir_p!`) and write content (`File.write!`). |

---

## 2. Guard Details

### `:unchanged` (Content-Level Idempotency)
- **Automatic & Unconditional:** Does not require an opt-in flag.
- **Mechanism:** Compares binary strings `existing == content`.
- **Output Notice:** Logs `"unchanged (skipped, identical content): <path>"`.

### `unless_exists` Flag
- **Flag:** `--unless-exists` / `unless_exists: true`
- **Use Case:** Initial file scaffolding (e.g. user-editable config files or baseline modules) where future sync runs must not overwrite manual edits.
- **Output Notice:** Logs `"skipped (unless_exists, already exists): <path>"`.

### `skip_if` Pattern Matching
- **Flag:** `--skip-if <pattern>` / `skip_if: pattern`
- **Pattern Matching:**
  - `binary`: `String.contains?(content, needle)`
  - `%Regex{}`: `Regex.match?(pattern, content)`
- **Use Case:** Preserving user customizations identified by marker comments or custom directives.
- **Output Notice:** Logs `"skipped (skip_if matched): <path>"`.

### Injection Idempotency (`Actuate.inject_content!/5`)
For partial-file splices using frontmatter `inject: true`, `Actuate.inject_content!/5` inspects the insertion anchor. If the injected block is already present at that exact line position, it returns `{:ok, :unchanged}` and skips writing to avoid duplicating code.

---

## 3. Manifest Layer Write Suppression (`same_outputs?/2`)

A core design requirement is that a no-op sync must leave `.ggen_igniter/manifest.json` **byte-for-byte untouched** (including its timestamp).

`Manifest.same_outputs?/2` performs strict map equality between current run outputs and existing entry outputs:

```elixir
def same_outputs?(entry, outputs) when is_map(outputs) do
  existing =
    case entry do
      %{"outputs" => o} when is_map(o) -> o
      _ -> %{}
    end

  existing == outputs
end
```

In `Mix.Tasks.GgenIgniter.Sync` (`lib/mix/tasks/ggen_igniter.sync.ex:708-715`):

```elixir
unless Manifest.same_outputs?(old_entry, outputs) do
  pack_dir = if pack_given?(opts), do: GgenIgniter.Pack.resolve_dir!(opts)
  entry = Manifest.build_entry(template_path, out_template, pack_dir, outputs)

  manifest
  |> Manifest.put(recipe_key, entry)
  |> Manifest.persist!(manifest_dir)
end
```

### Why Manifest Write Suppression Matters
If `manifest.json` were rewritten on every sync:
1. `updated_at` would increment continuously, masking when the recipe actually changed.
2. Version control would report spurious dirty diffs for `.ggen_igniter/manifest.json`.

---

## 4. Exclusion of Skipped Files from Ownership

Only outcomes `:written` and `:unchanged` are recorded in the manifest outputs:

```elixir
outputs =
  for {_line, out_path, outcome} <- render_results,
      outcome in [:written, :unchanged],
      into: %{} do
    {out_path, Manifest.hash_content(File.read!(out_path))}
  end
```

Files with outcome `:skipped_exists` or `:skipped_match` are **intentionally omitted** from `outputs`. Because the generator refrained from asserting ownership over their contents, it must never claim ownership in the manifest. This prevents a subsequent ontology rename from identifying those files as stale and pruning them.

---

## 5. Verification & Test Evidence

- `test/ggen_igniter_reconciliation_manifest_test.exs` (Test 2):
  - Proves that a consecutive re-sync against the same ontology results in `output =~ "unchanged (skipped, identical content)"` and `File.read!(manifest_path) == manifest_bytes_before`.
- `test/actuate_test.exs`:
  - Validates `unless_exists`, `skip_if`, and `:unchanged` outcome transitions.
