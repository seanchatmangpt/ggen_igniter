# feat: adopt ADR 0010 gate directory convention + remediate misfiled gates

## Summary

- **ADR 0010** (`9690f9d`) records the directory-is-convention decision:
  `gates/*.rq` are witness-reporting (>= 1 row = PASS, 0 rows = FAIL, scored by
  `GgenIgniter.GateVerify`); `verify/*.unbound.rq` are offender-reporting
  (0 rows = PASS, >= 1 row = FAIL, scored by `mix ggen_igniter.verify` through
  the pack's `verify/cardinality.json` contract).
- **Remediation** (`f754170`): ADR-mandated docstring change in
  `lib/ggen_igniter/gate_verify.ex` — a gate's pass/fail convention is the
  directory it ships in. Docs-only; no behavior change. The pack re-home half
  (evidence-standing-pack all 8, state-transition-pack 010/020/050 = 11
  offender-shaped gates) landed in the ash_pplan vendor corpus at `0523ad9`
  with its Oxigraph courts; recounted misfiled inventory = 0 (ADR inventory:
  evidence-standing 8 + state-transition 3 = 11).
- **Cleanup** (`ed704ba`): removed the unrenderable `ard_prd.ttl.eex` draft
  (project query matches no in-repo GoalCheckpoint graph; committed as a rider
  on `9690f9d`, recoverable there) — removes the permanent PackHealth failure.
- **Falsifier**: misfiled inventory = 0 (was 11: evidence-standing 8,
  state-transition 3).

## Verification receipts

- `pack_state_transition_court`: 24 tests, 0 failures.
- `standing_parity` courts: green.
- `gate_verify`: 13 tests, 0 failures.
- Pack health: 8 tests, 0 failures (post-`ed704ba` deletion).
- Full suite at this PR's head (`7907a21`, `MIX_BUILD_ROOT=_build-ao3`):
  1550 tests, 23 failures, 5 skipped, 720 excluded
  (25 doctests, 42 properties; 721.7s). The 23 failures are outside the
  touched surface (gate_verify + pack health both 0 failures); triage of
  those failures is not owned by this lane.

## Known residuals

- **cardinality.json unblocker** — ENGINE-LIMIT on `EXISTS` handling in the
  sparql engine (oxigraph/qlever `FILTER NOT EXISTS` variants, see
  `lib/ggen_igniter/query/oxigraph.ex`); tracked as Item 3 of
  `ECO-UPSTREAM-IGNITER-FIXES.md` (Option B per-gate `"mode"` flag deferred
  until DERIVED_ROWS proves out).
- OTP pin env mismatch: repo pins elixir 1.19.5-otp-27 (`4d54c19`); local env
  may differ — use the pinned toolchain.

## Merge notes

- No push performed; merge is user-gated.
- Files: ADR (`9690f9d`), docstring fix (`f754170`), draft removal (`ed704ba`),
  plus branch-head docs commits. `.github/` untouched by this lane.
