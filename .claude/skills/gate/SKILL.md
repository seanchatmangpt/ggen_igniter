---
name: gate
description: Run the full verification gate for ggen_igniter and report receipts before claiming any work done
---

Run this before claiming any implementation, fix, or refactor is complete.

1. Confirm location: `pwd && git remote -v && git rev-parse --abbrev-ref HEAD`. Verify
   this is `ggen_igniter` before proceeding — never assume cwd.
2. Run, capturing full real output (never summarize instead of pasting):
   - `mix compile --warnings-as-errors`
   - `mix test`
   - `mix dialyzer` (only if `.plt` already built; otherwise note it was skipped and why)
3. For every file you edited this session, re-`Read` it and quote the changed lines —
   confirm the change is actually on disk, not just claimed. An edit you did not
   re-read did not happen.
4. `git diff --stat` and `git diff` on the specific changed hunks; confirm the diff
   matches your stated intent. Empty diff or unintended file touched = stop and report,
   don't continue.
5. Classify every failing test/warning as PRE-EXISTING (was already broken before this
   session's changes — cite the baseline) or INTRODUCED-BY-ME.
6. Chicago-style check (the regex pinned in `test/CLAUDE.md` — do NOT use the older
   `grep -rn "Mock\|mock(\|patch(\|monkeypatch"` form, which cannot tell a real mock
   from `assert_has_patch/3` or from moduledoc disclosures quoting banned tokens):
   `grep -rn --include='*.ex' --include='*.exs' --include='*.rs' --include='*.py' --exclude-dir=_build --exclude-dir=deps -E '(use|import) +(Mox|Mimic|Patch)\b|(Mox|Mimic|Patch)\.|:meck\.|mockall|MagicMock|Mock\(' test lib native`
   — expect exit 1 with zero output. Any hit must be justified per
   `~/.claude/rules/testing-chicago-style.md`'s one legitimate exception, or removed.
7. Output a receipts block: `command -> exit code -> key output lines`. Do not use the
   words "done"/"fixed"/"working" without this block immediately preceding it.
8. After the receipts block, print every `status=open` finding in
   `docs/REVIEW_STATE.md` VERBATIM (id, severity, class, file:line, invariant).
   If the file is absent or has no open findings, print `OPEN FINDINGS: none`.
   Claiming "done" while OPEN findings exist is invalid — adjudicate them first
   (`adjudicate-findings` skill) or state `NEEDS-HUMAN`.
9. Review-eval gate: if this session's diff touches
   `.claude/agents/ggen-reviewer.md` or `lib/ggen_igniter/review_eval/`, run
   `mix ggen_igniter.review_eval.gate` and paste its real output with the
   receipts block. If the module/task does not exist yet (the review-eval lane
   has not landed), note it as `review_eval.gate: not-yet-landed` in the
   receipts block — that is a disclosure, not a failure.
