# HANDWRITTEN — the 1% ledger

Law: `priv/ggen/dfcm-agent-pack/ontology.ttl` (DfCM hand-writing gate). A hand-written
product artifact is admitted only when no admitted pack/generator expresses the semantic
element, an `UNSUPPORTED(generator, element)` row names the exact gap in the owning
ontology, and a row appears here. The ledger must shrink monotonically per milestone;
growth requires a paydown plan in the same change.

Format: `path | semantic element | missing capability | intended owner pack | date`

---

test/ggen_igniter_semantic_jira_pack_test.exs | Chicago-style, no-mock ExUnit integration proof of semantic-jira-pack's full pipeline (canonical WorkOrder graph -> oxigraph/sparql admission -> for-each Reactor render -> real filesystem actuation -> durable GgenIgniter receipts -> byte-identical replay; includes falsifier, DO fail-closed, and promotion-boundary proofs) | no admitted generator manufactures pack-integration proof tests — the only test-manufacturing families (beam4pm-bench-pack, chicago-fault-injection-pack) emit domain-specific benchmark/fault-injection specs, and pack gates verify admission data, not end-to-end pipeline behaviour | semantic-jira-pack: extend the test-manufacturing family with a pack-integration-proof generator (ontology facts + template over the pack's own manifest/gates); when admitted, this row and the `sj:ledger-unsupported-001` UNSUPPORTED row retire | 2026-09-19
