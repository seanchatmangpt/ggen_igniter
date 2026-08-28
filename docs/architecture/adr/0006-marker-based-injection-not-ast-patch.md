# ADR-0006: Marker-Based Line Splice for Injection, Deferring Real AST-Based Mutation

## Status

**Accepted** for what is implemented (`GgenIgniter.Actuate.inject_content!/5`).
Real AST-based structural patching (`Sourceror`/`Igniter.Code`) is named as
explicit, disclosed follow-on work in this same source — **Proposed at
most, not built** — this ADR does not claim that half is Accepted.

## Context

`ggen_igniter` needed a way to splice generated content into an
**existing** file the pack does not fully own (as opposed to `write_file!/3`,
which owns the whole file). Two real mechanisms were available in
principle:

1. **Line-anchored text splice** — read the file as a string, find a
   marker line (literal string or regex match), insert new lines before/
   after/at an explicit line number.
2. **AST-based structural patch** — parse the file into a syntax tree
   (via `Sourceror.Zipper`/`Igniter.Code`), locate a node structurally
   (a function definition, a `use` call), patch the tree, re-serialize.

`ggen_igniter` already has a real, unconditional dependency on `igniter`
(see the CLI-task rationale in `docs/integrations/igniter/project-actuation.md`),
which exposes the AST-based option — but using it was not undertaken this
pass.

## Decision

Implement `inject_content!/5` as a real, line-oriented marker splice
(modeled on the real Rust `ggen`'s `inject_into`/marker-selection semantics
from `ggen-engine/src/write.rs`'s `FM-WRITE-003`/`FM-WRITE-004` fail-closed
gates — mirrored, not called into), with three fail-closed gates (target
must already exist; `before`/`after` marker must match exactly one line;
`at_line` must be in range) and a real idempotency check so re-running the
same injection never duplicates the block. Defer the AST-based structural
patch as explicit, disclosed future work.

## Consequences

- This is genuine **text/line-level manipulation, not AST manipulation** —
  the target file is never parsed into an Elixir AST or a `Sourceror.Zipper`
  anywhere in this function. It cannot survive a marker line being
  reformatted or reflowed across multiple lines, and cannot target "the
  second argument of this specific function call" the way a real structural
  patch could.
- `GgenIgniter.Frontmatter`'s `before`/`after` fields support both a literal
  string and a structured `MatchRule` (matcher/case-sensitivity/trim), but
  `scope: :file`, any non-default `occurrence`, and `trim: true` paired
  with a non-`:exact` matcher have **no equivalent** in this mechanism —
  using one of those raises a clear, named "not yet supported" error rather
  than silently approximating it.
- A real Igniter/Sourceror AST patch remains **PLANNED**, not
  PARTIAL_ALIVE — there is no partial AST-patch code path anywhere in
  `lib/` today (confirmed by a real grep with zero matches on
  `Igniter\.Project\|Igniter\.Code\|Sourceror\.`).
- The marker-based splice is real, tested, and load-bearing today — this
  ADR does not treat it as a stopgap to be apologized for, only as one half
  of a two-mechanism design where the second half has not been built.

## See also

- `docs/integrations/igniter/ast-mutation.md` — full mechanism contrast
- `docs/integrations/igniter/safety.md` — the fail-closed gates in the
  broader write-safety picture
