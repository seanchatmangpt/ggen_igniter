# ggen_igniter reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### GgenIgniter.SemanticJira.Authority

| `admission_digest` | function | admission_digest/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `canonical_index` | function | canonical_index/1 |  |  |  |  |

| `canonical_path` | function | canonical_path/0 |  |  |  |  |

| `graph_digest` | function | graph_digest/1 |  |  |  |  |

| `index` | function | index/1 |  |  |  |  |

| `index_from` | function | index_from/1 |  |  |  |  |

| `index_receipt` | function | index_receipt/1 |  |  |  |  |

| `pin` | function | pin/2 |  |  |  |  |

| `pins` | function | pins/1 |  |  |  |  |

| `require_origin` | function | require_origin/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `trust_roots` | function | trust_roots/0 |  |  |  |  |

| `verify_origin` | function | verify_origin/3 |  |  |  |  |

| `digest` | type | @type digest :: String.t() |  |  |  |  |

| `index` | type | @type index :: %{ admitted: %{String.t() => digest()}, refused: %{String.t() => origin_refusal()}, source_graph: RDF.Graph.t(), source_digest: digest() } |  |  |  |  |

| `origin_refusal` | type | @type origin_refusal :: :order_absent | :origin_authority_missing | {:ambiguous_origin_authority, [String.t()]} | {:authority_not_admitted, String.t()} | {:authority_digest_mismatch, String.t()} | {:authority_type_mismatch, String.t()} | {:authority_not_pinned, String.t()} | {:authority_digest_invalid, String.t()} | {:authority_index_conflict, String.t()} | {:authority_index_unavailable, Path.t() | nil, term()} |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `admission_digest` | function | admission_digest/2 |  |  |  |  |

| `admit` | function | admit/2 |  |  |  |  |

| `canonical_index` | function | canonical_index/1 |  |  |  |  |

| `canonical_path` | function | canonical_path/0 |  |  |  |  |

| `graph_digest` | function | graph_digest/1 |  |  |  |  |

| `index` | function | index/1 |  |  |  |  |

| `index_from` | function | index_from/1 |  |  |  |  |

| `index_receipt` | function | index_receipt/1 |  |  |  |  |

| `pin` | function | pin/2 |  |  |  |  |

| `pins` | function | pins/1 |  |  |  |  |

| `require_origin` | function | require_origin/2 |  |  |  |  |

| `resolve` | function | resolve/2 |  |  |  |  |

| `trust_roots` | function | trust_roots/0 |  |  |  |  |

| `verify_origin` | function | verify_origin/3 |  |  |  |  |

| `digest` | type | @type digest :: String.t() |  |  |  |  |

| `index` | type | @type index :: %{ admitted: %{String.t() => digest()}, refused: %{String.t() => origin_refusal()}, source_graph: RDF.Graph.t(), source_digest: digest() } |  |  |  |  |

| `origin_refusal` | type | @type origin_refusal :: :order_absent | :origin_authority_missing | {:ambiguous_origin_authority, [String.t()]} | {:authority_not_admitted, String.t()} | {:authority_digest_mismatch, String.t()} | {:authority_type_mismatch, String.t()} | {:authority_not_pinned, String.t()} | {:authority_digest_invalid, String.t()} | {:authority_index_conflict, String.t()} | {:authority_index_unavailable, Path.t() | nil, term()} |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
