# TODO-FIX-AND-FINISH (ggen_igniter)

Standing: PARTIAL_ALIVE

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R8, re-read where marked confirmed.
Updated 2026-11-18 finish slice — see `docs/jira/v26.11.18/RECEIPT-finish-slice.md`.

## Fix

- ~~MED `lib/ggen_igniter/frontmatter.ex` `String.to_atom` on frontmatter~~ **CLOSED**
  — `MatchRule` enums use closed allowlist tables; hostile matcher raises.
- ~~MED `lib/ggen_igniter/schema_dispatch.ex` `String.to_atom` on mode~~ **CLOSED**
  earlier (`parse_generation_mode/1` allowlist; commit `136be4c`).
- ~~MED `lib/ggen_igniter/reconcile.ex` / `reconcile_reactor.ex` / `sync.ex`
  SPARQL binding atomize~~ **CLOSED** via `GgenIgniter.BindingKeys.atomize!/1`
  (identifier charset+length; not a closed name allowlist — query authors
  choose vars).
- ~~MED `lib/ggen_igniter/semantic_jira/descriptor.ex` atom from descriptor keys~~
  **CLOSED** — compile-time `@binding_atoms` allowlist over `@render_keys` ∪
  `@identity_keys`.
- MED lock TOCTOU: `pack_lock.ex` / `lock.ex` stale check then rmdir/retry
  (confirmed). Check: concurrent-acquire court. **IN PROGRESS** — fix landed
  in this wave, see `docs/jira/v26.11.18` (not CLOSED; closure needs the gate).
- LOW git-ignored `doc/` is generated ExDoc output — non-issue, not a source
  of drift to track.

## Finish

- Replace `to_atom` helpers with bounded admission. **PARTIAL** —
  `rg 'String.to_atom' lib` still hits install/DoctorFixes/refusals/
  review_eval/rename_options (trusted or operator-shaped inputs). SPARQL
  binding sites now go through `BindingKeys`. PackFrontmatter.Tera compare
  ops closed without `to_atom` (lane 6, 2026-11-18).

## Decide (operator)

- ~~Keep the frontmatter atom comment's rationale or switch to string keys?~~
  **DECIDED this slice:** keep atom enum fields; admit via allowlist (no
  string-key rewrite).
- Flip Controller `use_reactor` default? **OPEN** (see v26.11.18 FINISH).
- Restore `Receipt.to_prd_status/1`? **NO** — superseded by `RProjection`.
- Hex publish of `26.11.18`? **OPEN** (local tarball evidence is 26.11.10).
- ~~Wire `[ontology.aggregate]` into sync?~~ **CLOSED 2026-11-18** —
  `OntologyAggregate.enforce_project/2` on `Reconcile` +
  `ReconcileReactor`; marker `.ggen_igniter/aggregate-freshness`
  (SHA-256). Standing: **IMPLEMENTED** (`docs/status.md`,
  `docs/jira/v26.11.18/FINISH.md`).

## Reuse

- `pack_lock.ex:85-96,180-215` pin/digest with symlink-escape refusal (for ash_surface).

## See Also

- `docs/jira/v26.11.18/FINISH.md` — open operator decisions (canonical)
- `docs/jira/v26.11.18/RECEIPT-finish-slice.md`
- `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md`
