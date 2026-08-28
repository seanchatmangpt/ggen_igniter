# `mix ggen_igniter.doctor`

Source: `lib/mix/tasks/ggen_igniter.doctor.ex` (`Mix.Tasks.GgenIgniter.Doctor`).
Status: **IMPLEMENTED** — every flag and every one of the 17 checks below is
verified against that module's `info/2` schema (lines 84–93) and the
`igniter/1` implementation.

`mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID] [--hex-check] [--fix]`

Runs a fixed checklist of real checks — no fabricated pass output; every
check either executes a real command/read or reports a real fact. Exits
non-zero (`System.halt(1)`, called directly — not routed through Igniter's
own `--check` halt mechanism) if and only if any check comes back `:error`.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--pack NAME` | string | *(none)* | Enables checks 9–12 (pack-scoped: ontology, gate queries, template). |
| `--pack-dir DIR` | string | *(none)* | Same as `--pack` but uses `DIR` directly. |
| `--engine sparql\|qlever` | string | *(none — no reachability/dep check unless given)* | `qlever` adds the `:gno` dependency check (#2) and the QLever reachability check (#8). Note: unlike `sync`, doctor's `--engine` schema does **not** accept `"oxigraph"` as a meaningful value here — it only branches on the literal string `"qlever"`; passing anything else (including `"oxigraph"`) simply skips checks #2's `:gno` requirement and #8 entirely. |
| `--store-id ID` | string | *(required for check #8 when `--engine qlever`)* | Same `gnoa:Qlever` store resource id as `sync`'s `--store-id`. |
| `--hex-check` | boolean | `false` | Enables check #16 (`mix hex.build` + package metadata) — off by default because it shells out and is slow. |
| `--fix` | boolean | `false` | Applies real, safely-recognized fixes for checks #4–#7 and #17 directly to the current project (`File.cwd!()`) instead of only reporting them. |

## The 17 checks

Checks always run unless noted. Checks 9–12 run **only** with
`--pack`/`--pack-dir`. Check 8 runs only with `--engine qlever`. Check 16
runs only with `--hex-check`.

1. **Elixir/OTP version** — `System.version()` satisfies `~> 1.17` and
   `:erlang.system_info(:otp_release)` is `>= 25` (this project's own
   `mix.exs` requirement). `:error` if either fails.
2. **Required deps loaded** — `:rdf`, `:sparql`, `:igniter` always; `:gno`
   additionally when `--engine qlever`. Each checked via
   `Application.ensure_loaded/1` + `Application.spec(app, :vsn)`. `:error`
   naming every missing app if any are unresolvable.
3. **`sparql` hex package advisory** — warns if the loaded `:sparql` version
   is `<= 0.3.12`: that version's known `FILTER NOT EXISTS` + `BIND` inside
   `UNION` bug raises `Protocol.UndefinedError` (see
   `GgenIgniter.Query.Qlever`'s moduledoc); recommends `--engine qlever` for
   gate queries with that shape. Always `:warn`/`:ok`, never `:error` (and
   `:warn` if `:sparql` itself isn't loaded, since the version can't be
   checked).
4. **Current project's `igniter` dep not `:only`-restricted** — real
   conflict: `ggen_igniter` needs `igniter` unconditionally, so a consumer
   declaring it with `only: [:dev, :test]` makes Mix's resolver refuse.
   `--fix` relaxes it for real.
5. **Same check, for `sourceror`** — only applicable if the current project
   declares `sourceror` directly at all.
6. **`config :dcatr, env: ...` present** — required whenever `:gno`/`:dcatr`
   are in the dependency tree (`Gno`'s `Fuseki` adapter raises at compile
   time without it). `--fix` adds the missing entry.
7. **Every `use Ash.Domain` module registered in `config :OTP_APP,
   ash_domains: [...]`** — an unregistered domain is a hard compile error
   under `mix compile --warnings-as-errors`. `--fix` registers any missing
   one(s).
8. **QLever endpoint reachable** (only with `--engine qlever`) — resolves
   `--store-id` against the pack ontology graph and runs a real `ASK { ?s ?p
   ?o }` query against it. `:error` if `--store-id` is missing, if no pack
   ontology can be resolved to look it up in, or if the endpoint is
   genuinely unreachable.
9. **Pack `ontology.ttl` exists and parses** — real `RDF.Turtle.read_file/1`
   parse (only with `--pack`/`--pack-dir`).
10. **At least one gate query present** — `<pack_dir>/gates/*.rq` (only with
    `--pack`/`--pack-dir`).
11. **At least one template present** — `<pack_dir>/templates/*.{eex,tmpl}`
    (only with `--pack`/`--pack-dir`).
12. **Every gate query is syntactically valid SPARQL** — parse-only via
    `SPARQL.query/1` (`sparql` hex package's parser), no execution (only
    with `--pack`/`--pack-dir`). `:warn` (not `:error`) if there are no gate
    queries to parse at all.
13. **Target (cwd) git status** — `git status --porcelain`; reports clean vs.
    dirty as `:ok`/`:warn`. Never `:error` — including when the directory is
    not a git repo at all, or `git` isn't on `$PATH` (both report `:warn`,
    "not a git repo (or git not on PATH): ..."), so this check alone never
    fails the aggregate run.
14. **`native/ggen_graph_nif` compiled and up to date** — resolves the
    crate's real on-disk location first (this project's own `File.cwd!()`
    when dogfooding, or the resolved dependency path
    `Mix.Project.deps_paths()[:ggen_igniter]` when running as a consumer's
    dependency), then checks whether the built `priv/native/ggen_graph_nif.so`
    exists and is newer than every `.rs` source file under the crate (a fast
    mtime proxy). If missing or stale, falls back to a real `cargo build
    --quiet` and reports real stderr on failure (`:error`).
15. **`GgenIgniter.Query.Oxigraph` functional smoke test** — runs a real
    `SELECT * WHERE { ?s ?p ?o }` against a tiny in-memory `%RDF.Graph{}`
    through the native oxigraph NIF and confirms it returns without raising —
    a functional check, not just "does the NIF load".
16. **hex-publish readiness** (only with `--hex-check`) — shells out to a
    real `mix hex.build` and reports its real output; also checks
    `mix.exs`'s `package[:description]` and `package[:licenses]` are both
    present and non-empty. `:error` if either the build fails or metadata is
    incomplete.
17. **`check_version_policy`** — `mix.exs`'s `version:` literal is treated as
    a *projection* of this project's real, observed versioning convention,
    not an independently maintained field. This repo has no `git tag`s at
    all (confirmed via `git tag --list` returning empty), so
    `CHANGELOG.md`'s topmost `## vX` entry heading is the sole real,
    standing record of "what the current version is" — a calendar-ish
    `YY.M.D` string (e.g. `26.8.27`), matched verbatim against `mix.exs`'s
    `version:`. Reports `MATCH` (`:ok`) or a clearly named `MISMATCH`
    (`:warn` without `--fix`, or fixed and reported `:ok` with `--fix`);
    never silently rewrites `mix.exs`. `--fix` corrects it only when the
    derivation is unambiguous (a single topmost `## vX` heading and a
    simple string-literal `version:`); an ambiguous shape (no
    `CHANGELOG.md`, no `## v` heading, or a non-literal `version:`) is
    reported as informational-only (`:error` from `check_version_policy`'s
    `{:unrecognized, msg}` branch), never guessed at.

## `--fix`

Checks 4–7 and 17 are backed by real fix functions (`GgenIgniter.DoctorFixes`),
not just diagnostics. Checks 4–7 are data-driven — `DoctorFixes.default_rules/0`
— run through one generic `DoctorFixes.run_rule/3` engine, so adding a new
Igniter/Ash wiring-gap class means appending a rule there, not writing a new
hand-written check function in the doctor task itself.

Passing `--fix` applies each detected, safely-recognized fix directly to the
**current project** (`File.cwd!()` — the real consumer app `doctor` is
running inside, never a test-harness scaffold); the check line reports
exactly what changed, prefixed `FIXED:`, or that there was nothing to fix.

Without `--fix`, these checks are strictly read-only:

- A real, fixable problem → `:warn`, naming the exact fix to run (`... -- run
  \`mix ggen_igniter.doctor --fix\` to fix`).
- A real problem whose exact shape isn't safely automatable → `:error`
  rather than silently skipped or guessed at.

A fix that raises (a shape it refuses to guess at) is caught and turned into
a real `:error` check result rather than crashing the whole `doctor` run.

## Output format

Each check prints one line: `✔ message` (`:ok`), `⚠ message` (`:warn`), or
`✘ message` (`:error`). If any check is `:error`, doctor prints `"✘
ggen_igniter.doctor: one or more checks failed (see ✘ lines above)"` and
exits the OS process with code 1 (`System.halt(1)` — a real non-zero exit
regardless of Igniter's own `--check` machinery). Otherwise it adds an
Igniter notice: `"ggen_igniter.doctor: all checks passed (see output
above)"`.

## Examples

```
mix ggen_igniter.doctor
mix ggen_igniter.doctor --pack audit-trail-pack
mix ggen_igniter.doctor --pack audit-trail-pack --fix
mix ggen_igniter.doctor --engine qlever --store-id http://example.com/Qlever --pack audit-trail-pack
mix ggen_igniter.doctor --hex-check
```
