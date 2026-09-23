# HANDWRITTEN — the 1% ledger

Law: `priv/ggen/dfcm-agent-pack/ontology.ttl` (DfCM hand-writing gate). A hand-written
product artifact is admitted only when no admitted pack/generator expresses the semantic
element, an `UNSUPPORTED(generator, element)` row names the exact gap in the owning
ontology, and a row appears here. The ledger must shrink monotonically per milestone;
growth requires a paydown plan in the same change.

Format: `path | semantic element | missing capability | intended owner pack | date`

---

test/ggen_igniter_semantic_jira_pack_test.exs | Chicago-style, no-mock ExUnit integration proof of semantic-jira-pack's full pipeline (canonical WorkOrder graph -> oxigraph/sparql admission -> for-each Reactor render -> real filesystem actuation -> durable GgenIgniter receipts -> byte-identical replay; includes falsifier, DO fail-closed, and promotion-boundary proofs) | no admitted generator manufactures pack-integration proof tests — the only test-manufacturing families (beam4pm-bench-pack, chicago-fault-injection-pack) emit domain-specific benchmark/fault-injection specs, and pack gates verify admission data, not end-to-end pipeline behaviour | semantic-jira-pack: extend the test-manufacturing family with a pack-integration-proof generator (ontology facts + template over the pack's own manifest/gates); when admitted, this row and the `sj:ledger-unsupported-001` UNSUPPORTED row retire | 2026-09-19
lib/ggen_igniter/semantic_jira/fleet_observation.ex | git/gh probe execution and output parsing for `mix semantic_jira.observe --fleet` (for-each-ref ahead/behind, ls-remote --symref delta, worktree list + status --porcelain, stash list, gh pr list, gh api check-runs); the Turtle shape is `runtime-templates/fleet_observation.ttl.eex` and the registry read is `runtime-queries/fleet_repositories.rq` | UNSUPPORTED(generator-capability): no admitted pack or generator expresses subprocess probes or their parse grammar | semantic-jira-pack: a probe-pack whose ontology declares each probe (argv, parse grammar, emitted sj: term) and whose template manufactures the probe module; when admitted, this row, the test row below and `sj:ledger-unsupported-002` retire | 2026-09-22
test/ggen_igniter_semantic_jira_fleet_observe_test.exs | Chicago-style proof of fleet observation over real tmp git repositories (bare remote, clones, linked dirty worktree, stash; two task runs byte-identical modulo prov:endedAtTime) | same gap as the row above: no generator manufactures probe-module proof tests | semantic-jira-pack probe-pack (as above) | 2026-09-22
