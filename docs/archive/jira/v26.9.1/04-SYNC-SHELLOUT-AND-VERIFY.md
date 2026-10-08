# Real ggen sync run shellout and gate verification

## Status (updated after real implementation)

**DONE** per gi04 evidence in `/tmp/full_results.json`.

- Worktree `/tmp/GI-04-worktree` (real git worktree of `~/ggen_igniter`), branch
  `story/GI-04-sync-shellout-and-verify` (based on GI-03's `story/GI-03-bundle-manifest-and-merge`,
  commit `eae7397`), new commit `c542eea`. Committed only — not merged to main, not pushed.
- Real `ggen` binary used: `~/.local/bin/ggen`, a docker-run wrapper for
  `ghcr.io/seanchatmangpt/ggen-ecosystem:v26.8.28`. This machine's `/tmp` is NOT shared into the
  container (`docker run -v /tmp/...:/workspace ... ls /workspace` returned empty), while
  `System.tmp_dir!()` resolves to `~/.cache/tmp`, which IS shared and content-verified. Every
  scratch consumer-project test fixture is built under `System.tmp_dir!()` for this reason.
- GGEN-1805: new `lib/ggen_igniter/sync_shellout.ex` — `GgenIgniter.SyncShellout.run/2`, a real
  `System.cmd("ggen", ["sync", "run"], cd: project_dir, stderr_to_stdout: true)`, typed
  `{:ok, output} | {:error, {exit_code, output}}`, `ErlangError` rescue → `{:error, {:enoent, ...}}`,
  and an `upstream_ok?: false` hard precondition gate that returns `{:error, :upstream_failed}`
  without ever calling `System.cmd/3`.
- GGEN-1806: new `lib/ggen_igniter/gate_verify.ex` — `GgenIgniter.GateVerify.run/2`, reusing
  `GgenIgniter.Pack.discover_queries/1` (`gates/*.rq`) + `GgenIgniter.Ontology.load!/1` +
  `GgenIgniter.Query.run/2` for real SPARQL gate execution; returns `{:ok, [{gate_name, :pass}, ...]}`
  or `{:error, {:gate_failed, gate_name}}` naming the first failed gate.
- Orchestrator: new `lib/ggen_igniter/sync_verify.ex` — `GgenIgniter.SyncVerify.run/3` chains both
  via a real `with`.
- Tests: `test/ggen_igniter_sync_shellout_test.exs` (8 tests), real fixtures under
  `System.tmp_dir!()` plus committed `.rq` gate fixtures at `test/fixtures/sync_verify/pack/gates/`.
  `mix compile --warnings-as-errors` → clean. `mix test test/ggen_igniter_sync_shellout_test.exs`
  → "8 tests, 0 failures". `mix ggen_igniter.doctor` → "all checks passed" (only pre-existing
  unrelated advisories). `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` → only
  doc-comment mentions of the discipline plus pre-existing `assert_has_patch` calls (igniter's
  real API, not mocking) — zero real mock usage.

**Same full-suite-unconfirmed caveat as the other stages**: a background full-repo `mix test` (log
at `/tmp/gi04_fulltest.log`) was still running against this repo's full 2500+-test suite
(unrelated pre-existing suites — redteam collision reproducers, ArtifactIdentity, QLever engine
matrix, etc.) when the task's time budget was reached; not confirmed to completion. The scoped run
above is the load-bearing evidence for this ticket's own acceptance bullets — nothing in the new
files depends on unrelated suites.

Non-goals explicitly out of scope and not attempted: GGEN-1804 (the upstream `ggen.toml`
serialize-back step itself — `upstream_ok?` is a caller-supplied boolean gate, not an
implementation of that step), GGEN-1807 and the rest of the fortune5-ready installer mix task, and
wiring `SyncShellout`/`GateVerify`/`SyncVerify` into any actual mix task.

---

## Scope note — this is a different v26.9.1 work stream

This repo already has `docs/v26.9.1-requirements.md`, tracking a **process-mining/OCEL
manufacturing-pack expansion release** (incremental DFG discovery, sensor-to-event streaming,
inductive-miner discovery, token-replay conformance, OCEL2/EKG derivation, OLAP slice/dice, and
Chicago-style OTP fault injection packs). That document and this `docs/jira/v26.9.1/` ticket set
share a version number by coincidence, not by relationship — this ticket is part of the
**fortune5-ready bundle installer** epic instead. Do not conflate the two; see "See Also" below
for both.

This ticket (`04-SYNC-SHELLOUT-AND-VERIFY.md`) covers the `ggen_igniter`-side implementation
detail for **GGEN-1805** (real `System.cmd/3` shellout to an external `ggen sync run`) and
**GGEN-1806** (post-sync gate verification) from the source epic,
`~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`. Story numbering below reuses
that epic's numbers 1:1 rather than inventing a parallel scheme.

## Status vocabulary

This document uses this repo's own three-value convention exactly:
**IMPLEMENTED / PARTIAL_ALIVE / PLANNED** — not beam4pm's ALIVE/PARTIAL_ALIVE/BLOCKED/UNVERIFIED
scheme, which belongs to a different repo with a different convention.

Everything in this ticket is **PLANNED**: confirmed by direct search that no code shelling out to
an external `ggen` binary exists in this repo today (see Evidence below).

## Evidence this is genuinely new code

```
grep -rn "System.cmd" lib/
```

returns four hits, none of which shell out to an external `ggen` binary:

- `lib/ggen_igniter/shell_hook.ex:94` — `System.cmd("sh", ["-c", cmd], cd: project_dir,
  stderr_to_stdout: true)`, a generic consumer-defined shell-hook runner, not a `ggen` caller.
- `lib/ggen_igniter/reactors/reconcile_reactor.ex:613` — `System.cmd("mix", ["compile",
  "--warnings-as-errors"], ...)`, the Reactor pipeline's `:verify` step.
- `lib/mix/tasks/ggen_igniter.doctor.ex:746, 821, 914` — three existing subprocess checks
  (`git`, `cargo`, `mix hex.build`), cited as the pattern to model on below.

`mix ggen_igniter.sync` (`lib/mix/tasks/ggen_igniter.sync.ex`) **is** this repo's own
Elixir-native sync engine (ontology-load → engine-run → render → actuate, per this repo's
`CLAUDE.md`) — it is not, and has never been, a caller of an external `ggen sync run` binary.
This confirms the epic's own framing: "no code shelling out to a real external `ggen sync run`
binary."

## The three existing subprocess-check patterns this ticket models on

All three live in `lib/mix/tasks/ggen_igniter.doctor.ex` and share one shape: a real
`System.cmd/3` call with an explicit or resolved `cd:`, `stderr_to_stdout: true`, a `case`/`cond`
over `{output, exit_code}`, and a `rescue` clause converting a raised `ErlangError` (binary not on
`PATH`) into a typed result rather than crashing the calling task.

- **`check_git_status/0`** (`lib/mix/tasks/ggen_igniter.doctor.ex:745-768`, doctor check 13):
  ```elixir
  case System.cmd("git", ["status", "--porcelain"], cd: File.cwd!(), stderr_to_stdout: true) do
    {output, 0} -> ...
    {output, _code} -> {:warn, "not a git repo (or git not on PATH): #{String.trim(output)}"}
  end
  rescue
    error -> {:warn, "not a git repo (or git not on PATH): #{Exception.message(error)}"}
  ```
  Notable disclosed defect this pattern's moduledoc documents (per the comment at lines 748-763):
  an absent `.git` directory must surface as `:warn`, never `:error` — a `{:error, ...}` here
  would fail the whole aggregate doctor run for a condition that is advisory, not a real project
  defect. GGEN-1805's shellout is a different case (a missing `ggen` binary or a real sync
  failure genuinely should refuse), but the *shape* — resolve absence-vs-failure into distinct
  typed outcomes, don't let a `rescue` silently downgrade a real failure — carries over.

- **`check_nif_compiles/0`** (`lib/mix/tasks/ggen_igniter.doctor.ex:815-833`, doctor check 14):
  ```elixir
  case System.cmd("cargo", ["build", "--quiet"], cd: crate_dir, stderr_to_stdout: true) do
    {_output, 0} -> {:ok, "..."}
    {output, code} -> {:error, "... (cargo exit #{code}): #{String.trim(output)}"}
  end
  ```
  Demonstrates the `cd:` resolution discipline GGEN-1805 must follow: `crate_dir` is computed via
  `ggen_igniter_root/0` (lines 793-802), never assumed to be `File.cwd!()` when this task may run
  as a dependency inside a consumer project. GGEN-1805's equivalent is `project_dir` passed
  explicitly by the caller (the bundle installer), never an implicit `File.cwd!()`.

- **`check_hex_publish_readiness/0`** (`lib/mix/tasks/ggen_igniter.doctor.ex:900-925`, doctor
  check 15): the closest structural analog to GGEN-1805 — a real `mix hex.build` subprocess whose
  success is necessary but not sufficient (metadata completeness is checked *in addition to* the
  zero exit code, at lines 913-919). This is the direct precedent for GGEN-1806's requirement that
  "sync succeeded" (zero exit) is not the same claim as "the pack's own contract holds" (gates
  pass) — `check_hex_publish_readiness/0` already treats "subprocess succeeded" and "the thing we
  actually care about is present" as two separate, both-required conditions.

## GGEN-1805 — Real `System.cmd/3` shellout to `ggen sync run`

### Requirement

Implement a real subprocess shellout to an external `ggen sync run` invocation, modeled on the
three patterns above, with:

- an explicit `cd: project_dir` argument (the consumer project's root, passed in by the caller —
  never implicit `File.cwd!()`, per `check_nif_compiles/0`'s `ggen_igniter_root/0` precedent);
- `stderr_to_stdout: true`;
- a typed return: `{:ok, output}` on exit 0, `{:error, {exit_code, output}}` on nonzero exit —
  never an unhandled raise, and never a bare boolean;
- a `rescue` clause that converts a raised `ErlangError` (binary not found on `PATH`, the same
  failure mode `check_git_status/0` already handles for `git`) into the same
  `{:error, {exit_code, output}}` shape rather than crashing the caller, with `exit_code` set to a
  sentinel (e.g. `:enoent`) distinguishable from a real subprocess exit code;
- a hard precondition: this function must not be called at all if the preceding `ggen.toml`
  serialize-back step (GGEN-1804, upstream in the bundle-installer pipeline) failed — the shellout
  is gated on that step's success, not merely sequenced after it.

### Acceptance

- **Real invocation, real capture.** Run for real against a scratch consumer project fixture with
  a real (small, fast) test pack under `priv/ggen/` (per this repo's own `priv/ggen/CLAUDE.md`
  convention). Before invoking, check `PATH` for a real `ggen` binary
  (`System.find_executable("ggen")`); if absent, the test is skipped with a named, visible reason
  (`@moduletag :skip` with an explicit message, or `ExUnit.Case`'s `@tag skip: "..."` — the same
  named-and-visible-skip discipline the global `testing-chicago-style.md` rule cites for
  `is_server_available()`-style guards) — never silently substituted with a mock. When a real
  `ggen` binary is present, the test asserts on the real captured `{output, exit_code}` tuple —
  confirming the subprocess was actually invoked (real stdout content matching what `ggen sync
  run` genuinely emits, not a canned string) and that the call's `cd:` genuinely pinned execution
  to the fixture project root (e.g. by asserting the pack's real generated output file exists at
  the fixture's path afterward, not the caller's own cwd).
- **Nonzero exit surfaced as a typed error, not swallowed.** A second real fixture — a `ggen.toml`
  deliberately pointing at a nonexistent pack path — is run through the same shellout, and the
  test asserts the real nonzero exit code and real stderr/stdout content are both present in the
  returned `{:error, {exit_code, output}}` tuple, proven by inspecting the actual tuple, not
  inferred from a raised exception or a log line.
- **Chained-failure gating.** A fixture where the upstream TOML serialize-back step is forced to
  fail asserts that `ggen sync run` is never invoked at all — via a real, observable signal (e.g.
  the fixture project directory's mtime/generated-file-absence after the run, or a real process
  count check), not a mocked call-count assertion. Per this repo's Chicago-school discipline
  (`CLAUDE.md`'s "Testing discipline" section, enforced via `grep -rn
  "Mock\|mock(\|patch(\|monkeypatch" test lib native` returning zero matches), this assertion must
  be state-based, not interaction-based.

## GGEN-1806 — Verification stage: run the newly-generated packs' own gates for real

### Requirement

After a successful GGEN-1805 sync (exit 0), run each newly-added pack's own `gates/*.rq` SPARQL
gate queries for real against the regenerated ontology graph, and report a **typed, per-gate**
pass/fail result — never a single aggregate boolean. If any gate fails, refuse with a typed error
naming the specific failed gate. "Sync succeeded" (GGEN-1805's `{:ok, output}`) and "the pack's
own contract holds" (this story's per-gate result) are separate, independently observable
outcomes — a caller must be able to tell "generated and gate-verified" apart from "generated
only." This mirrors `check_hex_publish_readiness/0`'s existing precedent of not conflating
subprocess success with the actual property being checked.

Gate execution follows this repo's own `priv/ggen/CLAUDE.md` convention (`gates/NNN_name.rq`,
zero-padded, `PREFIX` declarations scoped to the pack's own ontology IRI, `SELECT DISTINCT`) and
beam4pm's gate-closure convention cited by the source epic
(`docs/jira/v26.8.29/16-gate-closure-m0-m6.md`-style: a gate is a real, individually-inspectable
pass/fail check, not a compilation-or-existence proxy for correctness).

### Acceptance

- **Per-gate results, not one aggregate.** Run for real post-sync against the fixture pack's
  `gates/*.rq` files: each gate query is executed for real (real SPARQL execution against the
  regenerated `ontology.ttl`-derived graph — via this repo's own `--engine sparql`/`oxigraph`
  machinery, or the pack's documented gate-runner mechanism) and the test asserts on the real,
  individual pass/fail result of each gate by name — proven by inspecting a list/map of
  `{gate_name, :pass | :fail}` results, not a single boolean.
- **Named refusal on a broken gate.** A fixture that deliberately removes a required ontology
  individual one gate query depends on causes the verification stage to refuse with a typed error
  that names the specific failed gate (e.g. `{:error, {:gate_failed, "030_required_field.rq"}}`),
  proven by running against that fixture and reading the real refusal message — not merely
  asserting a nonzero exit code or a generic `{:error, _}`.
- **Distinguishable success levels.** When all gates pass, the task's final result is a typed
  success value (e.g. `{:ok, %{sync: output, gates: [{name, :pass}, ...]}}`) that a caller can
  pattern-match to distinguish "generated and gate-verified" from "generated only" (GGEN-1805's
  bare `{:ok, output}`) — these are two separate, independently-observable outcomes per the
  epic's explicit instruction not to claim readiness from generation alone.
- **Chicago-school test discipline throughout.** Every test above uses real collaborators — a
  real scratch consumer project fixture, a real small/fast test pack with real `.rq` gate files,
  a real SPARQL engine execution, and (where a real `ggen` binary is available) a real subprocess
  — with state-based assertions on real returned tuples/files/query results. No
  `Mock`/`mock(`/`patch(`/`monkeypatch`, verified via this repo's own required
  `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` sweep returning zero matches
  before this ticket is claimed done, per `CLAUDE.md`'s "Testing discipline" section and the
  global `~/.claude/rules/testing-chicago-style.md` rule.

## Real commands to run before closing this ticket

Per this repo's own `CLAUDE.md` "Verification discipline" section — a summary is not a receipt:

```
mix compile --warnings-as-errors
mix test test/ggen_igniter_sync_shellout_test.exs   # or wherever the new test file lands
grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native
mix ggen_igniter.doctor
```

## See Also

- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the **other, unrelated** v26.9.1 work stream in
  this same repo (process-mining/OCEL manufacturing-pack expansion release). Same version number,
  different scope — do not conflate.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — the source epic (GGEN-1800
  through GGEN-1807); this ticket implements GGEN-1805 and GGEN-1806 specifically, reusing that
  epic's story numbering.
- `~/beam4pm/CLAUDE.md` — `just sync` / `rm ggen.lock && ggen sync run` as the documented real
  invocation form for a `ggen` consumer, the intended first real target for GGEN-1805's shellout.
- `~/beam4pm/docs/jira/v26.8.29/16-gate-closure-m0-m6.md` — the gate-closure convention GGEN-1806's
  per-gate refusal semantics are modeled on.
- `~/beam4pm/docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the epic/story/acceptance
  format (exact subject, acceptance behavior, evidence) this document's structure follows.
- `~/ggen_igniter/priv/ggen/CLAUDE.md` — the `--pack` convention (`gates/*.rq` naming, template
  naming) GGEN-1806's gate execution follows.
- `~/ggen_igniter/lib/mix/tasks/ggen_igniter.doctor.ex` — `check_git_status/0` (~746),
  `check_nif_compiles/0` (~821), `check_hex_publish_readiness/0` (~914), the three existing
  subprocess-check patterns GGEN-1805's shellout is modeled on.
- `~/.claude/rules/testing-chicago-style.md` — the global Chicago-school testing discipline (real
  collaborators, state-based assertions, named-and-visible skip over silent mock substitution)
  every acceptance bullet above is written against.
