# Gate Non-Vacuity: .rq Gates and Refusing Fixtures

Standing: UNVERIFIED

Lane 11 of v26.11.17. Read-only static survey of the 196 `.rq` files under `priv/` (183 under
`priv/ggen/`, 13 under `priv/sa2a/`): which refusing gates have a fixture whose test asserts the
refusal, and which gates may be unable to fire. `mix` is not installed in this sandbox
(`which mix` printed nothing, exit 1), so no gate, fixture or test was executed; every behavioral
claim below is read from source and stays UNVERIFIED. "OBSERVED" marks a fact read directly from
a file or a grep count. Main result: the gate scoring convention is inconsistent across three
code paths, several offender-shaped gates sit in `gates/` where ADR 0010 scores them inverted,
and at least 33 refusal codes or gates have no test that names them. Aliases: `P` =
`priv/ggen`, `T` = `test`.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| G01 | No run possible here: mix absent | OBSERVED | `which mix` -> no output |
| G02 | CLAUDE.md says default engine is oxigraph + sparql limits; code has graphlaw only | OBSERVED | `lib/ggen_igniter/engine.ex:11-16`, `:29-31`; CLAUDE.md "What this is" |
| G03 | `docs/status.md` rows still list `--engine oxigraph` as IMPLEMENTED default | OBSERVED | `docs/status.md:73` vs `engine.ex:16` (fetch! refuses all but graphlaw) |
| G04 | Gate comments cite "sparql engine limitation" for MINUS; engine is retired | OBSERVED | `P/receipted-extension-pack/gates/000_violations.rq:3`, `P/igniter-task-pack/gates/030_refusals.rq:3` |
| G05 | Scoring conflict: GateVerify = rows>=1 pass; PackFrontmatter = any row refuses | OBSERVED | `gate_verify.ex:11-20` vs `pack_frontmatter/sync.ex:115-135` |
| G06 | Offender-shaped gates live in `gates/` (score inverted under ADR 0010) | UNVERIFIED | see G07 list; ADR names only `vendor/` instances, `adr/0010...md:40-43` |
| G07 | Misfiled set: state-machine 051-058, installer 900-940, 000_violations x3, igniter-task 030 | OBSERVED | headers e.g. `P/state-machine-pack/gates/055_refuse_dead_end.rq:1` |
| G08 | `GateVerify.run` callers (SyncVerify, fortune5_ready, verify task) hit those packs? | UNVERIFIED | `sync_verify.ex:40`, `ggen_igniter.fortune5_ready.ex:365`; pack set not checked |
| G09 | ash-igniter-api `000_violations.rq`: 41 codes, 26 never named in any test | OBSERVED | grep of each `AS ?violation_code` string over `T/` |
| G10 | Untested ash-api codes include MALFORMED_NAME, UNKNOWN_VALUE_TYPE, INCOMPLETE_PAGINATION | OBSERVED | `P/ash-igniter-api-pack/gates/000_violations.rq` branches; grep over `T/` empty |
| G11 | Tested ash-api codes: 15, via variant-ontology tests asserting REFUSED_ASH_API_SURFACE | OBSERVED | `T/ggen_igniter_ash_aggregates_interfaces_test.exs:183-199`, `T/ggen_igniter_ash_action_surface_test.exs:195-230` |
| G12 | ultracode `000_violations.rq`: 7 of 19 codes unnamed in tests | OBSERVED | NO_AGENT, INCOMPLETE_AGENT, MISSING_WORK_PORT, FOREIGN_CAPABILITY_PORT, EXTRA_SHELL_BOUNDARY, ACTUATION_WITHOUT_AUTHORITY |
| G13 | ACTUATION_WITHOUT_AUTHORITY is masked: fixture trips both actuation branches | OBSERVED | `T/fixtures/ultracode-two-port/neg_unmediated_push.ttl:5`, asserts one code `T/ggen_igniter_ultracode_two_port_test.exs:873` |
| G14 | A deleted ACTUATION_WITHOUT_AUTHORITY branch would likely survive the suite | UNVERIFIED | follows from G13; no mutation run |
| G15 | receipted-extension `000_violations.rq`: all 13 codes named in tests | OBSERVED | grep of codes over `T/`; whether each fixture isolates its branch not checked |
| G16 | state-machine 052 (unknown `from`) and 054 (undeclared initial) lack a discriminating fixture | UNVERIFIED | `neg_unknown_state.ttl` only has `to` ghost (t3); asserts code only `T/ggen_igniter_state_machine_conservation_test.exs:106-112` |
| G17 | One code TRANSITION_UNKNOWN_STATE shared by 5 gates; assertions match code, not gate | OBSERVED | `P/state-machine-pack/templates/state_machine.ex.eex:13-19` |
| G18 | state-machine 051/053/055/056/057/058 each have a named negative fixture | OBSERVED | `T/ggen_igniter_state_machine_conservation_test.exs:97-147`; fixtures listed |
| G19 | installer 910 (incomplete config) has no refusing fixture | UNVERIFIED | only complete `dev.exs` config tested, `T/ggen_igniter_installer_pack_test.exs:175-182` |
| G20 | installer 930 (incomplete step) has no refusing fixture; both step fixtures are complete | UNVERIFIED | `T/ggen_igniter_upgrader_chain_test.exs:140-179` |
| G21 | 930 header claims kind-specific facts; query checks only stepOf/kind/order | OBSERVED | `P/igniter-installer-pack/gates/930_refuse_step.rq:1-6` |
| G22 | installer 900, 905, 915, 920, 925, 932, 935, 940 each have a refusing test | OBSERVED | `T/ggen_igniter_installer_pack_test.exs:162-188`, `upgrader_chain_test.exs:138-200` |
| G23 | priv/sa2a: 13 ASK gates, no lib or test path loads them | OBSERVED | `grep -rn "priv/sa2a\|sa2a/gates" lib test` empty; `semantic_evidence.ex` hardcodes checks |
| G24 | sa2a ASK gates are offender-shaped (true = violation); no ASK scorer for them found | UNVERIFIED | `P/../priv/sa2a/gates/authority-none.rq:1`; `GateVerify.run` consumes rows |
| G25 | dfcm-agent-pack: 6 gates, 0 test references; calver-ticket-day-pack: 3 gates, no test | OBSERVED | `grep -rln "dfcm-agent\|calver-ticket-day" test lib` -> one fixture JSON only |
| G26 | ash-manufacture cardinality covers 11 of 13 gates; citations, dependency_pins default | OBSERVED | `P/ash-manufacture-pack/verify/cardinality.json` keys; its note says so |
| G27 | cardinality note says contracts were run on the `sparql` hex engine; stale | OBSERVED | cardinality.json note vs `engine.ex:11-16` |
| G28 | ash-manufacture has a mutation court proving verify is non-vacuous | UNVERIFIED | `T/ggen_igniter_verify_mutation_test.exs:46,62`; not executed |
| G29 | doctrine-hddl 030 nested FILTER NOT EXISTS: negative-fixture coverage unknown | UNVERIFIED | `P/doctrine-hddl-pack/gates/030_methods.rq:34-45`; one positive test `:147` |
| G30 | Name-grep proxy: 67 of 196 `.rq` stems appear in no test or lib file | OBSERVED | loop over `priv/**/*.rq` with `grep -rlF`; proxy only, many are tested by code |
| G31 | No MINUS with an unshared variable found in files read; other 150+ not scanned | UNVERIFIED | read: 000_violations (ash-api), state-machine, installer MINUS blocks |

## Next

1. Install the toolchain (or use CI) and run `mix test` plus a per-gate delete-the-branch
   mutation over the G09/G12/G19/G20 branches to turn UNVERIFIED into KILLED or SURVIVED.
2. Decide the single gate convention (G05) and either re-home offender queries to `verify/` with
   a cardinality contract (ADR 0010 sequence) or add a per-gate mode; update ADR 0010's list (G06).
3. Add one fixture per untested violation code, each isolating its branch (G09, G12, G13, G16).
4. Add refusing fixtures for installer 910 and 930; narrow or widen the 930 header (G19-G21).
5. Wire or retire `priv/sa2a/**/*.rq` (G23-G24) and add tests for dfcm-agent and
   calver-ticket-day packs (G25).
6. Correct CLAUDE.md, `docs/status.md:73` and stale gate comments for the graphlaw-only engine
   (G02-G04, G27); add a lint that flags a MINUS sharing no variable with its group (G31).

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/architecture/adr/0010-gate-convention-directory-is-convention.md`
- `lib/ggen_igniter/gate_verify.ex`
- `lib/ggen_igniter/pack_frontmatter/sync.ex`
- `priv/ggen/CLAUDE.md`
