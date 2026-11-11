# F1_RUNBOOK

# F1 Reference-Receipt Runbook (v26.10.20)

**STATUS: NOT-YET-EXECUTED.** Every command below is a planned invocation
grounded in the real CLI moduledocs (`lib/mix/tasks/semantic_jira.execute.ex`,
`lib/mix/tasks/semantic_jira.complete.ex`, `lib/mix/tasks/ggen_igniter.epoch.*.ex`,
`lib/mix/tasks/ggen_igniter.review.pipeline.ex`) as of 2026-10-20. No invocation
in this document has been run; no receipt named here exists yet. This document
is the procedure, not evidence of execution.

## 1. What F1 is

From `RESTART_HANDOFF.md` §4 / `PRD.md` §7 — the kill criterion:

> the reference receipt replays with `|Δ|=0` — any nonzero delta between
> recorded and recomputed state refuses the receipt; if a mutated artifact
> still admits, F1 is violated and the pipeline is not ALIVE.

`|Δ|=0` concretely means BOTH:

1. **Every target byte is covered by a receipt with a matching render
   digest.** For each artifact under `--target-dir`, the completion run's
   per-order receipt (`<receipts-dir>/<sanitized-identity>.json`) carries the
   projection record `{order_id, capability_id, pack_digest, render_digest,
   gate_results}`; the `render_digest` recomputed over the bytes on disk must
   equal the recorded one. A byte with no receipt, or a digest that differs,
   is a nonzero delta and the receipt must refuse on replay.
2. **`mix ggen_igniter.epoch.check` exits 0** over the post-landing tree —
   every implementation-plane file carries an ALIVE_* verdict
   (`ALIVE_GENERATED` / `ALIVE_FRESH_RESIDUE`); any `REFUSED_*` or
   `UNKNOWN_PROVENANCE` verdict is a nonzero delta.

A mutation probe (deliberately corrupt one artifact byte, re-run admit +
execute, expect a typed refusal, restore byte-exact) is the non-vacuity leg:
if the mutated artifact still admits, F1 is violated.

## 2. Preconditions (all must hold before step 1)

- **Green gate receipt**: the full gate has landed a real, currently-passing
  receipt — `mix compile --warnings-as-errors` + `mix test` with output
  persisted (the `gate` skill's receipt law). No green receipt, no F1 run.
- **Per-lane commits landed**: all wave lanes' atomic commits are on `main`
  (coordinator-owned git transitions; `_LANES.md` ownership respected;
  `_build-lane-*` dirs deleted before the final integration commit).
- **Pack present**: the pack-bootstrap pack exists at
  `~/ggen-marketplace/packs/pack-bootstrap-pack` (verified on disk
  2026-10-20). Its `pack.toml` `[pack].name` must match the executed orders'
  `sj:targetPack` — a mismatch refuses `REFUSED(target_pack_mismatch)` at the
  execute hop before anything runs.
- **Backlog prepared**: admitted work-order candidates JSONL + standing
  ledger (`--work-orders` / `--ledger`) exist and the frontier is populated.

## 3. Invocation sequence (watermark → observe → admit → execute/complete → check)

### 3.1 Watermark (epoch boundary identity)

```
mix ggen_igniter.epoch.watermark --epoch v26.10.20
```

Stamps path + git-blob-SHA for every `lib/**/*.ex` file into
`.ggen_igniter/epoch/v26.10.20/watermark.json`. Idempotent over an unchanged
tree; over a changed tree it refuses unless `--restamp REASON` is passed.

### 3.2 Observe (optional leg — prose to candidate)

Only when the backlog is fed from an observed process finding:

```
mix semantic_jira.observe --finding PATH --base-work-order PATH \
  --origin-authority https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority \
  [--identity ID] [--out PATH]
```

`--origin-authority` is required (INVARIANT A); a missing or unadmitted IRI
is a typed exit-1 refusal (`missing_origin_authority` / `origin_not_admitted`).

### 3.3 Admit (fail-closed plan gate, with epoch binding)

```
mix semantic_jira.admit_candidates --candidates PATH \
  --epoch-manifest .ggen_igniter/epoch/v26.10.20/watermark.json
```

One verdict per line. Orders carrying `"epoch"` are judged by
`EpochPlan.check/2`; a missing/unreadable manifest with epoch lines present
refuses every epoch line (fail closed). No `--epoch-manifest` means the epoch
binding leg is simply not exercised for this run — say so in the receipt.

### 3.4 Execute (projection backend) or Complete (multi-order loop)

Single order, pack-lock-pinned projection backend:

```
mix semantic_jira.execute --work-orders PATH --ledger PATH --identity ID \
  --verifier-suite SUITE \
  --pack-lock PACKLOCK --pack-dir ~/ggen-marketplace/packs/pack-bootstrap-pack \
  --target-dir DIR --receipt-out PATH
```

Multi-order backlog (per-order `sj:targetPack` resolution under a packs root):

```
mix semantic_jira.complete --work-orders PATH --ledger PATH \
  --packs-root ~/ggen-marketplace/packs \
  --target-dir DIR --receipts-dir .ggen_igniter/receipts \
  [--template PATH] [--max N] [--out PATH]
```

Notes grounded in the moduledocs:

- Exactly one backend per invocation (`--pack-dir` XOR `--packs-root` XOR
  `--receipt`; mixing them is exit 2, `pack_source_exclusive/1`).
- The **projection** backend (`--pack-lock` on `execute`) requires the order
  to carry `capability_id` + `target_path` and rides
  `{order_id, capability_id, pack_digest, render_digest, gate_results}` in
  the receipt's `"projection"` record — this is the render digest `|Δ|=0`
  is checked against.
- The completion receipt at exit 0 has `closed`, `orders`, `blocked`,
  `ledger`, `closed_count`, `blocked_count`. Blocked rows are **settled
  work** (the kernel's own blocked rows with their own reasons) — never
  re-executed, never a failure.
- Exit 1 = first per-order refusal stopped the loop; the refused iteration
  wrote nothing. Exit 2 = invalid invocation. There is **no** `--fail-closed`,
  `--work-order`, or standalone `--target-dir`-only flag; those do not parse.

### 3.5 Prove the bytes (epoch check)

```
mix ggen_igniter.epoch.check --epoch v26.10.20 [--report PATH]
```

Exit 0 = every implementation-plane file ALIVE. Exit 1 = designed refusal
verdict (a nonzero delta). Promotion requires BOTH 3.3 (admission) and 3.5
(proof) — admission ≠ proof, proof ≠ prevention.

## 4. Landing pipeline stages 0-7 (the gate around the landing)

`mix ggen_igniter.review.pipeline --base REF [--epoch v26.10.20] [--json]`
runs the fixed ordered registry over one candidate landing, short-circuiting
on the first block:

| stage | name | what it checks |
|---|---|---|
| 0 | `base_integrity` | real git: `rev-parse --verify`, `merge-base --is-ancestor`, worktree-drift |
| 1 | `epoch_check` | the §3.5 freshness court, inside the pipeline |
| 2 | `risk_tier` | risk classification of the diff (drives fan-out width) |
| 3 | `build_gate` | compile/test gate over the candidate |
| 4 | `fanout_review` | adversarial review round (width from risk tier) |
| 5 | `security_block` | planted-secret / unsafe-code block (F4: exit 5 `SECURITY_BLOCKED`) |
| 6 | `convergence_cap` | review-convergence bound |
| 7 | `incident_eval` | incident ledger evaluation |

Exit 0 = every stage ALIVE; exit 1 = BLOCKED (typed JSON on stderr +
`landing-receipt.json` on disk); exit 2 = invalid invocation. Per-stage
receipts land in
`.ggen_igniter/receipts/pipeline/<run_id>/stage-<order>-<name>.json` plus
`landing-receipt.json`. The fixed order is load-bearing (risk tier precedes
fan-out width). The F1 landing is admitted only when the full pipeline exits 0;
a stage block is a typed BLOCKED, never a silent pass.

## 5. Receipt naming: F1_REFERENCE_RECEIPT semantics

- Per-order sealed exports from the local/`--packs-root` backends:
  `<receipts-dir>/<sanitized-identity>.json` — every character outside
  `A-Za-z0-9._-` replaced by `_`. With
  `--receipts-dir .ggen_igniter/receipts`, a reference order whose identity
  sanitizes to `F1_REFERENCE_RECEIPT` lands at
  `.ggen_igniter/receipts/F1_REFERENCE_RECEIPT.json`.
- The F1_REFERENCE_RECEIPT is the receipt that **replays**: `|Δ|=0` is
  computed by re-running §3.3–§3.5 against the recorded state (work-order
  JSON, ledger tail, recorded render digests, watermark blob SHAs) and
  asserting every recomputed digest equals the recorded one and epoch.check
  exits 0 again. Any nonzero delta refuses the receipt on replay.
- Landing-pipeline stage receipts are a separate family:
  `.ggen_igniter/receipts/pipeline/<run_id>/stage-<order>-<name>.json` +
  `landing-receipt.json`.
- Epoch state: `.ggen_igniter/epoch/<epoch>/watermark.json`.
- Daily standing-ledger receipts already exist as
  `.ggen_igniter/receipts/<date>.jsonl`; the F1 run appends its standing
  transitions to the `--ledger` ndjson passed at §3.4, not to those files.

## 6. Execution receipt (to be filled when run)

- [ ] watermark stamped: epoch `v26.10.20`, watermark sha256: ______
- [ ] candidates admitted / refused counts: ______
- [ ] complete exit code + `closed_count` / `blocked_count`: ______
- [ ] per-order receipt paths + render digests: ______
- [ ] `mix ggen_igniter.epoch.check` exit code: ______
- [ ] `mix ggen_igniter.review.pipeline` exit code + run_id: ______
- [ ] mutation probe (corrupt byte → typed refusal → byte-exact restore):
      ______
- [ ] F1 verdict: `|Δ|=` ______ (0 = ALIVE; nonzero = F1 violated, pipeline
      not ALIVE)

## See Also

- `docs/jira/v26.10.20/RESTART_HANDOFF.md` §4 (falsifier register)
- `docs/jira/v26.10.20/PRD.md` §7
- `docs/jira/v26.10.20/_LANES.md`
- `docs/VERIFICATION_LEDGER.md`
- `docs/reference/cli/` (per-task reference pages)
