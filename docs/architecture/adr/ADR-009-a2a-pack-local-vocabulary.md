# ADR-009: Pack-local `a2a:` vocabulary for the Semantic Jira A2A projection

Status: accepted (2026-09-20). Milestone v26.9.19.

## Context

The Semantic Jira pack must expose work orders to `ash_a2a` so agents can
observe and act on them over the A2A protocol. The pack is ontology-first: the
canonical RDF graph is the source, and the Ash surface is a generated
projection. No hand-written Ash is allowed (`.claude/hooks/refuse-handwritten-ash.sh`).

## Decision

1. Declare a minimal `a2a:` vocabulary inside
   `priv/ggen/semantic-jira-pack/ontology.ttl` (`a2a:Task`, `a2a:Skill`,
   `a2a:AgentCard`, `a2a:TaskState` with 8 individuals, `a2a:StateMapping`).
   No public RDF ontology for A2A was found. That is UNVERIFIED (a search, not
   a proof of absence); replace the vocabulary if one is later confirmed.
2. `sj:WorkOrder rdfs:subClassOf a2a:Task`, `sj:Action rdfs:subClassOf a2a:Skill`.
   An action is an exposed skill only with `a2a:exposed true` and an ALIVE
   generator capability (`gi:GeneratorCapability`).
3. Standing -> task state is data (`a2a:StateMapping`), read by SPARQL gate
   `061_a2a_state_map.rq`. `completed` needs ALIVE with a valid receipt.
   UNSUPPORTED and REFUSED both map to `rejected` with distinct reason codes.
4. The Ash resource is manufactured by composing the real generators
   (`ash.gen.domain`, `ash.gen.resource --extend ets`, `ash_a2a.install`) from
   template `a2a_manufacture.ex.eex`. `lib/` gains no Ash reference; `ash_a2a`,
   `plug`, `bandit` are `only: [:dev, :test]`.
5. Push and Publish (`a2a:forbidsCapability`) are refusals, never skills.
   `external_do` skills are UNSUPPORTED(generator-capability): `ash_a2a.install`
   emits no `consequence:` override.

## Consequences

- ash_a2a 26.9.17 serves task states as `TASK_STATE_<UPPER>`;
  `SemanticA2A.wire_state/1` is the single mapping point.
- `ash_a2a.install` appends `a2a do end` on every run; the manufactured step is
  guarded by an installed-marker check.
- Ash >= 3.33 needs `config :ash, default_string_length_count:` for ash_ai/ash_a2a
  to compile; set in `config/config.exs`.
