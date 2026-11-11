# REVIEW_STATE

Persistent round state for the `review-round` / `adjudicate-findings` skills.
Round cap: 3. Findings are never deleted — closed ones stay as history with
their closing round. Resolutions are append-only history.

## Round

- current_round: 1
- base_sha: 1a6e60d6fed9c2adb06a2c097bbc83e8529f007e
- rounds_run: 1
- verdict: `VERDICT: 1/3 | 0 open findings (5/5 closed-by-fix, verified on disk 2026-10-20); 0 blockers, 0 majors, 0 minors; PROCEED`

## Findings

Schema (every field REQUIRED; a finding missing any field is not a finding):

- `id`: `R<round>-<seq>`
- `severity`: `blocker|major|minor`
- `bug-class`: `correctness|concurrency|resource-leak|error-handling|security|api-misuse|data-loss|type-soundness|test-gap|style`
- `invariant`: cited surface (1-6) or doc/ADR/README section
- `file:line`
- `status`: `open|closed`
- `what`: description of the flagged condition
- `fix criterion`: what observation closes it (test, code state, or cited artifact)
- `resolution` (on close): fixed | WONTFIX | DUPLICATE | BY-DESIGN | NOT-A-BUG | TEST-GAP-ONLY, each citing an artifact
- `closing round` / `verifying command` (on close-by-fix)

| id | severity | bug-class | file:line | invariant | what | fix criterion | status |
|----|----------|-----------|-----------|-----------|------|---------------|--------|
<!-- example (do not keep): | R1-01 | major | correctness | lib/ggen_igniter/receipt.ex:42 | Surface 3 | <what was flagged> | <test name that must pass> | open | -->

| id | severity | bug-class | file:line | invariant | what | fix criterion | status |
|----|----------|-----------|-----------|-----------|------|---------------|--------|
| R1-1 | major | correctness | lib/ggen_igniter/semantic_jira/epoch_plan.ex:114-135 (+ epoch_freshness.ex watermark_globs/1) | root CLAUDE.md epoch-boundary section ("Admission refuses known-illegal plans before any byte is written"); epoch_plan.ex matcher comment | Plane-set divergence: impl_globs/1 uses ONLY recorded watermark globs while EpochFreshness widens to recorded ++ default_globs; under an old lib-only watermark a plan line touching config/migrations passes admission (bytes written) then refuses at `mix ggen_igniter.epoch.check` — the exact admission≠proof two-layer failure the epoch law forbids | impl_globs/1 applies the same union as the court (or freshness recorded-only); one shared resolver for both callers, proven by a plan-line-vs-court agreement test | closed |
| R1-2 | major | error-handling | lib/ggen_igniter/convergence.ex:296-300 | convergence.ex moduledoc carry/clear law + finding @type (hunk_id optional) | Findings without :hunk_id fall out of the split_with and silently vanish (neither carried nor cleared nor re-posted) from round 2 onward, contradicting "cleared only when hunk disappears or class fixed globally" | hunk-less findings route to carried unconditionally, or a typed refusal of hunk-less reviewer output; test: feed a hunk-less finding through step/3, assert it is carried | closed |
| R1-3 | minor | style | docs/status.md (new convergence/security evidence cells) | docs/status.md sourcing header; no-overclaiming receipt-cited-counts rule | Evidence cells cite RED counts (convergence 4/16, security_gate 6/7, security_receipt 5/8, security_review CompileError) that no longer reproduce — re-run this pass is GREEN (51 tests, 0 failures, exit 0) | refresh the four evidence cells to a current green run with command + count | closed |
| R1-4 | minor | correctness | lib/ggen_igniter/convergence.ex:160 | convergence.ex record type (findings_new vs findings_carried distinction, diff-only re-review law) | decide/3 defaults findings_new to the FULL open set, so a caller passing findings_carried but not findings_new records carried findings as newly discovered | default findings_new to [] (or open -- carried); test asserting the record on that call path | closed |
| R1-5 | minor | resource-leak | lib/ggen_igniter/semantic_jira/complete.ex:189-198 | complete.ex "purely additive" comment; security_review.ex moduledoc (--check read mode) | security_pre_step/1 calls SecurityReview.run/2 with default write: true on every order hop, writing security-findings.json + receipts/security/<sha>.json into the subject worktree mid-landing (gate mutates the tree being landed; no cleanup on blocked path) | pre-step runs with write: false (read-only compute path); verdict identical, subject tree byte-unchanged | closed |

### Closing resolutions (adjudication, 2026-10-20 — write lane)

All five closed-by-fix; each fix verified on disk at adjudication time:

- R1-1 `resolution: fixed` — `lib/ggen_igniter/semantic_jira/epoch_plan.ex:132-145`:
  `impl_globs/1` now returns `Enum.uniq(recorded ++ EpochWatermark.default_globs())`,
  matching `EpochFreshness.watermark_globs/1` (epoch_freshness.ex:314-315)
  recorded-∪-default semantics; comment cites the court's clause. Verifying command:
  `grep -n "impl_globs\|watermark_globs\|default_globs" lib/ggen_igniter/semantic_jira/epoch_plan.ex lib/ggen_igniter/epoch_freshness.ex`.
- R1-2 `resolution: fixed` — `lib/ggen_igniter/convergence.ex` split_with (~:301-309):
  `hunk_id = Map.get(f, :hunk_id); (hunk_id == nil or MapSet.member?(current_ids, hunk_id)) and ...`
  — hunk-less findings carried unconditionally, per the carry/clear law comment.
- R1-3 `resolution: fixed` — `docs/status.md:220-221`: evidence cells refreshed to
  fresh green runs (`19 tests, 0 failures` convergence; `32 tests, 0 failures`
  security_gate/receipt/review), with prior RED receipts disclosed as closed.
- R1-4 `resolution: fixed` — `lib/ggen_igniter/convergence.ex:160-165`:
  `findings_new` defaults via `Keyword.get_lazy` to `open -- carried`
  (`Enum.reject(findings, &(&1 in carried))`).
- R1-5 `resolution: fixed` — `lib/ggen_igniter/semantic_jira/complete.ex:229-232`:
  `SecurityReview.run(cwd: cwd, write: false)` with dated comment (R1-5, 2026-10-20).

## Verdict log

Format: `VERDICT: <round>/3 | N blockers, M majors, K minors; PROCEED only if blockers==0`

- R1: `VERDICT: 1/3 | 0 blockers, 2 majors, 3 minors; PROCEED only if blockers==0`
  Round 1 full review of the uncommitted v26.10.20 wave. Reviewer gate evidence:
  `MIX_BUILD_ROOT=_build-review1 mix test test/ggen_igniter_security_gate_test.exs
  test/ggen_igniter_security_receipt_test.exs test/ggen_igniter_convergence_test.exs
  test/ggen_igniter_security_review_test.exs` → 51 tests, 0 failures, exit 0.
  Chicago grep: 3 hits, all benign (regex literals + one fixture diff-string; no test doubles).
  Surfaces 1/3/4 clean (manifest, cross-engine, injection untouched).
- Adjudication 2026-10-20 (write lane): all five findings closed-by-fix, each fix
  re-read on disk before closing. `VERDICT: 1/3 | 0 open findings (5/5 closed-by-fix);
  0 blockers, 0 majors, 0 minors; PROCEED`.
