# Durable Process Receipts

Status: **IMPLEMENTED**. Verified against `lib/ggen_igniter/receipt.ex`, `lib/ggen_igniter/reactors/reconcile_reactor.ex`, and test suites (`test/ggen_igniter_receipt_test.exs`, `test/ggen_igniter_reconcile_reactor_test.exs`, `test/ggen_igniter_finalize_evidence_ordering_test.exs`).

---

## 1. Overview & Core Distinction

`GgenIgniter.Receipt` provides durable, append-only historical evidence for every admitted reconciliation attempt within `ggen_igniter`.

### Production Manifest vs. Run Receipt

The system maintains two distinct durable records on disk with contrasting lifecycle disciplines:

| Dimension | `GgenIgniter.Manifest` (`.ggen_igniter/manifest.json`) | `GgenIgniter.Receipt` (`.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`) |
|---|---|---|
| **Purpose** | **Current-State Cache**: Tracks what the most recent successful reconciliation wrote | **Historical Evidence**: Complete audit trail of every reconciliation attempt |
| **Lifecycle Advancement** | Advances **only** on verified `:alive` standing | Appended on **every** admitted attempt (`:alive`, `:refused`, `:compensated`, `:build_broken`) |
| **Write Discipline** | Atomic rename via temporary file (`Manifest.persist!/2`) | Append-only file writes (`File.write!/3` with `[:append]`) |
| **Failure Recovery** | Atomic swap prevents partial overwrites | Bounded date-partitioned lines; torn final line discarded on recovery |
| **State Retention** | Overwritten upon next successful reconciliation | Permanent, append-only chronological log |

#### Why Both Records Are Necessary
If files are actuated on disk and verification subsequently fails, Reactor compensation restores prior on-disk bytes. In a manifest-only system, no evidence of the physical actuation or failure loop remains once files are restored. The process receipt preserves operational evidence (e.g., actuation start, changed files, failure reasons, and hash restoration checks).

---

## 2. Receipt Schema & Struct Fields

The Elixir struct `%GgenIgniter.Receipt{}` is defined in [`lib/ggen_igniter/receipt.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/receipt.ex#L104-L130):

```elixir
defstruct id: nil,
          recipe_key: nil,
          standing: nil,
          started_at: nil,
          finished_at: nil,
          pre_run_hash: nil,
          post_run_hash: nil,
          files: [],
          events: [],
          reason: nil,
          metadata: %{}
```

### Field Reference & Mapping

| Field | Type | Description | Intended / Canonical Specification Mapping |
|---|---|---|---|
| `id` | `String.t()` | Unique identifier prefixed with `"rcpt_"` and 16 random lower-hex characters (e.g., `"rcpt_7f3a8b1c2d4e5f60"`). Generated via `:crypto.strong_rand_bytes(8)`. | Canonical `receipt_id`. |
| `recipe_key` | `String.t() \| nil` | The template-to-output identifier string (`"template_path=>out_template"`) or `nil` for multi-target / refused runs. | Identifies the recipe definition. |
| `standing` | `standing()` | Closed-set atom: `:alive`, `:refused`, `:compensated`, `:build_broken`. | Process standing taxonomy. |
| `started_at` | `String.t()` | ISO 8601 UTC timestamp string of execution start. | `timestamp` / start boundary. |
| `finished_at` | `String.t()` | ISO 8601 UTC timestamp string of execution completion. | `timestamp` / finish boundary. |
| `pre_run_hash` | `String.t() \| nil` | `"sha256:" <> hex` digest over the sorted `{path, content_or_nil}` pre-image of touched files. | Pre-actuation integrity hash. |
| `post_run_hash` | `String.t() \| nil` | `"sha256:" <> hex` digest over the sorted `{path, content_or_nil}` post-image of touched files. | Post-actuation integrity hash. |
| `files` | `[String.t()]` | List of relative file paths touched or targeted by this run. | Target artifacts. |
| `events` | `[map()]` | Ordered list of OCEL-shaped event maps emitted during the attempt. | OCEL 2.0 event log payload. |
| `reason` | `String.t() \| nil` | Human-readable explanation of refusal or failure reason (`nil` on `:alive`). | Error diagnostics. |
| `metadata` | `map()` | Arbitrary string-keyed payload map containing contextual attributes (see below). | Extended metadata fields (`engine`, `ontology_digest`, `outcomes`, `pack_id`, `version`). |

### Metadata Fields Mapping

Additional canonical execution properties are stored within the `metadata` map:

- **`ontology_digest`**: Captured as `metadata["graph_hash"]` (`"sha256:" <> hex` digest of the loaded ontology file).
- **`engine`**: Recorded in metadata or query event logs (e.g., `"oxigraph"`, `"sparql"`, `"qlever"`).
- **`outcomes`**: Stored as `metadata["outcome"]` (`"written"`, `"unchanged"`, `"skipped_exists"`, `"skipped_match"`) and aligned with `GgenIgniter.WriteOutcome`.
- **`target_count`**: Integer count of evaluated targets (`metadata["target_count"]`).
- **`manifest_promotion`**: Manifest promotion status (`"promoted"`, `"{:pending, reason}"`, `":unchanged"`).
- **`failed_step` / `raw_error`**: Detailed diagnostic context on failure paths (`metadata["failed_step"]`, `metadata["raw_error"]`).

---

## 3. Storage Format & Serialization

### Date-Partitioned JSONL Path
Receipts are written to:
```
<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl
```
- Date-partitioning (`Receipt.path/2`) ensures individual log files remain bounded in size.
- The path is calculated from `started_at` (defaulting to current UTC date).

### Serialized JSON Structure
Each attempt produces exactly one serialized JSON line:

```json
{
  "id": "rcpt_a1b2c3d4e5f60718",
  "recipe_key": "priv/ggen/packs/resource.ex.eex=>lib/support/<%= resource %>.ex",
  "standing": "compensated",
  "started_at": "2026-08-27T16:51:29.000000Z",
  "finished_at": "2026-08-27T16:51:29.050000Z",
  "pre_run_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "post_run_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "files": ["lib/support/ticket.ex"],
  "events": [
    {
      "id": "ev_1122334455667788",
      "activity": "ACTUATION_STARTED",
      "time": "2026-08-27T16:51:29.010000Z",
      "objects": [{"type": "file", "id": "lib/support/ticket.ex"}],
      "attributes": {"paths": ["lib/support/ticket.ex"]}
    },
    {
      "id": "ev_99aabbccddeeff00",
      "activity": "FILES_CHANGED",
      "time": "2026-08-27T16:51:29.020000Z",
      "objects": [{"type": "file", "id": "lib/support/ticket.ex"}],
      "attributes": {"paths": ["lib/support/ticket.ex"]}
    },
    {
      "id": "ev_0123456789abcdef",
      "activity": "VERIFICATION_FAILED",
      "time": "2026-08-27T16:51:29.030000Z",
      "objects": [],
      "attributes": {"reason_type": "build_broken", "message": "syntax error before: 'end'"}
    },
    {
      "id": "ev_fedcba9876543210",
      "activity": "COMPENSATION_STARTED",
      "time": "2026-08-27T16:51:29.040000Z",
      "objects": [{"type": "file", "id": "lib/support/ticket.ex"}],
      "attributes": {"paths": ["lib/support/ticket.ex"]}
    },
    {
      "id": "ev_aabbccddeeff0011",
      "activity": "FILES_RESTORED",
      "time": "2026-08-27T16:51:29.050000Z",
      "objects": [{"type": "file", "id": "lib/support/ticket.ex"}],
      "attributes": {
        "paths": ["lib/support/ticket.ex"],
        "pre_run_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "post_run_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "matches_pre_run_hash": true
      }
    }
  ],
  "reason": "verification failed (mix compile): syntax error before: 'end'",
  "metadata": {
    "failed_step": ":verify",
    "raw_error": "{:compile_failed, \"syntax error before: 'end'\"}",
    "graph_hash": "sha256:36666c437cf2be158e6544305f9d3f716b8d419fe6783caafba40dc4f8a1600b"
  }
}
```

---

## 4. API & Core Functions

Defined in [`lib/ggen_igniter/receipt.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/receipt.ex):

- **`Receipt.standings/0`**: Returns `@standings` (`[:alive, :refused, :compensated, :build_broken]`).
- **`Receipt.new/1`**: Instantiates `%Receipt{}` from keyword list or map. Enforces that `:standing` is a valid member of `@standings` (raises `ArgumentError` on invalid standing). Automatically generates `id`, `started_at`, and `finished_at` if omitted.
- **`Receipt.hash_entries/1`**: Order-independent SHA-256 digest over `[{path, content_or_nil}]`. Formats missing/absent files as `path <> ":absent"`.
- **`Receipt.hash_files/1`**: Reads physical files on disk and hashes their real contents using `hash_entries/1`.
- **`Receipt.to_json_map/1`**: Converts a `%Receipt{}` struct into a `Jason`-encodable string-keyed map.
- **`Receipt.append!/2`**: Appends the JSON line representation to `<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`.
- **`Receipt.read_all!/1`**: Reads all `.jsonl` partition files under `.ggen_igniter/receipts/` in sorted chronological order. Returns `[]` if directory does not exist.

---

## 5. Naming Disambiguation: Controller `record.receipt`

In [`lib/ggen_igniter/controller.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/controller.ex#L236-L247), the `GenServer` state stores an in-memory reconciliation summary map also named `receipt`:

```elixir
receipt: %{
  engine: result.engine,
  template_path: result.template_path,
  query_count: result.query_count,
  total_rows: result.total_rows,
  mode: result.mode,
  out_path: result.out_path,
  outcome: result.outcome,
  notice: result.notice,
  opts: reconcile_opts
}
```

> [!IMPORTANT]
> `record.receipt` in `Controller` is an ephemeral in-memory map representing single-target legacy return data. It does **not** persist to disk, does not contain OCEL events or standing atoms, and is distinct from `%GgenIgniter.Receipt{}`.

---

## 6. Verification & Test Evidence

All receipt properties and operations are verified without mocks:

```bash
$ mix test test/ggen_igniter_receipt_test.exs test/ggen_igniter_reconcile_reactor_test.exs test/ggen_igniter_finalize_evidence_ordering_test.exs
Running ExUnit with seed: ..., max_cases: 32
............................
Finished in 3.2 seconds
28 tests, 0 failures
```

### Verified Properties
1. **Closed Set Enforcement**: `Receipt.new(%{standing: :invalid})` raises `ArgumentError` ([`test/ggen_igniter_receipt_test.exs:34-38`](file:///Users/sac/ggen_igniter/test/ggen_igniter_receipt_test.exs#L34-L38)).
2. **Order-Independent Hashing**: `hash_entries([{"a", "1"}, {"b", "2"}]) == hash_entries([{"b", "2"}, {"a", "1"}])` ([`test/ggen_igniter_receipt_test.exs:50-54`](file:///Users/sac/ggen_igniter/test/ggen_igniter_receipt_test.exs#L50-L54)).
3. **Absence Hashing**: Files that do not exist hash as `:absent` distinct from empty/content files ([`test/ggen_igniter_receipt_test.exs:56-60`](file:///Users/sac/ggen_igniter/test/ggen_igniter_receipt_test.exs#L56-L60)).
4. **Append-Only Integrity**: Multiple appends preserve strict chronological order without truncating prior lines ([`test/ggen_igniter_receipt_test.exs:129-139`](file:///Users/sac/ggen_igniter/test/ggen_igniter_receipt_test.exs#L129-L139)).
5. **Pre/Post Hash Identity on Compensation**: Verified under real compilation failure ([`test/ggen_igniter_reconcile_reactor_test.exs:191-291`](file:///Users/sac/ggen_igniter/test/ggen_igniter_reconcile_reactor_test.exs#L191-L291)).
