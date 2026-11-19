# L09 — semantic-jira-pack + digest fence + doc-work-order.shacl

Standing: PASS

Subject: `/Users/sac/ggen_igniter` on `origin/main` — pack SHACL admit, execute
digest fence, hybrid-pack EEx sync routing, and campaign `doc-work-order.shacl.ttl`
selection. Autoloop branches not merged (WIP acceptance red).

## Owned surfaces

| Surface | Path |
|---|---|
| Pack | `priv/ggen/semantic-jira-pack/` |
| Doc-graph SHACL | `shapes/doc-work-order.shacl.ttl` |
| Doc template | `templates/doc_work_order.ttl.tera` (stays under templates/; hybrid law) |
| Digest fence | `lib/ggen_igniter/semantic_jira/execute.ex` `recheck_target_pack_digest/4` |
| Hybrid routing | `lib/ggen_igniter/pack_frontmatter/sync.ex` `tera_pack?/1` |
| Fleet validator | `ggen-marketplace/scripts/validate_workgraphs.py` → doc-work-order shape |

## Courts (Chicago, real)

| Court | Exit | Evidence |
|---|---|---|
| `mix compile --warnings-as-errors` | 0 | clean |
| Pack SHACL `Shacl.validate_file(ontology, work-order.shacl)` | 0 | conforms=true shapes=27 violations=0 focus=259 |
| Golden WORKGRAPH vs `doc-work-order.shacl.ttl` | 0 | `validate_workgraphs.py --only ggen-marketplace` conforms True WO=6 |
| Digest fence + SHACL + target_pack + admit + hybrid dispatch | 0 | 61 passed (`--include integration`, focused files) |
| GoalCheckpoint suite | 0* | 38/39 under wave load; lone sync subprocess TimeoutError@5m; **isolate** `mix test …:622 --timeout 900000` → **1 passed in 141.6s** |
| `just sjira-loop dry-run` (friday fixture) | 0 | `dry_run_ok` admit=2/0 eligible=1 blocked=1 digests present |
| `tera_pack?("priv/ggen/semantic-jira-pack")` | false | hybrid EEx+Tera stays on ADR-0010 EEx path (FM-PACK-013 inverted polarity avoided) |

\*Load-induced 5m timeout only; timeout raised to 15m on the sync court.

## Repair landed this lane

- `tera_pack?/1`: require **no** `templates/*.eex` before classifying a pack as Tera
  (hybrid semantic-jira-pack with additive `doc_work_order.ttl.tera` must not flip
  witness `gates/*.rq` onto PackFrontmatter inverted polarity).
- GoalCheckpoint census: 27 shapes / 36 pack orders / 37 sync outputs.
- `render_ticket!/2`: merge `verify/*.unbound.rq` as `<stem>_unbound` (ADR-0010 parity
  with `mix ggen_igniter.sync`).
- Hybrid dispatch court: `dispatch_test.exs` refutes `tera_pack?` for semantic-jira-pack.

## SHAs

| Ref | SHA |
|---|---|
| Hybrid fix | `294902e` |
| Sync timeout raise | `89cb68f` |
| L09 receipt | `60457949a72ec671fe5cc45477f8ef77592ff1e7` |

## Standing

**PASS** — pack SHACL admit green, digest fence courts green, doc-work-order golden
conforms, hybrid sync EEx path verified (isolate EXIT=0), O→A→F dry-run EXIT=0.
Live actuation remains operator/sandbox-gated (L04).
