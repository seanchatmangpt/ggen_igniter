# 01-LANES-INDEX

Standing: UNVERIFIED

Materializes the session lane IDs (L01-L20, ERRC) as a repo index. Nothing here was run; every
lane's own notes say no compile and no `ggen sync` was executed. Pack root `P` =
`/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack`. Notes: `P/fragments/L<nn>-NOTES.md`.
Owner files per lane: `P/ontology.d/L<nn>-*.ttl`, `P/templates/L<nn>_*`,
`P/gates/L<nn>_*.rq`, `P/fixtures/L<nn>-*.ttl`, `P/fragments/L<nn>-NOTES.md`.
Every lane standing is UNVERIFIED. Trigger predicates for L03, L09-L11, L15, L16, L20 are
paraphrased from the notes; exact SPARQL lives in each lane's template frontmatter.

## Lanes

Format: lane, topic; trigger predicate; fragment module / output.

- L01 attributes in full; `aap:attrSpec`; `<Res>.L01Attributes` (`_l01.ex`) + enum modules.
- L02 relationships; `aap:relationship` or `aap:manage`; `<Res>.Relationships` (`_l02.ex`).
- L03 calculations; `aap:calculation`; `<Res>.CalculationsL03` (`_l03.ex`) + calc modules.
- L04 aggregates; `aap:aggregate`; `<Res>Aggregates` (`_l04.ex`).
- L05 identities, validations; `aap:identity` or `aap:validation`; `<Res>.L05` (`_l05.ex`).
- L06 changes, generic actions; `aap:l06Action`; `<Res>.L06` (`_l06.ex`) + hook/run modules.
- L07 Ash.Policy.Authorizer; `aap:policy`; `<Res>.L07Policies` (`_l07.ex`).
- L08 multitenancy, mounts; `aap:multitenancy`, domain `aap:mount`; `<Res>.TenancyL08`,
  `<Dom>.MountsL08`.
- L09 data layers; `aap:dataLayer`; `<Res>.DataLayer` (`_l09.ex`) + deps/aliases/config files.
- L10 code interfaces, domain config; interface/config/mount facts; `<Res>.L10`, `<Dom>.L10`.
- L11 notifiers, pub_sub; `aap:pubSub`, `aap:notifier`; `<Res>.L11PubSub` + notifier/server.
- L12 custom Ash types; `aap:typedAttribute`; `<Res>.TypesL12` (`_l12.ex`).
- L13 AshStateMachine on task lifecycle; `aap:stateMachine`; `<Res>.StateMachine` (`_l13.ex`).
- L14 AshOban, Delivery.Oban; `aap:obTrigger`, `aap:obSchedule`; `<Res>.L14Oban`
  (`_l14_oban.ex`) + config + worker.
- L15 Reactor; `aap:reactorFragment` and reactor facts; Reactor modules + `<Res>ReactorActions`.
- L16 ash_pplan; pplan workflow/provider/pack facts; standalone modules, no fragment.
- L17 complete AshA2A DSL; any L17 fact, domains with `aap:a2aConfigured "true"`;
  `<Res>.A2aL17`, `<Dom>.A2aL17`, `<Agent>.Configured`, endpoint, hooks config.
- L18 Spark custom DSL from TTL; `aap:sparkInstance`; `<Res>.SparkL18` + extension modules.
- L19 ea.graph.json (G2) and relock (G3); always emitted, `aap:eaDeclare` optional;
  `ea.graph.json`, igniter `pack_sync` (see `L19-g1-g3-design.md`).
- L20 courts and gates 040-047; court case facts; `test/courts/*_test.exs`, shim scripts.

## ERRC items

- E1: UNVERIFIED, no note file found under `P/fragments/`; owner unknown.
- E2: gates 010/020/030 widened to accept L01/L02/L06/L15 edges; owner `P/gates/010-030*.rq`,
  `P/fragments/ERRC-E2-gates.md`; UNVERIFIED.
- R1-R5: UNVERIFIED, no note files found; scope not recorded in the repo.
- C1: own doc `C1-*.md` in this directory (not owned by lane C2); UNVERIFIED.
- C2: this document set `01-*` through `09-*`; UNVERIFIED.
- C3: UNVERIFIED, no record found.

## Seam law (from `P/LANES.md`)

Lanes own only their prefixed files. Shared files (`ontology.ttl`, `resource.ex.tmpl`,
`domain.ex.tmpl`, `config.exs.tmpl`, `mix.exs.tmpl`) are coordinator-merged. Each lane's
`fragments: [...]` wiring line is a coordinator action listed in its NOTES file.

## See Also

[00-OVERVIEW](00-OVERVIEW.md) · [02-GAP-REGISTER](02-GAP-REGISTER.md) ·
[03-VERIFY-LADDER](03-VERIFY-LADDER.md) · [04-ASSUMPTIONS-TO-FALSIFY](04-ASSUMPTIONS-TO-FALSIFY.md)
