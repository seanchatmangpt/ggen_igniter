# ggen_igniter reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### GgenIgniter.Receipt

| `append!` | function | append!/2 |  |  |  |  |

| `compute_receipt_hash` | function | compute_receipt_hash/1 |  |  |  |  |

| `dir` | function | dir/1 |  |  |  |  |

| `hash_entries` | function | hash_entries/1 |  |  |  |  |

| `hash_files` | function | hash_files/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/2 |  |  |  |  |

| `path` | function | path/2 |  |  |  |  |

| `read_all!` | function | read_all!/1 |  |  |  |  |

| `reconstruct_standing` | function | reconstruct_standing/2 |  |  |  |  |

| `standings` | function | standings/0 |  |  |  |  |

| `to_json_map` | function | to_json_map/1 |  |  |  |  |

| `tool_version` | function | tool_version/0 |  |  |  |  |

| `GgenIgniter.Receipt` | struct | defstruct id: nil, recipe_key: nil, standing: nil, started_at: nil, finished_at: nil, pre_run_hash: nil, post_run_hash: nil, files: [], events: [], reason: nil, metadata: %{}, and every pre-existing field/function
            # above is unchanged. See the doc comments on `new/2` and
            # `compute_receipt_hash/1` for what each is for.
            schema_version: "1", tool_version: nil, operation: nil, inputs: [], queries: [], engine: nil, outputs: [], skipped_outputs: [], commands: [], source_hash: nil, plan_hash: nil, pre_state_hash: nil, result_hash: nil, parent_hash: nil, receipt_hash: nil, completed_at: nil, sha256 hex from
            # `GgenIgniter.PackLock.digest/1`. Emitted by `to_json_map/1` only
            # when non-nil so pre-existing receipt_hash values stay stable.
            pack_name: nil, pack_digest: nil |  |  |  |  |

| `standing` | type | @type standing :: :alive | :refused | :compensated | :build_broken | :compensation_failed |  |  |  |  |

| `t` | type | @type t :: %__MODULE__{ id: String.t(), recipe_key: String.t() | nil, standing: standing(), started_at: String.t(), finished_at: String.t(), pre_run_hash: String.t() | nil, post_run_hash: String.t() | nil, files: [String.t()], events: [map()], reason: String.t() | nil, metadata: map(), schema_version: String.t(), tool_version: String.t() | nil, operation: String.t() | nil, inputs: list(), queries: list(), engine: String.t() | nil, outputs: list(), skipped_outputs: list(), commands: list(), source_hash: String.t() | nil, plan_hash: String.t() | nil, pre_state_hash: String.t() | nil, result_hash: String.t() | nil, parent_hash: String.t() | nil, receipt_hash: String.t() | nil, completed_at: String.t() | nil, pack_name: String.t() | nil, pack_digest: String.t() | nil } |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `append!` | function | append!/2 |  |  |  |  |

| `compute_receipt_hash` | function | compute_receipt_hash/1 |  |  |  |  |

| `dir` | function | dir/1 |  |  |  |  |

| `hash_entries` | function | hash_entries/1 |  |  |  |  |

| `hash_files` | function | hash_files/1 |  |  |  |  |

| `new` | function | new/1 |  |  |  |  |

| `new` | function | new/2 |  |  |  |  |

| `path` | function | path/2 |  |  |  |  |

| `read_all!` | function | read_all!/1 |  |  |  |  |

| `reconstruct_standing` | function | reconstruct_standing/2 |  |  |  |  |

| `standings` | function | standings/0 |  |  |  |  |

| `to_json_map` | function | to_json_map/1 |  |  |  |  |

| `tool_version` | function | tool_version/0 |  |  |  |  |

| `GgenIgniter.Receipt` | struct | defstruct id: nil, recipe_key: nil, standing: nil, started_at: nil, finished_at: nil, pre_run_hash: nil, post_run_hash: nil, files: [], events: [], reason: nil, metadata: %{}, and every pre-existing field/function
            # above is unchanged. See the doc comments on `new/2` and
            # `compute_receipt_hash/1` for what each is for.
            schema_version: "1", tool_version: nil, operation: nil, inputs: [], queries: [], engine: nil, outputs: [], skipped_outputs: [], commands: [], source_hash: nil, plan_hash: nil, pre_state_hash: nil, result_hash: nil, parent_hash: nil, receipt_hash: nil, completed_at: nil, sha256 hex from
            # `GgenIgniter.PackLock.digest/1`. Emitted by `to_json_map/1` only
            # when non-nil so pre-existing receipt_hash values stay stable.
            pack_name: nil, pack_digest: nil |  |  |  |  |

| `standing` | type | @type standing :: :alive | :refused | :compensated | :build_broken | :compensation_failed |  |  |  |  |

| `t` | type | @type t :: %__MODULE__{ id: String.t(), recipe_key: String.t() | nil, standing: standing(), started_at: String.t(), finished_at: String.t(), pre_run_hash: String.t() | nil, post_run_hash: String.t() | nil, files: [String.t()], events: [map()], reason: String.t() | nil, metadata: map(), schema_version: String.t(), tool_version: String.t() | nil, operation: String.t() | nil, inputs: list(), queries: list(), engine: String.t() | nil, outputs: list(), skipped_outputs: list(), commands: list(), source_hash: String.t() | nil, plan_hash: String.t() | nil, pre_state_hash: String.t() | nil, result_hash: String.t() | nil, parent_hash: String.t() | nil, receipt_hash: String.t() | nil, completed_at: String.t() | nil, pack_name: String.t() | nil, pack_digest: String.t() | nil } |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
