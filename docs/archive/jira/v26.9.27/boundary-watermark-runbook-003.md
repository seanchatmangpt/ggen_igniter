<!-- manufactured by ggen_igniter --pack calver-ticket-day (public ns: oslc_cm + dcterms + prov + earl + aps)
     stage chain: 守→柲→算→除→偽→延→実  (APS OperatorGlyph — https://w3id.org/chatman/aps#) -->

# boundary-watermark-runbook-003: Execute and record the boundary watermark runbook, in pre-form, on this tree
status: OPEN
created: v26.9.27

## Mission

The 26.9->26.10 boundary procedure: at the final v26.9 head, commit all implementation state, run mix ggen_igniter.epoch.watermark --epoch v26.10.1, and archive the stamp. Today it executes in pre-form: stamp --epoch v26.9.27-pre at HEAD, run epoch.check (expected: real refusals — the gate must refuse its own makers), run epoch.explain on one file; capture command/exit/output in the day runlog.

## Acceptance

watermark stamp exits 0 with non-empty files; epoch.check exits 1 with standing REFUSED and per-file verdicts; epoch.explain exits 0 with a law string; all three transcripts in _RUNLOG.md

## History
- 2026-09-27T14:5xZ | ALIVE (pre-form) | feat/v26.9.27-epoch-prep | stamp exit 0 (files=104 head=5ac166b), idempotent re-stamp exit 0, check exit 1 standing=REFUSED refused=110 (designed refusal), explain exit 0 with law string | evidence in _RUNLOG.md; real v26.10.1 stamp runs at the final v26.9 head
