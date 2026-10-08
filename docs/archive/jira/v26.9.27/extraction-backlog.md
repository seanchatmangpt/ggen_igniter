# v26.9.27 semantic extraction backlog (epoch-005)

The operating law this backlog serves: **READ OLD → EXTRACT → GENERALIZE → PACK → GENERATE NEW → FALSIFY → DELETE OLD.** For each inventory family (inventory.md): what semantics live ONLY in code today, and which pack should own them after extraction. Extraction happens BEFORE the v26.10.1 boundary; an extraction receipt (admitted pack facts) is what licenses deleting the old implementation. A family with no code-only semantics claims "fully projected" with the carrying fact named.

Honest headline: most of this repo's semantics are code-only today. That is the backlog, not a failure — v26.10.1 cannot re-manufacture what was never extracted.

| module family | code-only semantics (not in any pack today) | owning pack after extraction | order |
|---|---|---|---|
| `ggen_igniter/{sync,engine,render,pack}.ex` — pack→render pipeline | the 5-stage sync contract: named-query → for-each row → EEx render → reconciliation manifest → atomic write; engine selection law (oxigraph default, sparql A/B, ORDER-BY corruption note); drift laws | new `ggen-sync-engine-pack` (ontology: pipeline stages as classes, gates as the .rq contract; template: manufacture task) | 1 |
| `ggen_igniter/{receipt,manifest,artifact_identity}.ex` — attribution machinery | receipt schema (standing closed set, five R fields), manifest outputs-as-identity, canonical path identity, receipts-admit attribution law (consumed by the epoch court) | new `manufacture-attribution-pack` | 1 |
| `ggen_igniter/semantic_jira/{shacl,kernel_differential,transition_log,authority,cli}.ex` | SHACL admission engine behavior (result_path, targetSubjectsOf, pattern anchoring), kernel event-sourcing law, authority trust roots (trust roots themselves ARE pack facts; the engine is code) | `semantic-jira-pack`: shapes already there; engine contract becomes pack facts (CLI template row already in HANDWRITTEN ledger) | 2 |
| `ggen_igniter/semantic_jira/{epoch_plan}.ex` + `ggen_igniter/epoch_*.ex` — epoch machinery | epoch boundary law: `sj:EpochBoundary` facts already extracted (this wave, epoch_boundary.rq + ontology.ttl); the court/enforcement remains code | `semantic-jira-pack` (facts landed this wave); court engine stays code with pack-carried parameters (glob, threshold) | 2 |
| `ggen_igniter/semantic_jira/{git_ground_truth,descriptor,observation,prose,reconciler,pack_health}.ex` | baseSha ground-truth jurisdiction law, descriptor shape, finding→candidate mapping (ledger row 2026-09-23 already names the CONSTRUCT-query paydown) | `semantic-jira-pack` | 3 |
| `ggen_igniter/{actuate,pending_actuation,ephemeral_manufacture,ephemeral_projection,controller}.ex` | actuation ceilings, compensation exclusions, ephemeral vs persisted projection disposition (`SemanticEpoch` invariants are code maps — extract to ontology facts) | new `actuation-ceiling-pack` (or extend `dfcm-agent-pack`) | 3 |
| `ggen_igniter/{query,query/*,native/*}.ex` + oxigraph NIF | engine binding law (already documented in sync moduledoc; the NIF is infrastructure, not semantics) | `ggen-sync-engine-pack` (wave 1 family) | 4 |
| `ggen_igniter/{semantic_a2a,semantic_work_order,semantic_epoch,ea,eds,enterprise_architecture}.ex`, `ggen_igniter/{gall,gall_ticket,discovery,stream,refactors,telemetry,reactors/*}` | domain projections (GALL semantic work, EDS claims, OCEL export, frontier planning) — each names its own projection contract in-moduledoc | one pack per family at extraction time (gall→GALL pack exists upstream; eds→`eds` family) | 4 |
| `mix/tasks/*` (21 shells) | strict option schemas + exit-code maps (CLI task template row: HANDWRITTEN 2026-09-23 names `templates/cli_task.ex.eex` as the paydown) | `semantic-jira-pack` / `ggen-sync-engine-pack` | 5 |

## Monotone extraction principle

1. Extraction is additive pack facts + gates; the old code keeps running until its replacement is manufactured and falsified.
2. v26.10.1 deletes a family's old implementation ONLY when: pack facts admitted (extraction receipt) AND fresh projection manufactured (generation receipt) AND `epoch.check --epoch v26.10.1` ALIVE.
3. A family left un-extracted at the boundary means its v26.10.1 replacement must be written as genuinely new implementation with ledgered residue — lawful but it grows the 1% ledger, which must then shrink by milestone end.
