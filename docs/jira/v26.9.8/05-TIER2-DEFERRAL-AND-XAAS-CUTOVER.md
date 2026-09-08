# Tier-2 Ash Task Deferral and xaas Case-Study Cutover Criteria v26.9.8

> **STILL CURRENT IN SUBSTANCE, PRE-EXECUTION IN FRAMING.**
> [00-OVERVIEW.md](00-OVERVIEW.md)'s status table records this ticket as UNCHANGED:
> the Tier-2 deferral holds and `xaas` stays deferred. What has changed around it is
> that the Tier-1 path it gates on was executed —
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) — so the cutover bar below
> is now assessable rather than hypothetical. Two tasks this ticket defers,
> `ash_postgres.setup_vector` and `ash_postgres.gen.resources`, have since been
> given typed rows in the pack ontology (`UNKNOWN` and `UNSUPPORTED` respectively);
> see [02-ASH-TASK-VALIDATION-MATRIX.md](02-ASH-TASK-VALIDATION-MATRIX.md). The
> status line below is the pre-execution framing; the overview's table governs.

**Status: PLANNED / NOT STARTED.** Forward plan only, no implementation attempted. Ticket
GGEN-1901 (Tier-2 deferral record) and GGEN-1902 (xaas cutover criteria), per the numbered
`NN-TOPIC.md` convention in `docs/jira/v26.9.1/` (see `00-OVERVIEW.md` and
`04-SYNC-SHELLOUT-AND-VERIFY.md` there for the tone/structure this file matches). Nothing
in this ticket set is committed; the only artifacts on disk are tickets 01/03's untracked
fixture and pack (`DRY-RUN-RECEIPT.md`), and no code or test exists for this ticket (05).

## 1. Tier-2 tasks: deliberate scope cut, not silent omission

Per `~/.claude/rules/no-overclaiming-conversational.md`'s grounding rule — a capability claim
needs a checked artifact, never a bare status line — none of these Tier-2 tasks have any
`ggen_igniter` wiring, test, or `sh_before:`/`sh_after:` frontmatter today. They are named here
as **unchecked and deferred**, not as silently absent from the v26.9.8 validation matrix.

| Task | Why deferred | Real future trigger condition |
|---|---|---|
| `ash_admin.install` | Admin-UI extension, no Tier-1 Ash resource lifecycle dependency | A consumer pack requests admin UI scaffolding |
| `ash_authentication.install`, `ash_authentication_phoenix.install` | Auth extension, separate config/domain surface from core resource gen | A consumer pack needs login/session scaffolding |
| `ash_double_entry.install` | Ledger-specific extension; xaas's own `Xaas.Ledger.*` resources are a disclosed sensitive-exposure decision, not a generic template target | A non-xaas consumer pack needs ledger scaffolding |
| `ash_events.install` | Event-sourcing extension, no current pack demand | A consumer pack requests event-sourced resources |
| `ash_graphql.install` | GraphQL API extension, orthogonal to resource lifecycle | A consumer pack requests a GraphQL surface |
| `ash_json_api.install` | JSON:API extension, orthogonal to resource lifecycle | A consumer pack requests a JSON:API surface |
| `ash_money.install` | Money-type extension, narrow domain need | A consumer pack models currency fields |
| `ash_oban.install` | Background-job extension, separate supervision-tree wiring | A consumer pack needs async job resources |
| `ash_onetime.install` | Narrow one-time-token extension | A consumer pack needs one-time-token flows |
| `ash_phoenix.gen.*` | Phoenix LiveView form/UI generation, UI layer not resource layer | A consumer pack needs LiveView form scaffolding |
| `ash_rate_limiter.install` | Rate-limiting extension, no current pack demand | A consumer pack requests rate limiting |
| `ash_state_machine.install` | State-machine extension, narrower than default Ash lifecycle | A consumer pack models explicit state machines |
| `ash_typescript.install` | Client codegen extension, output-projection concern not resource-authoring | A consumer pack needs TS client generation |
| `ash_postgres.setup_vector` | pgvector extension, not needed by any current pack | A consumer pack requires vector-similarity search |
| `ash_postgres.gen.resources` | Reverse-generation (DB → resources), opposite direction from this repo's ontology-forward generation model | A consumer pack needs schema-first reverse scaffolding |

## 2. xaas cutover criteria

The xaas Next Read case study (`~/xaas/docs/case-studies/next-read/`: `README.md`,
`ILS-AND-EXPLANATION-SUBSTITUTION.md`, `DEFINITION-OF-DONE.md`, `RCA-ggen-tool-confusion.md`,
`FMEA-ggen-tool-selection.md`) is **paused, not cancelled**. It resumes only once **both**:

(a) This v26.9.8 ticket set's Tier-1 validation (ticket 02's 26-row matrix — the parent
    overview's Tier-1 prose names 28 tasks and explains the difference — exercised against
    the on-disk, uncommitted `test/fixtures/book_library/` real-`mix.exs`,
    real-`{:ash, "~> 3.0"}`/`{:ash_postgres, "~> 2.0"}` fixture, contrasted with the non-compiled
    `test/fixtures/ash-lifecycle-pack`) is real-**DONE** with cited evidence — real command
    output, `git diff` idempotency proof per the definition in the parent overview, not a status
    claim; AND

(b) xaas is independently "ready to be live" per the user's own words.

**Concrete xaas-readiness criteria for (b) are not yet defined anywhere in either repo.** This is
a real, named open question for the user — not invented here, and not to be filled in by
inference from existing xaas docs. Until the user states what "ready to be live" means
concretely (which gates, which environment, which sign-off), condition (b) cannot be marked met
regardless of how condition (a) resolves.

## See Also

- `00-OVERVIEW.md` (this directory) — current per-ticket status table; `DRY-RUN-RECEIPT.md` —
  the dry-run evidence for tickets 01/03. Condition (a) above is unaffected: no Tier-1 row has
  been executed, so this ticket stays PLANNED / NOT STARTED.
- `docs/jira/v26.9.1/00-OVERVIEW.md`, `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` — the
  ticket-set convention this file matches
- `lib/ggen_igniter/telemetry/ocel_emitter.ex` — existing OCEL v2 infra Tier-1 validation wires
  into, not rebuilds
- `~/xaas/docs/case-studies/next-read/` — the paused case study this ticket set gates the resumption of
- `~/.claude/rules/no-overclaiming-conversational.md` — the grounding-claim rule cited in §1

Claude-Session: https://claude.ai/code/session_01K6xoATrg9HDDL9JBvjpPNC
