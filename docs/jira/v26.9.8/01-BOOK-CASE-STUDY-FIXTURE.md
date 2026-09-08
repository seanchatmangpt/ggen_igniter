# Book library-domain Ash fixture (ggen_igniter v26.9.8)

> **SUPERSEDED — pre-execution history.** This ticket describes the fixture as it
> stood at day zero, before any Ash task had run in it. The fixture has since been
> manufactured into for real and qualified:
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) supersedes this ticket's
> day-zero protocol with `bin/day_zero.sh`, and
> [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md) reviews the result.
> The status below is the pre-execution status and is retained for provenance; the
> status table in [00-OVERVIEW.md](00-OVERVIEW.md) governs on conflict. The findings
> here — the `mix.exs` contrast against `ash-lifecycle-pack` in particular — remain
> accurate.

## Status (pre-execution, superseded)

**DRY-RUN VERIFIED (not executed).** As of 2026-09-08 (repo HEAD `1738ad1`), the
fixture exists on disk at `test/fixtures/book_library/` as an **untracked,
uncommitted** directory. Its day-zero acceptance criteria (below) have been run for
real and pass; evidence is in [DRY-RUN-RECEIPT.md](DRY-RUN-RECEIPT.md) Step 1. No
`mix ash.*`/`mix ash_postgres.*` task has been executed inside it — the fixture is
still at day zero. "Not executed" here means exactly that: the Ash task matrix
(ticket 02) and the two-run idempotency protocol (ticket 04) have not started.

## Scope note — relationship to the xaas Next Read case study

`xaas`'s `docs/case-studies/next-read/` (README.md, ILS-AND-EXPLANATION-SUBSTITUTION.md,
DEFINITION-OF-DONE.md, RCA-ggen-tool-confusion.md, FMEA-ggen-tool-selection.md — all
written in the same session as this document) is **paused, not cancelled**, until
`xaas` itself is ready to go live. This ticket does not resume that case study. It
gives `ggen_igniter` its own, smaller, self-contained validation fixture — a "book
library" domain — for the narrower question that case study surfaced but couldn't
answer cheaply: can `ggen_igniter` drive real Ash Igniter tasks (`ash.gen.domain`,
`ash.gen.resource`, ...) executably and idempotently, against a real compiling Ash
project, without a full xaas-sized domain in the loop.

## Why a new real project, not `test/fixtures/ash-lifecycle-pack`

`test/fixtures/ash-lifecycle-pack` has no `mix.exs` and is confirmed (this session)
never compiled against a real `:ash` dependency — its `templates/domain.ex.eex` hand-
renders a full Elixir module textually, duplicating what a real Igniter generator
does, and it cannot detect whether the generated code actually compiles or whether
`ash.gen.domain`'s own config.exs wiring behavior is exercised at all. It is a
template-shape fixture, not an executable-task fixture. The book library fixture is
the opposite: a genuine separate `mix.exs` project with real `{:ash, "~> 3.0"}` and
`{:ash_postgres, "~> 2.0"}` deps, compiled for real, so `mix ash.gen.domain` /
`mix ash.gen.resource` run as themselves — real AST-aware `Igniter.Mix.Task`s, not
simulated by an EEx template.

## Location: `test/fixtures/book_library/`, not an ephemeral `System.tmp_dir!()` build

Decision taken and realized: an **on-disk fixture at `test/fixtures/book_library/`**
(currently untracked — intended to be committed, not yet committed), not a fresh
scratch project rebuilt into `System.tmp_dir!()` per test run.

One-sentence reason: `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` already
established that this machine's `/tmp` is not shared into the docker-wrapped `ggen`
binary (`docker run -v /tmp/...:/workspace ... ls /workspace` returned empty) while
`System.tmp_dir!()` (`~/.cache/tmp`) is — but the book library fixture's own subject
under test is Ash/Igniter tasks running via plain `mix`, not a `ggen` docker shellout,
so that container-sharing constraint doesn't force ephemeral placement here; a
committed fixture instead gives every ticket in this set (idempotency re-runs, CI, a
human `cd`-ing in to inspect a diff) the same day-zero state to start from, which an
`System.tmp_dir!()` rebuild-per-run would erase between runs.

## Minimal real domain shape

Deliberately small — explicitly **not** the fuller `xaas` Next Read scope (holds,
reservations, recommendation ranking, ILS integration substitution). Two resources:

- **Book**: `title`, `author`, `isbn`, `published_year`.
- **Loan**: `book_id`, `borrower`, `checked_out_at`, `returned_at`.

No policies, no extensions, no relationships beyond `Loan.book_id` referencing `Book`.
The goal is to exercise the tier-1 Ash task validation matrix (separately ticketed),
not to model a real library system.

## Minimal real deps

As written on disk in `test/fixtures/book_library/mix.exs`:

```elixir
defp deps do
  [
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:igniter, "~> 0.6", only: [:dev, :test]},
    # Deviation from ticket 01's three-dep list, disclosed: the ticket 03
    # harness runs `mix ggen_igniter.sync` from INSIDE this fixture (cwd =
    # fixture root), so the parent repo must be resolvable as a path dep.
    {:ggen_igniter, path: "../../..", only: [:dev, :test]}
  ]
end
```

**Deviation from the original three-dep spec, disclosed:** the fourth dep,
`{:ggen_igniter, path: "../../.."}`, is forced by ticket 03's working-directory
decision (run `mix ggen_igniter.sync` from inside the fixture root). Resolved
versions per `deps/*/mix.exs`: `ash 3.33.1`, `ash_postgres 2.13.1`, `igniter 0.8.4`.

Plain `Ash.Resource` directly for both `Book` and `Loan` — no custom base-resource
wrapper module, so the fixture doesn't introduce a variable this ticket set isn't
trying to test. (Neither resource exists yet; they are created by ticket 02's rows,
which have not run.)

## Real day-zero tree

`find . -path ./deps -prune -o -path ./_build -prune -o -type f -print | sort` from
inside the fixture (verified 2026-09-08):

```text
./.formatter.exs
./.gitignore
./config/config.exs
./config/dev.exs
./config/prod.exs
./config/test.exs
./lib/book_library.ex
./mix.exs
./mix.lock
./test/test_helper.exs
```

`lib/book_library.ex` is a bare moduledoc module. `config/config.exs` has
`config :book_library, ash_domains: []`; no `ecto_repos:`, no `Repo`, no
`Application` module, no repo block in any env config — matrix rows 1 and 11 are the
steps that add those. `.gitignore` covers `/_build/`, `/deps/`,
`/.ash-validation-receipts/`, `/.ggen_igniter/`, `erl_crash.dump`.

## Acceptance criteria (day zero, before any `ash.gen.*` task runs)

1. `test/fixtures/book_library/mix.exs` exists. **Met** (untracked; tree above).
2. `mix deps.get` succeeds inside `test/fixtures/book_library/` (real network/hex
   fetch, not stubbed). **Met** — `deps/` and `mix.lock` are populated; the resolved
   versions above come from the fetched `deps/*/mix.exs`.
3. `mix compile` succeeds on the empty day-zero app — no resources, no domain yet,
   just the bare `{:ash, "~> 3.0"}, {:ash_postgres, "~> 2.0"}` scaffold compiling
   clean before ticket 02's `ash.gen.domain`/`ash.gen.resource` matrix runs against
   it. **Met** — real output (receipt Step 1):

   ```text
   $ cd test/fixtures/book_library && mix compile --force --warnings-as-errors ; echo "compile exit=$?"
   ==> ggen_igniter
        ... (5 `warning:` lines, all under ==> ggen_igniter: pack.ex x3, ggen_igniter.doctor.ex,
             engine_registry.ex -- pre-existing in the path dep, none in the fixture)
   Generated ggen_igniter app
   ==> book_library
   Compiling 1 file (.ex)
   Generated book_library app
   compile exit=0
   ```

   The 5 warnings are pre-existing in the parent repo's path dep, not introduced by
   the fixture; `book_library` itself compiles with zero warnings.

Hygiene, also run: `grep -rn "unittest.mock\|Mock(\|MagicMock\|patch(\|monkeypatch\|Mox\b\|:meck\|meck\." lib test config ../ash_tier_matrix_pack`
→ no matches, exit 1; `grep -rn "/Users/\|/home/"` over the fixture and pack
(excluding `deps/`, `_build/`) → no matches, exit 1.

**Still not done for this ticket:** committing the fixture. The tier-1 Ash task
validation matrix (ticket 02) and the idempotency re-run protocol (ticket 04) that
consume this fixture remain PLANNED / NOT STARTED.

## See Also

- [DRY-RUN-RECEIPT.md](DRY-RUN-RECEIPT.md) — Step 1 is this ticket's compile
  evidence; Step 3 shows the dry run left the day-zero tree unchanged.
- `03-SH-AFTER-ALLOW-SH-HARNESS.md` — the harness whose working-directory decision
  forces the `ggen_igniter` path dep above.
- `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` — source of the `/tmp` vs
  `System.tmp_dir!()` container-sharing finding cited above.
- `lib/ggen_igniter/telemetry/ocel_emitter.ex` — existing OCEL2 emitter this fixture's
  future sync runs should wire into for evidence capture (separate ticket).
- `~/xaas/docs/case-studies/next-read/` — the paused, larger case study this fixture
  narrows down from.

Claude-Session: https://claude.ai/code/session_01K6xoATrg9HDDL9JBvjpPNC
