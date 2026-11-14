# v26.11.13 — ash_a2a end-to-end projection via ggen

Standing: PARTIAL

Goal: from Turtle alone, `ggen sync run --skip-ea-admission` AND `mix ggen_igniter.*` project an
Ash + AshA2A app that compiles (`--warnings-as-errors`) and passes its generated tests.

## Receipt (this wave, coordinator-run)

- Subject: `ggen_igniter` working tree on `9c2572e` (dirty; committed by the landing commit),
  pack `ggen-marketplace/packs/ash-a2a-app-pack`, ggen 26.11.5.
- Toolchain: moved to the latest installed: Elixir 1.20.4 / OTP 29 / erlang 29.1.2
  (`.tool-versions`, all `.github/workflows/*.yml`).
- `mix compile --warnings-as-errors` exit 0; `mix format --check-formatted` exit 0;
  `mix credo` exit 0 (5289 mods/funs, no issues).
- `mix test` exit 0: `Result: 1855 passed (20 doctests, 41 properties, 1794 tests), 5 skipped,
  705 excluded` under Elixir 1.20.4 / OTP 29.
- Pin re-qualification: `receipts/v26.11.13/R3-GI-PIN.json` (+ `.logs/`), literal lane gate under
  the new pin, exit 0, court stubbed with disclosure and restored byte-identical.
- Live-pack parity: `PackFrontmatter.SyncTest` runs the real `ggen sync run` and the igniter
  runner on the live pack + `app_live.ttl` and asserts byte equality of every igniter output.
  It passed with no `[BLOCKED]` line.

## Fixes forced by the toolchain move

- `faker` 0.18.0 (Hex latest) does not compile on Elixir 1.20: `mix.exs` pins upstream
  `elixirs/faker` at `f9d24dc`.
- Elixir 1.20 type-checker warnings and credo debt were repaired (behaviour-preserving
  refactors in the landing pipeline, review stores, review_eval, Tera, EA admission).
- Court re-pinned for the 1.20 summary format (`Result: N passed (...)`).

## Gaps

| id | gap | standing | evidence / remaining |
|---|---|---|---|
| G1 | igniter drives the frontmatter pack | ALIVE | `PackFrontmatter.Sync` (Tera subset incl. macros, `set_global`, `when:` ASK) + `mix ggen_igniter.sync --pack`; byte parity on the live pack. Not done: manifest/`--on-stale`, multiple `--ontology` on `sync`; `inject`/`construct`/`rdf_inline` etc. still refuse |
| G2 | admissible `ea.graph.json` | PARTIAL | `L19_ea_graph.json.tmpl` (committed) is the emitter; `L30` template retired (output collision); `EaAdmission` skip-receipt module + tests pass but is not wired into sync. Unverified: `ggen sync run` without `--skip-ea-admission` on a fresh dir (admission runs before render) |
| G3 | re-lock without deleting `ggen.lock` | ALIVE (igniter) / BLOCKED (ggen CLI) | `PackLock` write mode proven by `ggen_igniter_pack_relock_test.exs`; `ggen sync run --relock` lives in the ggen repo, not changed |
| G4 | `:strict` prod profile | PARTIAL | `L31_*` templates, gate, fixture authored; `config.exs.tmpl` still lacks `import_config("prod.exs")`; strict boot never run |
| G5 | missing pack features | PARTIAL | L21 hddl_operator, L22 authority, L23 argument_mapping, L24 `get?`, L25 destroy accept, L26 federated multi-domain (ash_a2a has no native multi-domain option) authored with gates and fixtures; they parse under real ggen; not wired into `resource.ex.tmpl` `fragments:`; L21/L23/L24 overlap L17 |
| G6 | mutation court per template | PARTIAL | `courts/` (lib.sh, shim_court.sh) authored; never executed |
| G7 | gates 040+ | PARTIAL | L28 (agent without domain, duplicate module/skill) and L29 (collisions, invalid atoms) authored with refusing fixtures; never executed. Census (read, not run): 106 of 149 gates have no refusing fixture; `L02_020`, `L13_050`, `X_060` likely cannot fire (SPARQL UNION scoping) |
| G8 | dispatch round-trip test | PARTIAL | `L27_dispatch_test.exs.tmpl` renders under real ggen; generated test never compiled or run |

## Defects found and fixed by the gate, not by authoring

- `L27` template used `(x | first).field` (invalid Tera): real ggen refused it.
- `L19` and `L30` both wrote `ea.graph.json` (ggen FM-WRITE-008).
- `L31-profile.ttl` used `rdf:` without a prefix declaration.
- `L13-statemachine.ttl:50` had a raw newline inside a string literal.

## Next

1. Wire L21–L25 fragments into `resource.ex.tmpl`; reconcile with L17.
2. Run gate non-vacuity: execute each gate against its refusing fixture through the engine.
3. Run the shim-courts; compile and run the generated dispatch test on a fresh fixture project.
4. `import_config("prod.exs")` seam and a strict-boot run.

## See Also

- `LANES.md`, `02-GAP-REGISTER.md`, `03-VERIFY-LADDER.md` in this directory
- `receipts/v26.11.13/R3-GI-PIN.json`
