# F1 Rehearsal — NOT the F1 Reference Receipt

**STATUS: REHEARSAL ONLY.** This is a validation pass of `F1_RUNBOOK.md`
executed 2026-10-20 against a scratch target, NOT the F1 reference receipt
and not evidence that the pipeline is ALIVE. Every claim below is grounded in
pasted real command output from the run.

- Canonical checkout: `/Users/sac/ggen_igniter` (untouched; no commits, no
  working-tree mutations — verified at the end of this run).
- Scratch target: `/tmp/f1-rehearsal-1792522706` — `git archive HEAD |
  tar -x` of canonical `main` @ `686640fad15d8c4c385d38779bc1e177cf720b86`,
  then `git init` + config + `git add -A` + commit.
- Build root: `MIX_BUILD_ROOT=_build-lane-e8` (scratch-local), deps symlinked
  from canonical (`ln -s /Users/sac/ggen_igniter/deps deps`).
- Compile: `mix compile` exit 0 (113 app deps, ~13 min from scratch).

## 1. Verdict (one line)

The runbook's §3.1–§3.3 and §3.5 commands work as documented with two
precision deltas; §3.4's projection (`--pack-lock`) backend **is not in HEAD**
and therefore cannot run from an archive/clone — the F1 landing is
**BLOCKED at HEAD** until the untracked W8 corpus lands.

## 2. Preconditions audit — runbook §2

| precondition | status | evidence |
|---|---|---|
| green gate receipt | NOT CHECKED (rehearsal scope) | `mix compile` exit 0 in scratch only |
| per-lane commits landed on main | **FAILED** | see §4 delta D1 — the W8 projection corpus is untracked |
| pack present (`~/ggen-marketplace/packs/pack-bootstrap-pack`) | NOT USED | rehearsal used the projection fixture pack instead (task brief) |
| backlog prepared | rehearsal-local | `candidates.jsonl` / `work_orders.json` minted in scratch (see §3) |

## 3. What ran, with real output

### 3.0 Setup

```
git archive HEAD | tar -x -C $SCRATCH; git init; git add -A; git commit
# HEAD: 686640fad15d8c4c385d38779bc1e177cf720b86
mix compile   # exit 0
```

Backlog minted from the tracked fixture
`test/fixtures/semantic_jira/friday_work_orders.json` (order `FRI-FMT-A` as
shape base), two candidate lines:

- `F1-REHEARSAL-1` — lawful projection order: `capability_id`
  `demo-capability`, `target_path` `ggen-manufactured/demo-capability.md`,
  `epoch` `v26.10.20`, `plan_touches` non-implementation path, `base_sha` =
  scratch HEAD. **Admitted.**
- `F1-REHEARSAL-BAD` — same order, `plan_touches: ["lib/ggen_igniter.ex"]`
  (implementation-plane path, no `manufacture_plan`). **Refused.**

```
$ mix ggen_igniter.pack.lock --path .../projection-fixture-pack --lock .../ggen_igniter.pack.lock
locked projection-pack-fixture sha256=8d3b5caf28de695b5e8a85c578d2535f723d794a4623ff8bed939032bf94416f
```

### 3.1 Watermark

```
$ mix ggen_igniter.epoch.watermark --epoch v26.10.20
epoch watermark: v26.10.20 files=171 head=686640fad15d -> .../.ggen_igniter/epoch/v26.10.20/watermark.json
EXIT=0
```

Re-stamp over unchanged tree: idempotent, exit 0. Final watermark sha256:
`0fde36b03abfb26c3156a4fa77b7c9af67717adf19a30961fc531617c3992336`
(head `dbd9da9…` — the scratch revert head, see probe P1).

### 3.3 Admit (`admit_candidates --epoch-manifest`)

```
$ mix semantic_jira.admit_candidates --candidates candidates.jsonl \
    --epoch-manifest .ggen_igniter/epoch/v26.10.20/watermark.json
admitted 1 F1-REHEARSAL-1 origin=https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority origin_digest=sha256:310e14f1e30a9bb4d6ebd4388036e10ce3c973b13c0d45a7b550fa3dfd53c72c work_order_digest=sha256:5523531326623f26178b65b0f8aef37c2a57cd196688831b58a1d7aac467a76a
refused 2 F1-REHEARSAL-BAD REFUSED:EPOCH_UNATTRIBUTED_IMPLEMENTATION
summary admitted=1 refused=1
EXIT=0
```

Typed refusals recorded: `REFUSED:EPOCH_UNATTRIBUTED_IMPLEMENTATION`
(implementation-plane `plan_touches` path with no `manufacture_plan`).

### 3.4 Execute/Complete — BLOCKED at HEAD

Sequence of real refusals, all with pasted stderr:

1. `missing_alias` (descriptor hop, exit 1):
   `{"broken_term":"R_missing_authority","detail":"descriptor refused: {:descriptor_refused, {:missing_alias, \"seanchatmangpt/ggen_igniter\"}}",...}`
2. `base_drift` (execute hop, exit 1):
   `{"broken_term":"mu_on_O","detail":"target HEAD dbd9da9… != order base_sha 686640f…","reason":["base_drift",...],"standing":"REFUSED"}`
3. `target_pack_mismatch` (exit 1):
   `{"verdict":{"broken_term":"mu_unlawful","detail":{"expected":"projection-pack-fixture","resolved":"projection-fixture-pack"},...,"standing":"REFUSED(target_pack_mismatch)"}}`
4. exit-2 backend exclusivity: `--packs-root` without a `--pack-dir`, order
   lacking `target_pack` →
   `{"reason":"exactly one execution backend is required: --pack-dir + --target-dir, or --receipt PATH","status":"invalid_invocation"}` —
   the packs-root join is `Path.join(packs_root, order["target_pack"])`, so
   **directory name must equal `pack.toml` `[pack].name`**.
5. `sync_failed` — the decisive one (pasted verbatim from `/tmp/comp3.err`):
   ```
   error: undefined variable "capability"
   └─ nofile:2:16

   {"closed":[],"closed_count":0,"identity":"F1-REHEARSAL-1","reason":"order_refused","status":"refused","verdict":{"broken_term":"mu_on_O","detail":"execute refused: {:sync_failed, \"GgenIgniter.Reconcile.run/1 raised: nofile: cannot compile file (errors have been logged)\"}","hop":"execute","reason":["sync_failed","GgenIgniter.Reconcile.run/1 raised: nofile: cannot compile file (errors have been logged)"],"standing":"REFUSED"}}
   ```

### 3.5 epoch.check

```
$ mix ggen_igniter.epoch.check --epoch v26.10.20
epoch check: standing=REFUSED admitted_generated=0 admitted_residue=0 refused=171
EXIT=1
```

All 171 implementation files `REFUSED_LEGACY_EDIT` — the designed behavior
for a post-watermark tree with zero post-watermark admissions: the epoch
court refuses an unattributed tree. This is the §3.5 leg working as designed
(a real court that fires), not a defect. A passing epoch.check requires the
projected artifacts to carry alive receipts — which requires §3.4 to work,
which is BLOCKED at HEAD (D1).

## 4. Deltas to a real landing (the F1 runbook's §6 checklist stays unfilled)

- **D1 (BLOCKER): the W8 projection corpus is untracked.** `git ls-files`
  at canonical `main` shows NONE of: `lib/ggen_igniter/semantic_jira/
  projection.ex`, `lib/ggen_igniter/landing_pipeline*`, `lib/ggen_igniter/
  review*`, `lib/ggen_igniter/convergence*`, the `--pack-lock` branch of
  `lib/mix/tasks/semantic_jira.execute.ex`, `lib/mix/tasks/
  ggen_igniter.review.pipeline.ex` family, `test/fixtures/projection-pack/`,
  `test/ggen_igniter_semantic_jira_projection_test.exs`. A fresh clone or
  `git archive` of HEAD has no projection backend at all. F1's §2
  precondition "per-lane commits landed on main" is not satisfied; the F1
  run must happen AFTER the W8 landing commit lands.
- **D2: restamp refusal requires a COMMITTED tree change.** The watermark
  identity is `rev-parse HEAD^{tree}` + `git ls-files` — working-tree drift
  (uncommitted edit, or an untracked new `lib/**.ex`) does not trigger
  `restamp_required`. The runbook's "over a changed tree it refuses" needs
  the word "committed": proven by probe P1 (below). Documented honest
  residue in `epoch_watermark.ex` (records tracked files only), but the
  runbook text overstates it.
- **D3: `--packs-root` naming law.** `Path.join(packs_root, target_pack)`
  means the pack's directory name must equal its `pack.toml` `[pack].name`,
  else `target_pack_mismatch` (reproduced: dir `projection-pack-fixture`,
  name `projection-fixture-pack`). The runbook §3.4 note about
  `pack.toml` name matching should name the directory-name-equals-pack-name
  requirement for the packs-root backend explicitly.
- **D4: `git archive`/fresh-clone portability.** Beyond D1, the projection
  fixture pack directory and its tests are not carried by `git archive`;
  the F1 runbook §3.4 fixture note should say which pack the F1 run uses
  (the bootstrap pack at `~/ggen-marketplace/...` per §2) and that the
  fixture pack is working-tree-only.
- **D5 (runbook text): §3.4's `--pack-lock` example is the only projection
  invocation; the tracked task ignores unknown long options silently**
  (`--pack-lock` was accepted without exit 2 by the tracked task — it
  landed in OptionParser `invalid` and was not checked). A silent flag drop
  is a real invocation-boundary gap to fix in the tracked task (validate
  `invalid == []`).

D5 was confirmed three ways: (a) `grep -n pack_lock` over the tracked
`lib/mix/tasks/semantic_jira.execute.ex` and
`lib/ggen_igniter/semantic_jira/execute.ex` in the scratch tree — zero
matches, so the flag is an unknown long option to the tracked task; (b) the
invocation silently ran the local backend and hit the EEx compile refusal
`undefined variable "capability"` — the named-query scoping
(`capability=<scope.rq>`) is provided only by the untracked
`Projection.project/2`; (c) `mix run` calling `Projection.project/2`
directly in the scratch tree raises
`function GgenIgniter.SemanticJira.Projection.project/2 is undefined`.

## 5. Probes (non-vacuity receipts)

- **P1 (watermark restamp, committed-tree law)**: mutated tracked
  `lib/ggen_igniter/actuate.ex`, committed, watermark without `--restamp`:

  ```
  {"code":"restamp_required","detail":"epoch v26.10.20 already stamped at a different tree; pass restamp: %{reason: ...} to redefine the epoch boundary","refused":"EPOCH_WATERMARK"}
  EXIT=1
  ```

  Working-tree-only edits: exit 0 (three probe attempts, including one
  vacuous attempt on an untracked file and one on a tracked `.md` outside
  the `lib/**/*.ex` glob — both vacuous by construction and recorded as
  such). Restamp with reason: exit 0, reason recorded. Restore: byte-exact
  vs the archive original (`git show 686640f:lib/ggen_igniter/actuate.ex |
  shasum` = `20912c9f8e55ae8d4f8ec2037bd1b7f9d112729ef9191223d29a859ae96ec6ab`
  = on-disk sha after revert commit).

- **P2 (render-digest mutation probe)**: **NOT RUN** — requires a successful
  §3.4 execution to mutate against; blocked by D1. The real F1 run must run
  P2 (corrupt one artifact byte → typed refusal → byte-exact restore), per
  runbook §1 leg 1 + mutation-probe law. Recorded as an OPEN requirement,
  not a skip.

P2 is the non-vacuity leg of F1; without it there is no F1. This document
is explicitly marked NOT the F1 receipt.

## 6. Typed-refusal register (all real, all pasted above)

| # | refusal | hop | exit | fired by |
|---|---|---|---|---|
| 1 | `EPOCH_WATERMARK restamp_required` | watermark | 1 | committed tree change, no `--restamp` |
| 2 | `REFUSED:EPOCH_UNATTRIBUTED_IMPLEMENTATION` | admit | 0 (summary) | impl-plane `plan_touches`, no manufacture_plan |
| 3 | `missing_alias` | descriptor | 1 | alias not passed for order's repository |
| 4 | `base_drift` | execute | 1 | base_sha ≠ target HEAD |
| 5 | `target_pack_mismatch` | execute | 1 | dir name ≠ pack.toml name (packs-root) |
| 6 | `invalid_invocation` (backend exclusivity) | complete | 2 | packs-root w/o target_pack on order |
| 7 | `sync_failed` (EEx `capability` unbound) | execute | 1 | projection backend absent at HEAD |

## 6b. Vacuous-probe register (honest residues of this rehearsal)

- V1: `touch`-only (mtime) probe — blob/tree identity unchanged → idempotent
  exit 0. Not a restamp probe.
- V2: untracked-file probe — watermark stamps `git ls-files` only.
- V3: tracked `.md` probe (outside the `lib/**/*.ex` glob) — correctly
  ignored by the glob.
- V4: admit "no-epoch leg" probe — the `sed '/"epoch"/d'` deleted whole
  candidate lines, not the key; `admitted=0 refused=0` proved nothing. The
  non-epoch byte-identical leg is covered by the repo's own
  `ggen_igniter_epoch_admission_test.exs`, which the real F1 run must cite
  as a receipt.
- V5: zsh `${PIPESTATUS[0]}` is not zsh (`pipestatus`, lowercase); early
  probe exit codes were captured through a re-run with direct capture.

The register shows the probes were hardened iteratively until they bit; the
real F1 run should reuse the hardened forms, not the vacuous ones.

## 7. Canonical checkout integrity

No commits, no working-tree mutations, no `_build-lane-e8` in canonical
(the lane build root lived in the scratch tree). Untracked scratch files
in the scratch git: `candidates.jsonl`, `work_orders.json`, `deps` symlink,
`standing-ledger.ndjson`, `candidates_noepoch.jsonl`; committed scratch
history: base → probe commit → revert commit (both documented above).
Canonical `git status` is unchanged from session start (verified below in
the final receipt).

## 8. Next actions for the real F1 run

1. Land the W8 corpus (D1) — coordinator-owned commits to `main`.
2. Fix D5 in the tracked task (validate `invalid == []` → exit 2).
3. Update runbook §3.1 (committed-tree wording), §3.4 (packs-root naming
   law D3), §3.4 (fixture note D4).
4. Re-run the full runbook including P2 (render-digest mutation probe) and
   the §3.5 `epoch.check` exit-0 leg after §3.4 succeeds.
5. Fill runbook §6 checklist from the real run — this rehearsal deliberately
   leaves it unfilled.
