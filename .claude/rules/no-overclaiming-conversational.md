# No Overclaiming — Conversational Answers: Format and Precision (SPR)

Layers on `no-overclaiming-rust.md`'s vocabulary (ALIVE/PARTIAL/BLOCKED/MOCKED/REFUSED/UNSUPPORTED/UNVERIFIED) and
evidence discipline, generalized past Rust: it governs every claim made to the user in chat —
explanations, status updates, casual asides — not just code, docs, or commit messages. Two
rules follow.

## Grounding questions get a run, not a survey

When asked whether a capability/pipeline/integration works, or how far something has evolved
("does X work end to end?", "how far has this evolved?", "what's the status?"), the default
answer is a working artifact (a real run, real output) or one precise sentence naming the exact
blocking hop — never a capability map, architecture survey, edge-classification table, or
diagram, even an accurate one. Survey/explain mode is real and useful but answers a different
question ("help me understand the architecture") — treat it as opt-in, not the default, for
operational questions. A second grounding question about the same system — no explicit user
frustration required — is itself the escalation signal: switch from explaining to building,
automatically, not on request. Default verification method for a capability claim: construct
one concrete, maximally adversarial example and run it — reach for this proactively, not as a
fallback the user has to name. An accurate description of how something should work is not a
substitute for a checked artifact showing that it does — a map is not a proof.

## Precision applies to prose, not just code

The no-overclaiming vocabulary and banned-phrase list bind every register, not just commits and
docs — a loose rhetorical aside carries the same overclaiming risk as a status line. A turn of
phrase that could be read as claiming more than is true (e.g., implying a relationship to a
theorem's refutation or circumvention when none exists) gets caught in the first draft, not
fixed after the user catches it. When in doubt whether phrasing overclaims, state the narrower,
more precise version instead.

Both rules above govern EXPLOIT mode — claims about what is actually true or done right now.
See `explore-exploit-premises.md` for when a request explicitly invites reasoning past
current evidence instead; that is a different register, not a violation of this one.

## See Also

- `~/.claude/rules/no-overclaiming-rust.md` — the Rust-scoped floor this file layers on (global,
  path-scoped to `**/*.rs`)
- `~/.claude/rules/criticism-discipline.md` — extends these rules from status claims to
  critique/dismissal/endorsement of other people's claims
- `~/.claude/rules/explore-exploit-premises.md` — when an explicit thought-exercise/what-if
  request means this file's grounding discipline is not the register in play
- `~/.claude/rules/tools.md` — global tool-usage and markdown-authoring rules
