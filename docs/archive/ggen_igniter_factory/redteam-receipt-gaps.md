# Red-Team: Receipt Invariant (`ActuationOccurred => ReceiptExists`)

Independent adversarial review. No builder reasoning consulted. All commands
and file reads below were executed for real in this session on 2026-08-27/28.

## 1. Real receipt-related test suite (as-is, unmodified)

```
$ mix test test/ggen_igniter_receipt_test.exs \
           test/ggen_igniter_receipt_reconstruct_standing_test.exs \
           test/ggen_igniter_reconcile_reactor_test.exs \
           test/ggen_igniter_finalize_evidence_ordering_test.exs \
           test/ggen_igniter_compensation_failure_test.exs \
           test/ggen_igniter_actuation_failure_injection_test.exs

Running ExUnit with seed: 987477, max_cases: 32
.............................
Finished in 6.4 seconds (0.1s async, 6.2s sync)
29 tests, 0 failures
```

All 29 tests pass for real, no mocks (grep of these files for
`unittest.mock|Mock(|MagicMock|patch(|monkeypatch`-equivalent Elixir
patterns turns up none; these tests use real ontology/query/template
fixtures and a real `mix compile` subprocess).

Every one of these 29 tests exercises `GgenIgniter.Reactors.ReconcileReactor`
directly (`ReconcileReactor.run/1`) — the **opt-in** pipeline
(`config :ggen_igniter, use_reactor: true`). Confirmed by inspection:
`grep -rn "use_reactor" config/*.exs` returns nothing in any config file, and
`lib/mix/tasks/ggen_igniter.sync.ex:446` (`defp use_reactor?, do:
Application.get_env(:ggen_igniter, :use_reactor, false)`) and
`lib/ggen_igniter/controller.ex:170` both default to `false`. **The default
pipeline for both `mix ggen_igniter.sync` and `GgenIgniter.Controller` is the
plain, non-Reactor path — the one path with zero tests in this suite that
check for a durable receipt's presence or absence.**

## 2. Independently constructed scenario (not covered by any existing test)

Grep evidence that no existing test checks this: none of
`test/ggen_igniter_sync_*.exs` (the tests that actually invoke the default
pipeline, e.g. `ggen_igniter_sync_task_test.exs` as a real subprocess) mention
`receipt`, `Receipt`, or `jsonl` anywhere. The one hit for `record.receipt` in
`test/ggen_igniter_sync_controller_delegation_test.exs:129-130` is the
ephemeral in-memory `Controller` map, explicitly disambiguated from the
durable `%GgenIgniter.Receipt{}` in `docs/reference/evidence/receipts.md`
section 5 — not the durable JSONL record.

**Scenario constructed and executed for real:** run `mix ggen_igniter.sync`
as a real OS subprocess (`System.cmd`, exactly the pattern
`ggen_igniter_sync_task_test.exs` uses), with the default pipeline (no
`use_reactor` config set anywhere), pointed via `--manifest-dir` at an
isolated `/tmp` directory so the run is fully separable from the repo's own
`.ggen_igniter/`, and `--out` at a fresh path under the same isolated `/tmp`
tree that does not exist before the run.

Command (engine/ontology/queries/template identical to the existing
`ggen_igniter_sync_task_test.exs` fixture — sparql engine, real oxigraph):

```
$ mix ggen_igniter.sync \
    --engine sparql \
    --ontology test/fixtures/audit_trail_ontology.ttl \
    --query spec=test/fixtures/spec.rq \
    --query sections=test/fixtures/sections.rq \
    --query entities=test/fixtures/entities.rq \
    --query fields=test/fixtures/fields.rq \
    --template test/fixtures/extension.ex.eex \
    --out /tmp/ggen_redteam_scenario_2049/outdir/resource.ex \
    --manifest-dir /tmp/ggen_redteam_scenario_2049/manifest_dir
```

Real output:
```
Notices:
* ggen_igniter: wrote /tmp/ggen_redteam_scenario_2049/outdir/resource.ex (engine: sparql, 4 queries, 7 total row(s))
```
`EXIT_CODE=0`.

**Post-run, read from real disk (not from the tool's own claimed output):**

- `test -f /tmp/.../outdir/resource.ex` → **YES**, real file, 63 lines, valid
  Elixir (`defmodule AuditTrail.Resource do ...`) — this is a genuine,
  consequential physical actuation: a file that did not exist before the run
  now exists with real generated content.
- `/tmp/.../manifest_dir/.ggen_igniter/manifest.json` → **written**, and its
  content is not a no-op stub — it records a real `sha256:` content hash for
  the exact output path, proving the manifest layer genuinely registered this
  as a completed write, not a skip/refusal:
  ```json
  {
    "entries": {
      "test/fixtures/extension.ex.eex=>/tmp/.../outdir/resource.ex": {
        "outputs": { "/tmp/.../outdir/resource.ex": "sha256:4ede3854fd08..." },
        "template": "test/fixtures/extension.ex.eex",
        "updated_at": "2026-08-28T01:07:38.350256Z"
      }
    },
    "version": 1
  }
  ```
- `find /tmp/.../manifest_dir -iname "*.jsonl"` → **empty**. No
  `.ggen_igniter/receipts/` directory was created anywhere.
- Exhaustive `find` over the entire isolated `/tmp` scratch tree for any
  `*.jsonl` file → **empty**.
- The repo's own `.ggen_igniter/manifest.json` (checked via
  `git status --porcelain .ggen_igniter/manifest.json` and `git diff --stat`)
  → untouched by this run, confirming the isolation held and this result is
  not an artifact of cross-contamination with some other receipt-writing
  path.

## 3. Verdict

**CONFIRMED**: a real, consequential physical actuation (a genuinely new file
written to disk, with its content hash durably registered in the manifest)
can occur, via the default configuration of this codebase's own CLI entry
point, with **no receipt existing afterward, anywhere** — durably or
otherwise. `GgenIgniter.Receipt.append!/2` is never called on this path;
`Receipt` is referenced nowhere in `lib/mix/tasks/ggen_igniter.sync.ex`'s
plain dispatch branch or in `GgenIgniter.Reconcile.run/1`.

This is not a new discovery of a hidden bug — the project's own docs
(`docs/architecture/adr/0005-receipt-independent-of-manifest.md`,
`docs/operations/failure-recovery.md`) already disclose it in prose: "the
plain `GgenIgniter.Reconcile.run/1` pipeline and `Mix.Tasks.GgenIgniter.Sync`'s
own inline pipeline (today's default paths) write no receipt on any outcome."
What was previously true only as an assertion in documentation is now, as of
this session, also a real, executed, independently-reproduced falsification:
the core invariant stated in `docs/reference/evidence/standing.md` section 4
— "If files were physically modified on disk ... a durable receipt MUST be
appended" — **does not hold for the default configuration of this system**.
It holds only for the non-default, opt-in `use_reactor: true` path, and nowhere
is a user, on a fresh clone with zero config changes, ever warned at the point
of actuation (no runtime warning/log line was observed in the real command
output above) that the receipt guarantee does not apply to the command they
just ran.

## 4. Scope note

This finding is about the **default/plain pipeline only**. The opt-in Reactor
path's receipt-before-manifest ordering guarantee (verified by the 29 real
passing tests in section 1, including the genuine
`:build_broken`/`:compensated`/manifest-promotion-pending cases) is not
disputed here and is not what this scenario tested.
