# v26.9.27 re-manufacture wave plan for v26.10.1 (epoch-006)

`Repo_26.10.1 = μ_26.10.1(O*_≤26.9, Marketplace_≤26.9, MachineExperience_≤26.9)` — waves manufacture new projections from pack facts; no wave edits `lib/` in place. The planning layer itself is already pack-expressed: `doctrine-hddl-pack` projects strategy graphs to HDDL+FOND; these waves are its first self-application.

| wave | input pack facts | manufactured output | falsifier | depends on |
|---|---|---|---|---|
| W0: the boundary | `sj:EpochBoundary` facts (semantic-jira-pack, landed this wave) + stamp runbook (_RUNLOG epoch-003) | `.ggen_igniter/epoch/v26.10.1/watermark.json` at the final v26.9 head; inventory frozen | re-stamp at a different tree refuses `:restamp_required` without a reason (witnessed pattern, freshness test 13) | extraction waves E1–E3 landed |
| W1: attribution layer | `manufacture-attribution-pack` (extraction-backlog order 1) | fresh receipt/manifest/artifact-identity projections; epoch court consumes them unchanged | generated-then-mutated refusal still fires on the new layer (freshness test 7 analog) | W0 |
| W2: sync engine | `ggen-sync-engine-pack` | new `ggen_igniter.sync` manufactured task; the calver day pipeline re-rendered through it | book_library A–L ladder re-run byte-identical (`qualify.sh` all rungs) | W1 + E1 |
| W3: sJira kernel projections | `semantic-jira-pack` kernel-contract facts (CLI template paydown, ledger 2026-09-23) | the six CLI shells + kernel refusal clauses rendered byte-identical from pack | rendered shells == shipped shells; drift_check analog exits 0 both directions | W2 |
| W4: epoch enforcement | epoch court stays code; its parameters (glob, threshold) come from `sj:EpochBoundary` facts | nothing new to render — verification wave | `epoch.check --epoch v26.10.1` must be ALIVE on the new tree; admission gate refuses legacy-edit orders (admission corpus analogs) | W1–W3 |
| W5: falsify + promote | carried courts (courts.md CARRY set) run against the new projection UNCHANGED | promotion receipt per the invariant: `Promotable(T) ⟺ AdmittedPlan(T) ∧ EpochCheck(T)=ALIVE` | a carried court failing is evidence against the projection — never a reason to edit the court | W4 |
| W6: delete old | extraction receipts + fresh manufacture receipts + W5 promotion | pre-epoch `lib/**` deleted; evidence archived first (evidence-continuity.md procedure) | `epoch.check` on the emptied-and-remade tree: no REFUSED_LEGACY_EDIT remains; ledger delta recorded | W5 |

## Standing rules across all waves

- Courts are not candidates: carried test files stay byte-identical; a red carried court blocks promotion.
- Every wave's receipts are the standing evidence; `inspection ≠ execution`, `workflow ran ≠ success`.
- A wave that cannot name its falsifier is not admitted (zero-information check law).
-UNKNOWN residue per wave goes through admit_candidates as orders; standing comes from receipts, never prose.
