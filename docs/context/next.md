# Machine Handoff & Next Obligations

## 1. Active In-Flight Work
- **Branch**: `feat/adr-0010-gate-convention`
- **Plan Reference**: ADR 0010 (`docs/architecture/adr/0010-gate-convention-directory-is-convention.md`)
- **Status**: ADR 0010 (commit `9690f9d`) and the gate remediation (commit `f754170`) have landed on the branch; the draft PR body is `docs/architecture/adr/0010-pr-body.md`; the merge itself is user-gated.

## 2. Delivered This Cycle (all SHAs verified on `feat/adr-0010-gate-convention`)
1. **ADR 0010 — gate directory convention** (`9690f9d`): `gates/` emits witness reports, `verify/` emits offender reports; the convention is the directory, not the filename.
2. **Gate remediation** (`f754170`): ADR 0010's required docstring change in `gate_verify` — directory-is-convention. Companion change in ash_pplan at `0523ad9` (verified in `/Users/sac/ash_pplan`).
3. **CHANGELOG v26.10.3 gap fill** (`6a42dbb`): the v26.10.3 section now carries its full commit range.
4. **`mix pm4pytest` wrapper** (`9e581cf`) + **`PM4PYTEST_BINARY_NOT_FOUND` refusal registration** (`831eaa0`) + **README documentation** (`7907a21`).
5. **ard_prd removal** (`ed704ba`): unrenderable draft removed from the semantic-jira pack.
6. **Graphlaw WASM boot refusal** (`56f79e9`): typed `REFUSED:GRAPHLAW_WASM_ARTIFACT_MISSING` at boot when the artifact is absent.
7. **Receipt-schema currency court**: 37 tests validating the shipped `priv/schema/receipt.schema.json` against the current surface (session court run; no single commit).
8. **MIX_GATE_ENV_ONLY verdict**: gate court verdict — the mix gate honors env-only configuration (session court run; no single commit).

## 3. Not Started (Backlog)
- **cardinality.json ENGINE-LIMIT unblocker**: lift the engine limit that forces cardinality.json to a lower-fidelity fallback.
- **OTP pin decision**: two options on the table — (a) keep host OTP (currently 28) and re-qualify per upgrade, falsifier: a host OTP upgrade changes no test/court outcomes; (b) pin to OTP 27.2.4 (as the `4d54c19` toolchain pin does), falsifier: a build under a different OTP changes test/court outcomes. Unresolved.
- **Periodic receipt-schema court**: schedule the 37-test receipt.schema.json currency court to run per release rather than ad hoc.
- **Host OTP 28 vs pin OTP 27.2.4**: resolution folded into the OTP pin decision above.

## 4. Not Started (Backlog, superseded claims retained for history)
- Release `v26.10.5` exists (`90a5c63`); `v26.10.4` at `0df7eec`, `v26.10.3` at `95f02d4`.
- Elixir 1.19.5-otp-27 toolchain pin recorded at `4d54c19` (pinned re-qualification R2-GI-PIN).
- Credo-zero refactor at `a404697`: 15 behavior-preserving fixes + 7 law-commented exemptions.
