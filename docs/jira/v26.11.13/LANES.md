# LANES

Standing: UNVERIFIED

Lane index for v26.11.13 (ash_a2a end-to-end projection via ggen). Gap ids come from
`00-OVERVIEW.md`. Pack = `/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack`.

## Lanes

| lane | gap | owned files |
|---|---|---|
| g1-tera | G1 | `lib/ggen_igniter/pack_frontmatter/tera.ex`, `tera_test.exs` |
| g1-cli | G1 | `lib/mix/tasks/ggen_igniter.sync.ex` seam, `test/mix/tasks/ggen_igniter_sync_pack_frontmatter_test.exs` |
| g2-igniter | G2 | `lib/ggen_igniter/pack_frontmatter/ea_admission.ex` + test |
| g2-pack | G2 | pack `L30_*` |
| g3-relock | G3 | `test/ggen_igniter_pack_relock_test.exs` |
| g4-strict | G4 | pack `L31_*` |
| l21-hddl | G5 | pack `L21_*` (hddl_operator) |
| l22-authority | G5 | pack `L22_*` (authority, hooks) |
| l23-argmap | G5 | pack `L23_*` (argument_mapping) |
| l24-getq | G5 | pack `L24_*` (get?) |
| l25-destroy | G5 | pack `L25_*` (destroy accept) |
| l26-multidomain | G5 | pack `L26_*` (multi-domain agents) |
| l27-dispatch | G8 | pack `L27_*` (dispatch round-trip test) |
| l32-shimcourt | G6 | pack `courts/` (template mutation courts) |
| l28-gates-a | G7 | pack gates 040+ (first half) |
| l29-gates-b | G7 | pack gates 040+ (second half) |
| census-tera | G1 | read-only: tera constructs census |
| census-gates | G7 | read-only: gate non-vacuity census |
| doc-index | all | `docs/jira/v26.11.13/LANES.md` (this file) |

## Rules

- Lanes own disjoint files; no lane runs git state commands.
- Census lanes are read-only and write no files.
- Standing is UNVERIFIED until a lane receipt with command output lands.

## See Also

- `docs/jira/v26.11.13/00-OVERVIEW.md`
- `docs/jira/v26.11.13/01-LANES-INDEX.md`
- `docs/jira/v26.11.13/02-GAP-REGISTER.md`
- `docs/jira/v26.11.13/03-VERIFY-LADDER.md`
- `docs/jira/v26.11.13/L19-g1-g3-design.md`
