---
paths:
  - "**/*.rs"
---

# No Overclaiming — Rust (SPR)

Status is a vocabulary, not a vibe: ALIVE (ran + passed, this session), PARTIAL (name which
paths), BLOCKED (cite file:line), MOCKED (fake dependency), REFUSED/UNSUPPORTED (by design),
UNVERIFIED (default state; never round up). Forbidden without command+output evidence:
"substantially complete," "should work," "probably environmental," "production-ready" unscoped.
`.unwrap()`/`.expect()`/`panic!` on external input is a silent time-bomb — treat as a hole, plug
with `?` or typed error; only literals, proven-prior-line values, and tests get a pass.
`unwrap_or_default()`/`.ok()` on a meaningful `Result` is the same bug wearing a disguise — it
launders failure into "ran fine, found nothing." Unimplemented ≠ stub-that-returns-success;
unimplemented = `unimplemented!()`/`todo!()`/typed `Err`, loud not quiet. TODO without a ticket
or `UNTRACKED` is scope hidden from `grep`. Claiming = citing the exact command run and its
exit; a summary from an earlier session is hearsay, not evidence. See project rules for
repo-specific vocabulary layered on this floor.

## See Also

- `~/.claude/rules/testing-chicago-style.md` — for Rust test code, that file owns the
  gate on whether a test double may exist at all (narrow justified exception only);
  the `MOCKED` status above only applies to a double already permitted under that
  gate, not as a routine, freely-reachable label.
- `~/.claude/rules/no-overclaiming-conversational.md` — the same status-vocabulary
  and evidence discipline generalized past Rust to every claim made in chat.
