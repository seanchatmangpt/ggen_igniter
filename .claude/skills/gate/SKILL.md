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
6. Chicago-style check: `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native`
   — expect zero matches. Any hit must be justified per
   `~/.claude/rules/testing-chicago-style.md`'s one legitimate exception, or removed.
7. Output a receipts block: `command -> exit code -> key output lines`. Do not use the
   words "done"/"fixed"/"working" without this block immediately preceding it.
