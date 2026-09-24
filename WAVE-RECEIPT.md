# WAVE-RECEIPT — G4: `mix ggen_igniter.hand_authored` (the admission lockstep, retired)

Agent: G4, ggen maximization wave v26.9.18. Ticket:
`docs/jira/v26.9.18/g4-igniter-admission-task.md`. Standing at close: **ALIVE**
(observed task runs on the real beam4pm consumer, gate-matching replay, typed
falsifiers all refused).

## What was manufactured

`mix ggen_igniter.hand_authored` (lib/mix/tasks/ggen_igniter.hand_authored.ex,
~1050 lines) — three verbs automating the whole `bpm:HandAuthoredSource`
admission law of the beam4pm-process-model-pack (gates 050/060/070 + the
consumer's rendered `scripts/gate_authorship_check.sh`):

- `admit` — validates every capability-object law BEFORE writing (file exists,
  unmarked, miscoped, acceptance command, expiry format, kind in the pack's
  CLOSED vocabulary, debt-kind sunset-plan/expiry laws, duplicate
  `bpm:sourcePath`, per-kind ceiling), computes the real sha256 over the real
  bytes, appends the individual to the consumer's ontology.ttl, then triggers
  the pack render: scaffold `force: true` into the three hand-authored Tera
  templates, remove ggen.lock (FM-PACK-008's own re-lock remediation — the
  scaffold changes the pack hash), `ggen sync run`, restore templates AND lock
  byte-for-byte, re-sync against the clean pack (idempotence + lock
  re-validation). `--dry-run` validates and writes nothing; `--no-render`
  skips the render; missing `ggen` binary is `BLOCKED_RENDER_NO_GGEN` (exit 3)
  with the manual two-step printed.
- `list` — admitted set per kind (count/ceiling, AT CEILING flagged) + really
  runs the pack's own `gates/0{50,60,70}_*.rq` through oxigraph over the
  merged consumer+pack graph; exit 1 on any gate row.
- `check` — runs the consumer's rendered shell gate as a subprocess; exits
  with the gate's own code.

Exit contract: 0 ok / 1 typed `REFUSED_*` / 2 invalid invocation / 3 blocked
render. Version bump 26.9.15 -> 26.9.18 + CHANGELOG entry per house rule
(doctor check 17: CHANGELOG topmost heading == mix.exs literal).

Tests: test/ggen_igniter_hand_authored_task_test.exs — 26 Chicago-style
subprocess tests against a real scratch consumer project (real mix deps.get +
compile, real oxigraph NIF, real fixture pack with the verbatim gate SPARQL).

## SHAs / trees

- igniter authorship: `/Users/sac/ggen_igniter-wt/g4`, branch
  `feat/hand-authored-admit-task` from d018ed4; commit at close: see `git log
  -1` (task + tests + mix.exs 26.9.18 + CHANGELOG).
- proof consumer: `/Users/sac/beam4pm-worktrees/wt-g4-proof`, branch
  `scratch/g4-proof` @ 70e2662 (parity/integration tip; wave's +17
  admissions, raised ceilings, gate 64/57).
- vendored pack: submodule checked out at **f2ae5382e**
  (fix/…ceiling-35-wave-26918, hand_authored_qualification 50,
  native_engine_facade 7) — the exact content the integration rendered with;
  ggen.lock blake3 36fc3a3d… matches it (dry-run verified before replay).
- gitlink NOT bumped (same as the integration branch; worktree-local pack
  commit).

## Observed commands + exits (the decisive sequence)

1. Baseline gate (wave state): `bash scripts/gate_authorship_check.sh` ->
   `GATE AUTHORSHIP: PASS -- 64 admitted (57 counted as manufacturing debt),
   64 unmarked files under roots, 0 findings`, exit 0.
2. Revert to pre-wave ledger: `git checkout 36b0ed9 -- ontology.ttl
   schema/beam4pm_hand_authored_source.tsv docs/reference/beam4pm_hand_authored_source.md`
   -> 47 admitted / 40 debt; gate now `REFUSED: 17 finding(s)`, all 17 wave
   paths REFUSED_UNADMITTED (the hand-lockstep work, replayed from zero).
3. Replay: `/tmp/g4_replay.sh` — **all 17 rows admitted one by one THROUGH
   `mix ggen_igniter.hand_authored admit`** (field values verbatim from the
   wave's own synthesis commits 86b0363 + 3ac0d8f; sha256 computed by the task
   from the real bytes — row 1's digest a88af2e5… equals the wave's recorded
   digest independently). Ceiling arithmetic observed live: qualification
   35 -> 50/50 [AT CEILING], native_engine_facade 5 -> 7/7 [AT CEILING].
   Logs: /tmp/g4_replay_logs/01…17_*.log.
4. Render (row 17, inside admit): `✔ RENDER: ggen sync run exit 0 (3
   template(s) force-scaffolded, restored)`. An earlier attempt surfaced the
   real FM-PACK-008 refusal (scaffolded pack hash vs ggen.lock) — fixed by
   encoding FM-PACK-008's own re-lock remediation into the render leg, then
   replayed end-to-end clean.
5. Render artifacts **byte-identical to the wave's own synthesis commit
   70e2662**: schema/beam4pm_hand_authored_source.tsv IDENTICAL,
   docs/reference/beam4pm_hand_authored_source.md IDENTICAL,
   test/beam4pm_authorship_gate_test.exs IDENTICAL, ggen.lock IDENTICAL,
   vendored submodule clean. Only ontology.ttl differs in serialization
   (mechanically-derived `bap:` subject names, appended after the last
   existing individual) — the RDF graph is row-for-row equivalent (same 64
   individuals, same field values); the rendered projections query by class,
   not by subject name, hence byte-identical output.
6. Final gate, both paths:
   - `bash scripts/gate_authorship_check.sh` -> **PASS -- 64 admitted (57
     counted as manufacturing debt), 0 findings**, exit 0.
   - `mix ggen_igniter.hand_authored check` -> gate PASSED (exit 0).
   - `mix ggen_igniter.hand_authored list` -> `LIST: OK -- 64 admitted, 0
     gate rows` (pack gates 050/060/070 really run: 0 rows each).

## Refusal falsifiers (all observed typed, nothing written)

| Falsifier | Result |
|---|---|
| missing file (`test/nonexistent_g4.exs`) | `REFUSED_FILE_NOT_FOUND` |
| duplicate path (`lib/beam4pm_dfcm.ex`) | `REFUSED_DUPLICATE_SOURCE_PATH` |
| kind past ceiling (51 > 50) | `REFUSED_CEILING_EXCEEDED` (names the pack-edit remedy) |
| debt kind without sunset plan | `REFUSED_MISSING_SUNSET_PLAN` |
| marked file (the TSV manifest itself) | `REFUSED_MARKED_FILE` |
| unknown kind (`does_not_exist`) | `REFUSED_UNKNOWN_KIND` |
| miscoped (`ggen.toml` at root) | `REFUSED_MISSCOPED` |
| invalid expiry (`31/12/2026`) | `REFUSED_INVALID_EXPIRY` |
| no verb / unknown verb / unknown flag | exit 2, typed message |
| `--dry-run` | validates for real, writes nothing |

Also refused during the replay (real discoveries, then fixed as permanent
tripwires in the task): `REFUSED_ONTOLOGY_MALFORMED_SECTION` (consumer blocks
terminate inline in ` .`, not a standalone `.` line) and the FM-PACK-008
lock-mismatch handling above.

## ggen_igniter's own suite

`mix test` (g4 worktree, 26.9.18, final run after all render-leg fixes):
**958 tests, 0 failures** (+20 doctests, +42 properties; 9 excluded by tag,
1 skipped) — includes the task's own 26-test subprocess suite (green).

## 比 (ratio, honest)

This ticket manufactures a TOOL, not consumer source; 比 is measured on what
the operator did not have to write and on the replay's replaced lockstep:

- Task + tests authored this session: ~1,050 lines task + ~700 lines tests,
  hand-written (this is 法面 tooling; the 階 ladder's REUSE steps ran first —
  the task reuses GgenIgniter.Ontology, GgenIgniter.Query.Oxigraph, the pack's
  own gates/*.rq, and the pack templates; no second gate implementation).
- Replaced hand-lockstep: 17 admissions x (ontology edit + sha + render +
  gate) — the exact stumble every v26.9.18 parity agent performed — is now ONE
  typed command per row, machine-validated before write, replay-proven
  byte-identical to the hand-made result.
- Consumer lines this session hand-wrote on 産面: **0** (ontology.ttl rows were
  written by the task; the three projections by ggen sync run; scratch mix.exs
  dep override is an uncommitted wiring edit).

## What the operator did NOT have to write

The admission individual (TTL block, sha, escaping, anchor placement), the
render dance (scaffold/re-lock/restore), the gate run, and every refusal
diagnostic — all manufactured by the task. Future waves admit with one command
and never hand-edit ontology.ttl admission rows again.

## Remaining (honest gaps)

- The render leg's two-sync dance is verified on the real consumer but not in
  the scratch test suite (needs a real ggen binary + pack; the scratch tests
  cover everything up to `--no-render`).
- A permanent `force: true` (or freeze_policy) on the three hand-authored
  templates in the vendored pack would retire the scaffold entirely — pack
  edit + ggen.lock re-lock, deliberately out of scope here.
- `admit` refuses an already-admitted path rather than re-admitting a drifted
  file (edit the existing row's sha instead) — an `update` verb is future work.
- The `_G-CONTEXT.md` 並 note: this receipt's logs live under /tmp (session
  scratch); the durable evidence is this receipt + the commits.
