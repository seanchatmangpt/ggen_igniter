# ggen_igniter reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### GgenIgniter.SemanticJira.KernelDifferential

| `calibrate` | function | calibrate/1 |  |  |  |  |

| `calibration_cases` | function | calibration_cases/0 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `closure` | function | closure/2 |  |  |  |  |

| `differs?` | function | differs?/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `evaluate_shapes` | function | evaluate_shapes/4 |  |  |  |  |

| `localize` | function | localize/7 |  |  |  |  |

| `mutate` | function | mutate/3 |  |  |  |  |

| `mutation_ids` | function | mutation_ids/0 |  |  |  |  |

| `order_iri` | function | order_iri/1 |  |  |  |  |

| `order_iris` | function | order_iris/1 |  |  |  |  |

| `owned_predicates` | function | owned_predicates/0 |  |  |  |  |

| `prepare` | function | prepare/1 |  |  |  |  |

| `probe` | function | probe/1 |  |  |  |  |

| `restrict_targets` | function | restrict_targets/3 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `shacl_kernel` | function | shacl_kernel/0 |  |  |  |  |

| `slice_tree` | function | slice_tree/1 |  |  |  |  |

| `slices` | function | slices/1 |  |  |  |  |

| `to_json_term` | function | to_json_term/1 |  |  |  |  |

| `to_turtle` | function | to_turtle/1 |  |  |  |  |

| `vocabulary` | function | vocabulary/1 |  |  |  |  |

| `work_graph` | function | work_graph/3 |  |  |  |  |

| `input` | type | @type input :: %{ data_ttl: String.t(), shapes_ttl: String.t(), data_graph: RDF.Graph.t(), shapes_graph: RDF.Graph.t() } |  |  |  |  |

| `kernel` | type | @type kernel :: {String.t(), (input() -> verdict())} |  |  |  |  |

| `leaf` | type | @type leaf :: {String.t(), String.t(), String.t(), RDF.Graph.t()} |  |  |  |  |

| `verdict` | type | @type verdict :: %{ status: :conforms | :refused | :error, violations: non_neg_integer() | nil, detail: String.t() } |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `calibrate` | function | calibrate/1 |  |  |  |  |

| `calibration_cases` | function | calibration_cases/0 |  |  |  |  |

| `classify` | function | classify/1 |  |  |  |  |

| `closure` | function | closure/2 |  |  |  |  |

| `differs?` | function | differs?/1 |  |  |  |  |

| `encode` | function | encode/1 |  |  |  |  |

| `evaluate` | function | evaluate/2 |  |  |  |  |

| `evaluate_shapes` | function | evaluate_shapes/4 |  |  |  |  |

| `localize` | function | localize/7 |  |  |  |  |

| `mutate` | function | mutate/3 |  |  |  |  |

| `mutation_ids` | function | mutation_ids/0 |  |  |  |  |

| `order_iri` | function | order_iri/1 |  |  |  |  |

| `order_iris` | function | order_iris/1 |  |  |  |  |

| `owned_predicates` | function | owned_predicates/0 |  |  |  |  |

| `prepare` | function | prepare/1 |  |  |  |  |

| `probe` | function | probe/1 |  |  |  |  |

| `restrict_targets` | function | restrict_targets/3 |  |  |  |  |

| `sha256` | function | sha256/1 |  |  |  |  |

| `shacl_kernel` | function | shacl_kernel/0 |  |  |  |  |

| `slice_tree` | function | slice_tree/1 |  |  |  |  |

| `slices` | function | slices/1 |  |  |  |  |

| `to_json_term` | function | to_json_term/1 |  |  |  |  |

| `to_turtle` | function | to_turtle/1 |  |  |  |  |

| `vocabulary` | function | vocabulary/1 |  |  |  |  |

| `work_graph` | function | work_graph/3 |  |  |  |  |

| `input` | type | @type input :: %{ data_ttl: String.t(), shapes_ttl: String.t(), data_graph: RDF.Graph.t(), shapes_graph: RDF.Graph.t() } |  |  |  |  |

| `kernel` | type | @type kernel :: {String.t(), (input() -> verdict())} |  |  |  |  |

| `leaf` | type | @type leaf :: {String.t(), String.t(), String.t(), RDF.Graph.t()} |  |  |  |  |

| `verdict` | type | @type verdict :: %{ status: :conforms | :refused | :error, violations: non_neg_integer() | nil, detail: String.t() } |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
