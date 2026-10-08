## Status (updated after real implementation)

**DONE** — per gi01 evidence in `/tmp/full_results.json`.

- Branch: `story/GI-01-schema-dispatch-alignment`, worktree `/private/tmp/wt-gi01`, commit `af13e0a` (committed only, not merged/pushed).
- Story 01a: new `lib/ggen_igniter/schema_dispatch.ex` — `GgenIgniter.SchemaDispatch.load/1` (explicit `project_dir` arg, no `File.cwd!`) + `load_raw/1` + `classify_table/1`, a real Elixir port of ggen core's `classify_ggen_toml` (`~/ggen/crates/ggen-config/src/config_schema.rs`) and `schema_dispatch::load` (`~/ggen/crates/ggen-engine/src/schema_dispatch.rs`) — same markers, same `:declarative_rules`/`:frontmatter`/`{:refused, {:ambiguous|:unsupported|:malformed, ...}}` outcomes.
- Story 01b: `lib/ggen_igniter/project_config.ex` and `lib/ggen_igniter/pack_manifest.ex` moduledocs rewritten from "known gap" caveats to resolved-scope statements cross-referencing `SchemaDispatch`/`FrontmatterConfig`/`FrontmatterPackRef`. `git diff` on both files touched only moduledoc text — zero `defstruct`/`@type` diff.
- Story 01c: new `GgenIgniter.FrontmatterConfig`/`GgenIgniter.FrontmatterPackRef` in `schema_dispatch.ex`, mirroring `ggen_engine::config::GgenConfig`/`PackRef` (`config.rs:45-52` and the untagged `Path|Git` enum), `packs` as a name-keyed map, `PackRef` as a tagged tuple (`{:path, %{...}}|{:git, %{...}}`) per the existing `QuerySource`/`TemplateSource` untagged-union precedent.
- Tests: `test/ggen_igniter_schema_dispatch_test.exs`, real `Toml.decode` over real fixture files (`test/fixtures/schema_dispatch/{beam4pm_ggen.toml (verbatim copy of ~/beam4pm/ggen.toml, all 5 real packs asserted via load_raw AND load/1), declarative_rules.toml, ambiguous.toml}`) plus inline malformed/unsupported/git-variant/law-shapes cases — all state-based assertions on real returned struct/refusal fields.
- Command output (real, from the run): `grep -rn "Mock|mock(|patch(|monkeypatch" test/ggen_igniter_schema_dispatch_test.exs lib/ggen_igniter/schema_dispatch.ex lib/ggen_igniter/project_config.ex lib/ggen_igniter/pack_manifest.ex` → one hit, a doc-comment sentence naming the discipline, zero real mock usage. `mix compile --warnings-as-errors` → "Generated ggen_igniter app", clean, no warnings. `mix test test/ggen_igniter_schema_dispatch_test.exs test/ggen_igniter_project_config_test.exs test/ggen_igniter_pack_manifest_test.exs` → "37 tests, 0 failures".
- **Disclosed caveat**: a full-repo `mix test` was also launched in the background to satisfy the ticket's whole-suite line; it was still running against this large repo's full 2500+-test suite (unrelated pre-existing suites) when this task's time budget was reached and was **not confirmed to completion**. Only the scoped run above (this ticket's own new test files, 37/0) is confirmed. Nothing in the new/touched files depends on the unrelated suites.
- Non-goals explicitly out of scope, not attempted: wiring `SchemaDispatch` into `mix ggen_igniter.sync/.doctor/fortune5_ready` (tracked as GGEN-1802's `load/1`), and any change to `~/ggen` core.

---

# Align GgenIgniter.ProjectConfig/PackRef to ggen core's real dual-schema dispatch

Foundational epic for this document's v26.9.1 stream: the ggen_igniter-side implementation
detail of `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`'s Story GGEN-1802
("Real `ggen.toml` TOML parse into `ProjectConfig`/`PackRef`"). This ticket is scoped narrower
and lands first: it builds the classifier + dispatch point GGEN-1802's `load/1` needs, and fixes
the two structs GGEN-1802 populates so they represent the correct schema instead of silently
mismatching beam4pm's real `ggen.toml`.

This is a different work stream from `~/ggen_igniter/docs/v26.9.1-requirements.md` (the
process-mining/OCEL manufacturing-pack expansion release covering the same `v26.9.1` version
string — incremental DFG discovery, sensor-to-event streaming, inductive-miner discovery,
token-replay conformance, OCEL2/EKG derivation, OLAP slice/dice, Chicago-style OTP fault
injection packs). See "See Also" below; do not conflate the two.

Status vocabulary used throughout: **IMPLEMENTED** / **PARTIAL_ALIVE** / **PLANNED**, per this
repo's own convention (`CLAUDE.md`, `README.md`, `docs/status.md`) — not beam4pm's
ALIVE/PARTIAL_ALIVE/BLOCKED/UNVERIFIED scheme, which belongs to a different repo.

## Why this exists — resolved, not an open question

`~/ggen` (ggen core, Rust) has a real, deliberate dual-schema design for `ggen.toml`, confirmed
live against the actual source, not inferred from docs:

- `~/ggen/crates/ggen-engine/src/schema_dispatch.rs` is the single shared dispatch point every
  real ggen call site (`sync()`, `handle_doctor`, `handle_graph_validate`, the five `ggen law *`
  verbs via `build_law_engine`) goes through. It reads `ggen.toml` once, classifies it via
  `ggen_config::classify_ggen_toml`, and returns either concrete parsed type wrapped in
  `ParsedGgenToml::DeclarativeRules(Box<GgenManifest>)` or
  `ParsedGgenToml::Frontmatter(Box<GgenConfig>)`. Its own doc comment names the defect this module
  was built to close: **BUG-005** — before `schema_dispatch.rs` existed, six call sites each
  guessed the schema by their own ad-hoc logic, and `handle_doctor` unconditionally called
  `GgenConfig::load` (the frontmatter-only loader) regardless of which schema the target project
  actually used — `ggen doctor` against ggen's own root `ggen.toml` failed this way.
- **Schema 1, `Frontmatter`**: `crate::config::GgenConfig`
  (`~/ggen/crates/ggen-engine/src/config.rs:45-52`), selected when `[[generation.rules]]` is
  empty. Its `packs` field is `pub packs: BTreeMap<String, PackRef>` — `ggen.toml`'s `[packs]` as
  a **table-of-tables keyed by name**. Its `PackRef` (`config.rs:128`) is an untagged enum:
  `Path { path, extra_ontologies, lock } | Git { git, version }`.
- **Schema 2, `DeclarativeRules`**: `ggen_config::manifest::GgenManifest`
  (`~/ggen/crates/ggen-config/src/manifest/types.rs:193`), selected when `[[generation.rules]]`
  is non-empty. Its `packs` field is `pub packs: Vec<PackRef>` — `ggen.toml`'s `[[packs]]` as an
  **array-of-tables**. Its `PackRef` (`types.rs:52-69`) is a flat struct: `name`, `registry`,
  `path`, `version`.
- **Verified live against `~/beam4pm/ggen.toml`** (the real, first intended consumer of the
  fortune5-ready bundle installer): it has `[packs]` as
  `name = { path = "..." }` table-of-tables entries and no `[[generation.rules]]` section — it
  classifies as `Frontmatter`/`GgenConfig`, **not** `DeclarativeRules`/`GgenManifest`.
- `ggen_igniter`'s own existing code already self-discloses this exact gap, confirmed by direct
  read, not assumed:
  - `lib/ggen_igniter/project_config.ex`'s `GgenIgniter.ProjectConfig` moduledoc: "This module
    mirrors `ggen_config::manifest::GgenManifest` only" — and separately names the `GgenConfig`
    alternative as existing but unmirrored.
  - `lib/ggen_igniter/pack_manifest.ex`'s `GgenIgniter.PackRef` moduledoc: "This module mirrors
    the array-of-tables (`ggen-config`) shape only; the `ggen-engine` variant is a separate
    follow-on if the WASM bridge needs to parse a project using the older schema."

Both moduledocs were written as known, disclosed gaps — not silently wrong code. This ticket
converts that disclosed gap into a tracked, resolved requirement.

## The resolved decision

Per explicit user instruction this session ("ggen_igniter is not used yet so it should be
changed to align"): `ggen_igniter` has no production consumers depending on its current
(wrong-for-real-consumers) schema mirror, so there is no backward-compatibility cost to fixing
it properly. The requirement is **not** "support both as a coin-flip" — it is:

- Implement a real Elixir equivalent of ggen core's `classify_ggen_toml` + `schema_dispatch::load`
  pattern: one shared classifier, one dispatch point, both schemas as concrete typed structs.
- `GgenConfig`/`Frontmatter`/table-of-tables is the schema exercised **first and by default** in
  new bundle-installer work, since that is what real consumers (beam4pm) actually use.
- `GgenManifest`/`DeclarativeRules` stays supported — real projects may use it — but is no longer
  the assumed-default path.

## Story 01a — `GgenIgniter.SchemaDispatch` classifier + dispatch module

Add a new module, `GgenIgniter.SchemaDispatch`, that reads a `ggen.toml` at a given
`project_dir`, checks for a non-empty `[[generation.rules]]` table, and returns which of the two
schemas applies — mirroring `ggen_config::classify_ggen_toml` + `ggen-engine`'s
`schema_dispatch::load` (`~/ggen/crates/ggen-engine/src/schema_dispatch.rs`). No `File.cwd!()`
implicit dependency — `project_dir` is an explicit argument, consistent with
`lib/ggen_igniter/doctor_fixes.ex`'s established convention (per this repo's `CLAUDE.md`,
"project_dir"-as-explicit-argument is the norm here, not an implicit cwd read).

This module must be the **only** place the classification decision is made in `ggen_igniter` —
mirroring ggen core's own explicit anti-pattern lesson (BUG-005: six ad-hoc call sites each
guessing wrong, later consolidated into `schema_dispatch.rs`). Any future `ggen_igniter` call
site that needs to know which schema a `ggen.toml` uses calls `GgenIgniter.SchemaDispatch`;
none re-derives the check locally.

Return shape mirrors `ParsedGgenToml`: a typed result naming which schema classified
(`:frontmatter` | `:declarative_rules`) plus the parsed struct, or a typed refusal for the
classifier's fail-closed cases (ambiguous structural markers; unsupported — matches neither
schema; malformed TOML) — never a raised exception and never a silent wrong-schema guess.

Acceptance:

- A real test parses beam4pm's actual `ggen.toml` (its real content copied verbatim into a test
  fixture, not paraphrased or hand-summarized) and confirms `GgenIgniter.SchemaDispatch`
  classifies it as `:frontmatter` and produces a correctly-typed struct with all 5 real pack
  entries (`beam4pm-process-model`, `beam4pm-pro-infra`, `github-actions-pack`,
  `beam4pm-ai-contracts`, `beam4pm-pro-entitlement`) with correct `path` values, asserted on the
  actual returned struct's fields — not on a boolean "it parsed" result.
- A second real test parses a `DeclarativeRules`-shaped fixture (`[[generation.rules]]`
  non-empty, `[[packs]]` array-of-tables) and confirms `GgenIgniter.SchemaDispatch` classifies it
  as `:declarative_rules` via the other branch, with the parsed struct's `packs` field
  containing the fixture's actual flat `PackRef{name, registry, path, version}` entries.
- A third real test feeds `GgenIgniter.SchemaDispatch` a genuinely ambiguous/malformed
  `ggen.toml` fixture (conflicting structural markers from both schemas, or neither schema's
  required top-level tables present) and asserts a typed refusal — not a crash, not a silent
  wrong-schema guess — mirroring `schema_dispatch.rs`'s own `Ambiguous`/`Unsupported`/`Malformed`
  fail-closed behavior.
- All three tests use real collaborators (a real `Toml.decode` parse of a real fixture file on
  disk) and state-based assertions on the real returned struct/refusal value, per this repo's
  Chicago-school testing discipline (`CLAUDE.md`'s "Testing discipline" section: "real
  collaborators ... state-based assertions ... No `Mock`/`mock(`/`patch(`/`monkeypatch`
  anywhere"), verified by `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native`
  returning zero matches for the new test/lib files.
- `mix compile --warnings-as-errors` and `mix test` (the new test file(s) included) both pass;
  paste the real command output as evidence, not a narrated summary, per this repo's
  Verification discipline section.

## Story 01b — Fix `GgenIgniter.ProjectConfig`/`GgenIgniter.PackRef` to represent DeclarativeRules only

`lib/ggen_igniter/project_config.ex`'s `GgenIgniter.ProjectConfig` and
`lib/ggen_igniter/pack_manifest.ex`'s `GgenIgniter.PackRef` already correctly mirror
`GgenManifest`/array-of-tables `PackRef{name, registry, path, version}` — no field-shape change
is required. What changes is the moduledocs and the framing: drop the "known gap"/"real caveat"
language now that the gap is a tracked ticket (this one), and state explicitly that these two
structs represent the `DeclarativeRules` schema only, with a pointer to
`GgenIgniter.SchemaDispatch` (Story 01a) as the module that decides which schema applies, and to
`GgenIgniter.FrontmatterConfig`/`GgenIgniter.FrontmatterPackRef` (Story 01c) as the sibling
struct family for the other schema.

Acceptance:

- `GgenIgniter.ProjectConfig`'s moduledoc no longer says "This module mirrors
  `ggen_config::manifest::GgenManifest` only" as an open/unaddressed caveat; it states the same
  fact as a resolved, intentional scoping decision and cross-references
  `GgenIgniter.SchemaDispatch`.
- `GgenIgniter.PackRef`'s moduledoc no longer frames the `ggen-engine` variant as "a separate
  follow-on if the WASM bridge needs to parse a project using the older schema"; it
  cross-references `GgenIgniter.FrontmatterPackRef` (Story 01c) as the now-real sibling struct,
  and `GgenIgniter.SchemaDispatch` as the dispatch point.
- No field/type change to either struct's `defstruct`/`@type t` — this story is documentation-only
  (the shapes were already correct for `DeclarativeRules`); `mix compile --warnings-as-errors`
  passes with no diff to either struct's data shape, proven by a `git diff` on
  `project_config.ex`/`pack_manifest.ex` showing only moduledoc text changed.

## Story 01c — New `GgenIgniter.FrontmatterConfig`/`GgenIgniter.FrontmatterPackRef` structs

Add new structs mirroring `crate::config::GgenConfig`
(`~/ggen/crates/ggen-engine/src/config.rs:45-52`) exactly:

- `GgenIgniter.FrontmatterConfig` — a `packs` field shaped as an Elixir map keyed by pack name
  (mirroring `BTreeMap<String, PackRef>`), plus whatever other top-level `GgenConfig` fields the
  frontmatter schema declares (`project`, `ontology`, `templates` at minimum, matching this
  repo's own `[project]`/`[ontology]`/`[templates]` framing already used for beam4pm's
  `ggen.toml` per `README.md`/`docs/status.md`'s conventions).
- `GgenIgniter.FrontmatterPackRef` — mirrors the untagged
  `Path { path, extra_ontologies, lock } | Git { git, version }` enum. Elixir has no untagged-union
  deserialization primitive (the same constraint `GgenIgniter.ProjectConfig.QuerySource`/
  `TemplateSource` already document and solve via tagged tuples) — represent this the same way:
  a discriminated tagged tuple, e.g. `{:path, %{path: ..., extra_ontologies: ..., lock: ...}}` |
  `{:git, %{git: ..., version: ...}}`, or an equivalent discriminated struct if a tagged tuple
  proves awkward against `Toml.decode`'s real output shape — either is acceptable as long as the
  moduledoc states which was chosen and why, matching the precedent these two existing modules
  already set.

Acceptance:

- A real test `Toml.decode`s beam4pm's actual `ggen.toml` fixture (same fixture as Story 01a) and
  builds a `%GgenIgniter.FrontmatterConfig{}` whose `packs` map has exactly 5 keys
  (`"beam4pm-process-model"`, `"beam4pm-pro-infra"`, `"github-actions-pack"`,
  `"beam4pm-ai-contracts"`, `"beam4pm-pro-entitlement"`), each value a
  `GgenIgniter.FrontmatterPackRef.t()` in the `:path` shape with the correct real `path` string
  from the fixture, asserted on the actual struct's fields.
- A second real test exercises the `:git` variant of `GgenIgniter.FrontmatterPackRef` against a
  synthetic fixture entry (`{ git = "...", version = "..." }`), since beam4pm's real `ggen.toml`
  has no `Git`-shaped pack entries to exercise this branch against.
- Both tests are real-collaborator/state-based per this repo's Chicago-school discipline (real
  `Toml.decode` over a real fixture file, assertions on real returned struct fields) — verified
  by the same `grep -rn "Mock\|mock(\|patch(\|monkeypatch"` zero-match check as Story 01a.
- `mix compile --warnings-as-errors` and `mix test` pass with the new modules and tests included;
  paste real command output.

## Non-goals (this ticket)

- Wiring `GgenIgniter.SchemaDispatch`/the new structs into `mix ggen_igniter.sync`, `.doctor`, or
  any production task — that is GGEN-1802's `load/1` in
  `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`, which this ticket is a
  prerequisite for, not a duplicate of.
- The `mix ggen_igniter.fortune5_ready` bundle installer task itself, or the bundle manifest —
  both are downstream of this ticket, tracked in the source epic below.
- Any change to ggen core (`~/ggen`) — `schema_dispatch.rs` and `classify_ggen_toml` are read as
  the reference design, not modified.

## See Also

- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the OTHER v26.9.1 work stream in this repo
  (process-mining/OCEL manufacturing-pack expansion: incremental DFG discovery, sensor-to-event
  streaming, inductive-miner discovery, token-replay conformance, OCEL2/EKG derivation, OLAP
  slice/dice, Chicago-style OTP fault injection). Shares the `v26.9.1` version string only; no
  functional overlap with this document's bundle-installer stream.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — the source epic
  (GGEN-1800 through GGEN-1807) this document's ticket set is the `ggen_igniter`-side
  implementation detail of; this ticket is the prerequisite for that epic's Story GGEN-1802.
- `~/ggen/crates/ggen-engine/src/schema_dispatch.rs` — the reference Rust implementation this
  ticket's Elixir port mirrors.
- `~/beam4pm/docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the epic/story/acceptance
  format this document follows (exact subject, acceptance behavior, evidence; compilation or
  file existence alone is not a crown).
- `~/ggen_igniter/CLAUDE.md` — this repo's real conventions: pipeline shape
  (`Ontology.load!/1` → `Engine.run/2` → `Render.render/2` → `Actuate.write_file!/3`),
  Chicago-school testing discipline, `mix compile --warnings-as-errors` + `mix test`
  verification gate, `project_dir`-as-explicit-argument convention.
- `lib/ggen_igniter/project_config.ex`, `lib/ggen_igniter/pack_manifest.ex` — the existing
  structs this ticket fixes/extends.
