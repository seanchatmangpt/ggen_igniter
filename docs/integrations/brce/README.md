# BRCE integration

**Status:** PLANNED adapter contract  
**Normative source:** BRCE Protocol RFC v0.1 in `engineering-standards`

`ggen_igniter` does not define BRCE and does not grant BRCE authority.

Its role is manufacturing:

[
Ontology
\rightarrow SPARQL
\rightarrow Template
\rightarrow GeneratedArtifact
]

For BRCE, the intended projection is:

[
O^*
\xrightarrow{ggen\_igniter}
BRCE/TLA^+ artifacts
]

Generation is CONSTRUCT, not DO.

[
GeneratedAction \not\Rightarrow Authority
]

[
GeneratedTLA \not\Rightarrow Verified
]

## Intended adapter surfaces

The integration is split into two reusable packs:

1. **`brce-contract-pack`**
   - projects a canonical ontology into BRCE request/action/authority/receipt schemas;
   - generates conformance fixtures and adapter skeletons;
   - never performs governed external consequence.

2. **`tla-plus-pack`**
   - projects transition semantics into `.tla` and `.cfg` artifacts;
   - models BRCE safety/liveness properties;
   - does not run TLC/TLAPS as part of semantic compilation unless a separate verification court explicitly invokes them.

See [TLA+ adapter contract](./tla-plus-adapter.md).

## Ownership

| Concern | Owner |
|---|---|
| BRCE semantics | standalone BRCE RFC |
| canonical ontology | ecosystem semantic source / pack input |
| RDF load + SPARQL query | `ggen_igniter` |
| artifact rendering | `ggen_igniter` |
| TLA+ syntax/semantics validation | SANY/TLC/TLAPS adapter |
| execution authority | external BRCE authority broker |
| sealed evidence | receipt provider such as Affidavit |
| standing | external admitted policy |

## Hard exclusions

This adapter MUST NOT:

- infer authority from ontology facts unless the BRCE authority broker verifies a grant;
- treat successful rendering as model-check success;
- treat model-check success as production execution;
- treat a generated receipt-shaped artifact as a verified receipt;
- patch generated projections by hand when the canonical graph/template should change instead.

## Status ceiling

This document is a design/adoption contract. No BRCE or TLA+ pack is claimed implemented by this PR.
