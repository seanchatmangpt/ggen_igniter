# ggen_igniter reference

<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-BEGIN: reference body is RIGID                -->
<!-- Every row below is rendered from queries/ast_extract.rq.      -->
<!-- Agents MUST NOT add, edit, reorder, or remove any row or      -->
<!-- table cell. Prose outside the fenced slot below is refused    -->
<!-- by the doc_quality court.                                     -->
<!-- ============================================================= -->

## Modules


### GgenIgniter.Refusals

| `all` | function | all/0 |  |  |  |  |

| `count` | function | count/0 |  |  |  |  |

| `fetch` | function | fetch/1 |  |  |  |  |

| `format` | function | format/2 |  |  |  |  |

| `known?` | function | known?/1 |  |  |  |  |

| `markdown` | function | markdown/0 |  |  |  |  |

| `parse` | function | parse/1 |  |  |  |  |

| `scan_reason_atoms` | function | scan_reason_atoms/1 |  |  |  |  |

| `wrapped_markdown` | function | wrapped_markdown/0 |  |  |  |  |

| `wrapped_reasons` | function | wrapped_reasons/0 |  |  |  |  |

| `code` | type | @type code :: atom() |  |  |  |  |

| `entry` | type | @type entry :: %{ code: code(), family: String.t(), retryable: boolean(), owner: String.t(), fix_hint: String.t(), broken_term: String.t(), not_applicable_reason: String.t() | nil, hint_group: String.t() | nil, example: String.t() } |  |  |  |  |

| `wrapped` | type | @type wrapped :: %{reason: String.t(), parent: code(), note: String.t()} |  |  |  |  |



<!-- AGENT-FORBIDDEN-END -->

## Signature/type/default/errors table

<!-- RIGID table: header order is fixed; rows come only from the query. -->

| Item | Type | Signature | Params | Defaults | Errors | Invariants |
|------|------|-----------|--------|----------|--------|------------|

| `all` | function | all/0 |  |  |  |  |

| `count` | function | count/0 |  |  |  |  |

| `fetch` | function | fetch/1 |  |  |  |  |

| `format` | function | format/2 |  |  |  |  |

| `known?` | function | known?/1 |  |  |  |  |

| `markdown` | function | markdown/0 |  |  |  |  |

| `parse` | function | parse/1 |  |  |  |  |

| `scan_reason_atoms` | function | scan_reason_atoms/1 |  |  |  |  |

| `wrapped_markdown` | function | wrapped_markdown/0 |  |  |  |  |

| `wrapped_reasons` | function | wrapped_reasons/0 |  |  |  |  |

| `code` | type | @type code :: atom() |  |  |  |  |

| `entry` | type | @type entry :: %{ code: code(), family: String.t(), retryable: boolean(), owner: String.t(), fix_hint: String.t(), broken_term: String.t(), not_applicable_reason: String.t() | nil, hint_group: String.t() | nil, example: String.t() } |  |  |  |  |

| `wrapped` | type | @type wrapped :: %{reason: String.t(), parent: code(), note: String.t()} |  |  |  |  |


<!-- ============================================================= -->
<!-- AGENT-FORBIDDEN-END: nothing below this line may describe     -->
<!-- code behavior.                                                -->
<!-- ============================================================= -->
