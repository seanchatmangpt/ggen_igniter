# Reconciliation Manifest

`GgenIgniter.Manifest` (`lib/ggen_igniter/manifest.ex`) is the **manufacturing ownership memory** of `ggen_igniter`. It transforms `mix ggen_igniter.sync` from a stateless code generator into a stateful reconciler that tracks what it previously wrote to disk. When an entity is renamed or removed upstream in the ontology, the manifest enables mechanical detection of **stale output files** rather than leaving silently orphaned artifacts on disk.

---

## 1. Observed Implementation vs. Target Schema

### Runtime Schema (`lib/ggen_igniter/manifest.ex`)
In the observed codebase, `GgenIgniter.Manifest` operates over JSON-decoded string-keyed maps rather than a typed Elixir `%GgenIgniter.Manifest{}` struct:

```elixir
@type entry :: %{
        optional(String.t()) => term(),
        required(String.t()) => term()
      }

@type t :: %{String.t() => term()}
```

On disk (`<base_dir>/.ggen_igniter/manifest.json`), the manifest is stored as a formatted JSON document:

```json
{
  "version": 1,
  "entries": {
    "<template_path>=><out_template>": {
      "template": "test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex",
      "out_template": "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex",
      "pack_dir": "test/fixtures/ash-lifecycle-pack",
      "updated_at": "2026-08-27T12:34:56.789012Z",
      "outputs": {
        "lib/support_desk/support/ticket.ex": "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "lib/support_desk/support/customer.ex": "sha256:a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0"
      }
    }
  }
}
```

### Manifest Fields Description

| Field | Type | Description |
|---|---|---|
| `version` | `integer` | Schema version (`1`). Loaded manifests must match this version. |
| `entries` | `map` | Map from `recipe_key` to recipe entry objects. |
| `entry.template` | `string` | Resolved file path to the template (`--template`). |
| `entry.out_template` | `string` | Unrendered raw `--out` path string containing EEx expressions. |
| `entry.pack_dir` | `string \| null` | Path to the pack directory if invoked via `--pack` or `--pack-dir` (informational metadata). |
| `entry.updated_at` | `string` | ISO 8601 UTC timestamp of the last successful actuation run. |
| `entry.outputs` | `map` | Map of `path => "sha256:<hex>"` digests for all files written or confirmed unchanged by this recipe. |

### Architectural Model (Target Structs)
In conceptual architecture and future alignment specs, this corresponds to:

- `%GgenIgniter.Manifest{version: 1, generator: "ggen_igniter", ontology_digest: "...", pack: "...", engine: "oxigraph", artifacts: [%Artifact{}]}`
- `%Artifact{path: "...", digest: "sha256:...", source_template: "...", permissions: 0o644}`

In the current implementation, the entry is keyed by recipe identity `(template, out_template)` and encapsulates the output artifact map directly in `outputs`.

---

## 2. Manifest Keying: Recipe Identity (`recipe_key/2`)

Each entry in the manifest is keyed by `Manifest.recipe_key(template_path, out_template)`:

```elixir
def recipe_key(template_path, out_template)
    when is_binary(template_path) and is_binary(out_template) do
  template_path <> "=>" <> out_template
end
```

### Why Key by `(template, out_template)`?

1. **Not Ontology Path:** Developers iteratively edit `ontology.ttl` in place while keeping the path constant. If the manifest were keyed by ontology path, content changes would not trigger a new key, but using a checksum of the ontology path would break continuity across edits.
2. **Not Pack Name Alone:** CLI invocations without `--pack` (direct `--ontology`, `--template`, `--out`) must be first-class. The `(template, out_template)` tuple exists in every invocation shape.
3. **Stable Recipe Across Renames/Deletions:** In fan-out mode (`--for-each resource`), the unrendered `out_template` (`"lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`) remains invariant even when individual rows change from `Ticket` to `Case`. The diff between rendered output sets (`old_paths` vs `new_paths`) reveals exactly which artifacts became stale.

---

## 3. What Is Tracked vs. Excluded

Only `mode: file` writes actuated via `Actuate.write_file!/3` (full file ownership) are tracked in the manifest.

### Deliberately Excluded:
- **`mode: eval`:** Evaluated code does not write to disk (`Actuate.eval_code!/2`).
- **`inject: true` targets:** `Actuate.inject_content!/5` splices content into pre-existing consumer files. The pack does not own the target file; tracking it in the manifest would allow `--on-stale prune` to dangerously delete files the pack never created.
- **Skipped writes (`:skipped_exists`, `:skipped_match`):** Files skipped due to `--unless-exists` or `--skip-if` were not written or re-verified by this pack. Recording them would risk pruning user-managed files upon future renames.

---

## 4. Content Hashing & Path Canonicalization

### SHA-256 Content Hashing
Content digests are calculated using `Manifest.hash_content/1`:

```elixir
def hash_content(content) when is_binary(content) do
  "sha256:" <> (:crypto.hash(:sha256, content) |> Base.encode16(case: :lower))
end
```

To ensure integrity, digests are computed by **re-reading the written file from disk** after actuation, rather than taking the in-memory render string.

### Path Canonicalization & Location
- The manifest path is resolved by `Manifest.path(base_dir)` -> `<base_dir>/.ggen_igniter/manifest.json`.
- `base_dir` defaults to the working directory where `mix ggen_igniter.sync` is invoked (`File.cwd!()`).
- Can be overridden via `--manifest-dir <path>` or the `:manifest_dir` option.

---

## 5. Atomic Disk Persistence

Manifest writes use atomic file replacement to prevent corruption if the process terminates mid-write (`Manifest.persist!/2`):

```elixir
def persist!(manifest, base_dir) do
  manifest_path = path(base_dir)
  File.mkdir_p!(Path.dirname(manifest_path))

  tmp_path =
    manifest_path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

  json = Jason.encode!(manifest, pretty: true)
  File.write!(tmp_path, json <> "\n")
  File.rename!(tmp_path, manifest_path)
  :ok
end
```

1. Formats JSON with pretty indentation.
2. Writes to a unique sibling file on the same filesystem (`.manifest.json.tmp-<id>`).
3. Executes atomic `File.rename!/2` to overwrite the active manifest.

---

## 6. Manifest API Reference (`GgenIgniter.Manifest`)

| Function | Signature | Description |
|---|---|---|
| `path/1` | `(String.t()) -> String.t()` | Returns `<base_dir>/.ggen_igniter/manifest.json`. |
| `load/1` | `(String.t()) -> t()` | Loads JSON manifest. Returns `%{"version" => 1, "entries" => %{}}` if absent (`:enoent`). Raises `ArgumentError` on invalid JSON or malformed schema. |
| `recipe_key/2` | `(String.t(), String.t()) -> String.t()` | Combines template path and output template into `"<template>=><out_template>"`. |
| `get_entry/2` | `(t(), String.t()) -> entry() \| nil` | Fetches entry for a recipe key. |
| `output_paths/1` | `(entry() \| nil) -> MapSet.t(String.t())` | Returns `MapSet` of previously recorded output paths. |
| `stale_paths/2` | `(entry() \| nil, Enum.t()) -> MapSet.t(String.t())` | Computes `MapSet.difference(output_paths(entry), MapSet.new(new_paths))`. |
| `hash_content/1` | `(binary()) -> String.t()` | Computes `"sha256:<hex>"` lowercase SHA-256 digest. |
| `same_outputs?/2` | `(entry() \| nil, map()) -> boolean()` | Checks if newly generated outputs map matches recorded outputs byte-for-byte. |
| `build_entry/4` | `(String.t(), String.t(), String.t() \| nil, map()) -> entry()` | Constructs a new entry stamped with UTC ISO 8601 timestamp. |
| `put/3` | `(t(), String.t(), entry()) -> t()` | Updates manifest map with the new entry under `key`. |
| `persist!/2` | `(t(), String.t()) -> :ok` | Atomically writes manifest to disk. |
| `prune!/1` | `([String.t()]) -> [{String.t(), :pruned \| :absent}]` | Deletes specified paths with `File.rm/1`. Raises `RuntimeError` on OS permission failures. |

---

## 7. Pipeline Integration & Execution Contexts

Three execution contexts interact with reconciliation:

1. **`Mix.Tasks.GgenIgniter.Sync` (Inline Pipeline - Default):**
   - Directly checks `Manifest.load/1`, calculates `Manifest.stale_paths/2`, enforces `--on-stale`, writes outputs, checks `Manifest.same_outputs?/2`, and persists via `Manifest.persist!/2`.
2. **`GgenIgniter.Reactors.ReconcileReactor` (Opt-in Reactor):**
   - Coordinates steps `:observe_prior_manifest` -> `:render` -> `:admit` -> `:actuate` -> `:verify` -> `:finalize_evidence`.
   - Pruning is deferred until `:finalize_evidence`, after compilation succeeds.
3. **`GgenIgniter.Reconcile.run/1` (Stateless Helper):**
   - Bounded execution helper. Does not read or write the manifest.

---

## 8. Verification & Test Evidence

All manifest operations are verified through integration tests:
- `test/ggen_igniter_reconciliation_manifest_test.exs`: Tests initial creation, no-op byte-identical preservation, refusal, pruning, and dry-run preview.
- `test/ggen_igniter_destructive_change_agent3_test.exs`: Tests resource rename/removal reconciliation across 10 lifecycle cases.
