# ggen_igniter reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### GgenIgniter.SemanticJira.Bootstrap.Graph

| `capabilities` | function | capabilities/2 |  |  |  |  |

| `checkpoints` | function | checkpoints/2 |  |  |  |  |

| `fleet_rows` | function | fleet_rows/2 |  |  |  |  |

| `json_orders` | function | json_orders/2 |  |  |  |  |

| `local_name` | function | local_name/1 |  |  |  |  |

| `orders` | function | orders/3 |  |  |  |  |

| `parse` | function | parse/1 |  |  |  |  |

| `query_names` | function | query_names/0 |  |  |  |  |

| `read_queries` | function | read_queries/1 |  |  |  |  |

| `root` | function | root/2 |  |  |  |  |

| `sj` | function | sj/0 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `tuple_digest` | function | tuple_digest/1 |  |  |  |  |

| `order` | type | @type order :: %{ required(:id) => String.t(), required(:iri) => String.t() | nil, required(:source) => String.t(), required(:fields) => %{String.t() => [String.t()]}, required(:kernel) => map(), required(:tuple) => {:ok, map(), String.t()} | {:incomplete | :ambiguous, String.t()} } |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `capabilities` | function | capabilities/2 |  |  |  |  |

| `checkpoints` | function | checkpoints/2 |  |  |  |  |

| `fleet_rows` | function | fleet_rows/2 |  |  |  |  |

| `json_orders` | function | json_orders/2 |  |  |  |  |

| `local_name` | function | local_name/1 |  |  |  |  |

| `orders` | function | orders/3 |  |  |  |  |

| `parse` | function | parse/1 |  |  |  |  |

| `query_names` | function | query_names/0 |  |  |  |  |

| `read_queries` | function | read_queries/1 |  |  |  |  |

| `root` | function | root/2 |  |  |  |  |

| `sj` | function | sj/0 |  |  |  |  |

| `term` | function | term/1 |  |  |  |  |

| `tuple_digest` | function | tuple_digest/1 |  |  |  |  |

| `order` | type | @type order :: %{ required(:id) => String.t(), required(:iri) => String.t() | nil, required(:source) => String.t(), required(:fields) => %{String.t() => [String.t()]}, required(:kernel) => map(), required(:tuple) => {:ok, map(), String.t()} | {:incomplete | :ambiguous, String.t()} } |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
