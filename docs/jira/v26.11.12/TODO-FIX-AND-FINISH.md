# TODO-FIX-AND-FINISH (ggen_igniter)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R8, re-read where marked confirmed.

## Fix

- MED `lib/ggen_igniter/frontmatter.ex:357` `String.to_atom` on frontmatter (confirmed).
  Check: hostile frontmatter does not mint atoms.
- MED `lib/ggen_igniter/schema_dispatch.ex:460` `String.to_atom` on mode (confirmed).
- MED `lib/ggen_igniter/reconcile.ex:307` atom from SPARQL var name (confirmed); `:313` and
  `reconcile_reactor.ex:1414` UNVERIFIED (file not at that path).
- MED `lib/ggen_igniter/semantic_jira/descriptor.ex:110` atom from descriptor keys (confirmed).
- MED lock TOCTOU: `pack_lock.ex:400-402` stale check then rmdir/retry (confirmed);
  `lock.ex:125-127` stale_lock? break-and-retry (confirmed). Check: concurrent-acquire court.
- LOW git-ignored `doc/` copies can drift: UNVERIFIED.

## Finish

- Replace `to_atom` helpers with bounded admission. Check: `rg 'String.to_atom' lib` shows
  only allowlisted sites.

## Commit hygiene

`git status --short` (confirmed): modified 4 `docs/jira/v26.11.10/*` files; untracked
`11-` to `17-` review lenses and `20-TEN-EXPERT-PERSONAS-SYNTHESIS.md`.

## Decide

- Keep the frontmatter atom comment's rationale or switch to string keys end to end?

## Reuse

- `pack_lock.ex:85-96,180-215` pin/digest with symlink-escape refusal (for ash_surface).

## See Also

- `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md`
