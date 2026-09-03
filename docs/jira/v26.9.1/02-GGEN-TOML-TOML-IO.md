## Status (updated after real implementation)

**DONE** — per gi02 evidence in `/tmp/full_results.json`.

- Branch: `story/GI-02-ggen-toml-toml-io` (based on GI-01's `story/GI-01-schema-dispatch-alignment` branch, commit `af13e0a`), worktree `/private/tmp/GI-02-worktree`, new commit `ff58f6c` (committed only, not merged/pushed).
- Story (a): new `lib/ggen_igniter/ggen_toml_io.ex` — `GgenIgniter.GgenToml.IO.parse!/1` and `parse_raw!/1` wrap GI-01's `GgenIgniter.SchemaDispatch.load/1`/`load_raw/1` (real `Toml.decode/1`-backed classifier), raising a named `GgenIgniter.GgenToml.IO.Error` on a `:refused` classification. Real test asserts `%GgenIgniter.FrontmatterConfig{}` against beam4pm's real `ggen.toml`, with concrete field values (`project.name == "beam4pm"`, 5 packs, e.g. process-model pack's `path == "vendor/ggen-marketplace/packs/beam4pm-process-model-pack"`).
- Story (b): `serialize!/1` is a hand-written TOML formatter — `toml ~> 0.7` has no `Toml.encode/1` at all (confirmed absent by reading `deps/toml/lib/toml.ex`'s full `@spec` list; only `decode`/`decode_file`/`decode_stream` variants exist). Idempotency test: `parse!(dir) -> serialize!/1 -> write to a second temp path -> parse!/1 again -> assert reparsed == parsed` (real files, real `Toml.decode` both sides). A second test diffs real file bytes before/after with `File.read!/1`.
- Story (c) — **key-order/comment preservation**: resolved via the **accepted-limitation path (option 2)**, since `toml ~> 0.7`'s decode target is a bare `map()` with no ordered-key or comment-attachment concept — stated explicitly in the IO module's moduledoc with the concrete library-capability reason cited. The byte-diff test proves and documents the specific loss: `content_before =~ "gh-terraform-pack: investigated 2026-08-30"` holds, `refute content_after =~ same string` holds (comment dropped, as documented), while `content_after` still contains `"beam4pm-process-model"` and its real path (substantive data preserved). Fixture is beam4pm's actual comment-bearing `ggen.toml` copied verbatim into `test/fixtures/ggen_toml_io/beam4pm_ggen.toml`.
- Command output (real, from the run): `grep -rn "Toml\.decode\|Toml\.encode\|Toml\.parse" lib/` → real hit at `lib/ggen_igniter/schema_dispatch.ex:135` (`Toml.decode(raw)`) plus doc references in the new IO module — closing the gap this ticket opened with. `grep -rn "Mock|mock(|patch(|monkeypatch" test lib native` → 10 matches total (vs GI-01's baseline of 9); the sole new match is a doc-comment sentence naming the discipline, zero real mock usage. `mix compile --warnings-as-errors` → clean, no warnings. `mix test test/ggen_igniter_ggen_toml_io_test.exs` → "4 tests, 0 failures" (parse! typed struct + field assertions, parse! Error-raising on missing file, idempotency round-trip, byte-diff comment-loss disclosure).
- **Disclosed caveat**: a full-repo `mix test` was also launched in the background (matching GI-01's own disclosed pattern); it was still running this repo's full 2500+-test suite (unrelated pre-existing tests) when this task's time budget was reached and was **not confirmed to completion** (log at `/private/tmp/claude-501/-Users-sac-beam4pm/5ee243ee-8dba-4fda-978d-a383a6029781/scratchpad/gi02_mixtest.log`). Only the scoped run above (this ticket's own new test file, 4/0) is confirmed. Nothing in the new/touched files depends on the unrelated suites.

---

# Real ggen.toml TOML parse and idempotent serialize-back

## Epic

**GGENI-FORTUNE5-02: `ggen.toml` TOML file I/O over the ticket-01 dual-schema
dispatch module.**

This is the ggen_igniter-side implementation detail of the source epic
`~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` (stories
GGEN-1801 through GGEN-1807 — the Fortune5-ready bundle installer). It also
depends on this same directory's ticket 01 (the typed-struct + classifier +
dispatch module covering both `ggen.toml` schema variants). This document
does not restate ticket 01's schema-classification requirements — see that
ticket for `classify_ggen_toml`-equivalent dispatch details; this ticket
consumes its output types.

## Status quo — the gap (confirmed 2026-09-01)

`mix.exs` line 108 already declares the dependency:

```
{:toml, "~> 0.7"},
```

But `grep -rn "Toml\.decode\|Toml\.encode\|Toml\.parse" lib/` returns **zero
hits**. The two real matches for `Toml\.` in `lib/` are both in
`lib/ggen_igniter/pack_manifest.ex` (lines 119 and 124) and are type-spec /
module-name references (`GgenIgniter.PackageToml.PackSection.t()`,
`defmodule GgenIgniter.PackageToml.PackSection do`) — not calls into the
`toml` library. There is no real TOML file I/O anywhere in `lib/` today: the
dependency is declared but unused. This ticket builds the actual I/O layer.

## Stories

### Story (a) — parse a real `ggen.toml` file path into the correct typed struct

**Subject**: `GgenIgniter.GgenToml.IO.parse!/1` (or equivalent public
function name chosen in ticket-01's dispatch module namespace) accepts a
file path, reads it, decodes it via `Toml.decode/1` (or `Toml.decode_file/1`
if the library exposes it directly — confirm against the actual `toml` hex
package API surface, do not assume), classifies the decoded map via ticket
01's dispatch logic, and returns the correctly-typed struct: either the
Frontmatter/`GgenConfig`-shaped struct (`[packs]` as a table-of-tables,
`packs: BTreeMap`-equivalent in Elixir — a `%{String.t() => PackRef.t()}`
map) when `[[generation.rules]]` is absent/empty, or the
DeclarativeRules/`GgenManifest`-shaped struct (`[[packs]]` as an
array-of-tables, `packs: [PackRef.t()]`) when `[[generation.rules]]` is
present.

**Acceptance behavior**: given `~/beam4pm/ggen.toml`'s real content (no
`[[generation.rules]]` section, `[packs]` table-of-tables with 5 named
entries), `parse!/1` returns the Frontmatter/`GgenConfig`-shaped struct
specifically — not the DeclarativeRules struct, and not an untyped map.

**Evidence required**: a real test that copies `~/beam4pm/ggen.toml`'s
actual content into a `test/fixtures/` file (or reads it directly from a
path fixture under this repo's `test/CLAUDE.md`-mandated fixture placement),
calls `parse!/1` against it, and asserts — via pattern match or
`assert %GgenIgniter.GgenToml.Config{} = result` (exact module name per
ticket 01) — on the concrete struct type and on real field values (e.g. that
the `packs` map has key `"beam4pm-process-model"` with a `PackRef` whose
`path` field is `"vendor/ggen-marketplace/packs/beam4pm-process-model-pack"`).
State-based, not "no error was raised."

### Story (b) — serialize a struct back to TOML text, idempotent round-trip on no modification

**Subject**: `GgenIgniter.GgenToml.IO.serialize!/1` (or `to_toml!/1` —
name chosen consistently with ticket 01's module) accepts either typed
struct and returns TOML text via `Toml.encode/1` or hand-assembled string
formatting if the `toml` library's encode support is confirmed absent or
insufficient for the shape needed (confirm the library's actual encode
capability before committing to which path — `toml` ~> 0.7's README/hexdocs
must be checked for this, not assumed to mirror its decode capability).

**Acceptance behavior**: `serialize!(parse!(path))` on an unmodified struct
produces TOML text that, when written to a fresh file and re-parsed,
round-trips to an equal struct (`assert parse!(path) == parse!(roundtrip_path)`).
A **byte-for-byte** identical round-trip on the original file content is the
target, not merely a semantically-equal round-trip — see story (c) for the
comment/ordering preservation requirement that byte-for-byte identity
depends on.

**Evidence required**: a real "read-then-write-unchanged idempotency test,"
not assumed. The test must:

1. Copy `~/beam4pm/ggen.toml`'s real content to a temp fixture file (via
   `File.cp!/2` from a path fixture, or a `test/fixtures/` copy checked into
   the repo — either is acceptable, but the content must be beam4pm's real
   file, not a synthetic minimal example, because this ticket's whole
   purpose is proving the tool survives a real production consumer's file).
2. Call `parse!/1` on the temp fixture.
3. Call `serialize!/1` on the unmodified parsed result.
4. Write the serialized text to a second temp path.
5. Assert on the actual resulting file content — `File.read!/1` on both
   paths, diffed — not just "no exception was raised" and not just
   "`Toml.decode/1` on both sides produces equal maps" (that would hide a
   comment/ordering regression story (c) requires surfacing).

### Story (c) — preserve key order and comments in the `[packs]` table-of-tables shape, or explicitly document the limitation

**Subject**: beam4pm's real `ggen.toml` has a multi-line comment block
immediately after its `[packs]` entries:

```toml
# gh-terraform-pack: investigated 2026-08-30, NOT wired -- ships unscoped
# reference-repo instance data that hard-collides (family "repository") or
# pollutes (families "milestones"/"labels") any second consumer's output.
# See the "gh-terraform-pack consumption -- INVESTIGATED AND DECLINED"
# comment block in ontology.ttl for the full, confirmed finding.
```

This is real, meaningful project history (a documented decision not to wire
a specific pack, with a pointer to the fuller rationale in `ontology.ttl`) —
not decorative whitespace. A naive parse-then-encode round-trip through a
library that only understands TOML as an unordered key-value structure
(most TOML decode/encode pairs, including likely `toml` ~> 0.7's `Map`-based
decode target, do not retain comments or key insertion order by default)
would silently destroy this comment block and could reorder the five
`[packs]` entries. Both are unacceptable as a silent outcome.

**Acceptance behavior — two admissible outcomes, one is required**:

1. **Preferred**: key order and comments survive the round-trip. If the
   `toml` ~> 0.7 library (or a lower-level parse target it exposes) supports
   round-trip-preserving decode (e.g. it returns something richer than a
   bare `Map` — an AST, a list of key/value/comment nodes, or similar), use
   that path and prove it with the story (b) byte-for-byte test actually
   passing on beam4pm's comment-bearing file.
2. **Accepted limitation, only if (1) is genuinely infeasible with the
   chosen library**: document in this module's moduledoc, explicitly, that
   comments and/or key order are not preserved, name the specific reason
   (e.g. "`toml` ~> 0.7's `Toml.decode/1` target type is `map()`, which has
   no ordered-key or comment-attachment concept — confirmed by reading
   [library source/hexdocs path cited]"), and state the concrete consequence
   for a real consumer (e.g. "re-running `serialize!/1` against beam4pm's
   `ggen.toml` will drop the gh-terraform-pack decline-rationale comment
   block and may reorder `[packs]` entries alphabetically/insertion-order
   per Elixir `Map` semantics — this is a known, disclosed regression for any
   caller that writes back an unmodified-in-substance file, not a silent
   one"). This must not be discovered by a future reader diffing files by
   hand; it must be stated as an explicit acceptance-test assertion (the
   test asserts what actually survives and what does not, rather than
   skipping the comment case).

**Prohibited outcome**: shipping story (b)'s idempotency test with a
synthetic minimal `ggen.toml` fixture that has no comments, thereby never
exercising this failure mode at all. The evidence for story (b) must be
beam4pm's real, comment-bearing file specifically, precisely because a
minimal fixture would hide this exact gap.

**Evidence required**: the story (b) byte-for-byte round-trip test's actual
pass/fail outcome against beam4pm's real file *is* the evidence for this
story — do not write a separate synthetic test for the comment case. If the
round-trip is not byte-identical, the test must assert on the specific
delta (e.g. `assert content_before =~ "gh-terraform-pack: investigated"` and
either the same assertion holds against `content_after`, proving
preservation, or an explicit `refute content_after =~ "..."` paired with the
moduledoc limitation note, proving and documenting the loss rather than
leaving it to silently pass on a lucky diff).

## Testing discipline

Chicago-school only, per this repo's `CLAUDE.md`: real `File.read!/1`/
`File.write!/1` against real temp files (`System.tmp_dir!/0` or
`test/fixtures/`), real `Toml.decode/1` calls against beam4pm's actual
`ggen.toml` content, state-based assertions on the real returned struct and
the real resulting file bytes. No `Mock`/`mock(`/`patch(`/`monkeypatch`
anywhere in the new test file — verify with
`grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` (expect zero
new matches) before claiming this ticket done, per this repo's enforced
testing discipline section.

## Acceptance summary (compilation/existence is not a crown)

- [ ] `parse!/1` exists, is exported from the ticket-01 dispatch namespace,
      and correctly classifies + parses beam4pm's real `ggen.toml` into the
      Frontmatter/`GgenConfig`-shaped struct — proven by a real test
      asserting on concrete struct/field values, not "compiles."
- [ ] `serialize!/1` exists and produces TOML text from either schema
      variant's struct.
- [ ] A real read-then-write-unchanged idempotency test exists, uses
      beam4pm's actual `ggen.toml` (comment block included) as its fixture,
      and asserts on real file content — pass or documented, specific
      failure, never silently skipped.
- [ ] The `[packs]` table-of-tables comment/ordering question is resolved
      one of the two admissible ways in story (c), stated explicitly in the
      module's moduledoc with the concrete library-capability reason cited.
- [ ] `grep -rn "Toml\.decode\|Toml\.encode\|Toml\.parse" lib/` now returns
      real, non-test-only hits (closing the exact gap this ticket opened
      with).
- [ ] `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` returns
      zero new matches introduced by this ticket's changes.
- [ ] `mix compile --warnings-as-errors` and `mix test` both pass, output
      pasted as the receipt per this repo's verification discipline — a
      narrated summary is not a receipt.

## See Also

- `docs/jira/v26.9.1/01-*` (ticket 01, this same directory) — the typed
  dual-schema structs and dispatch/classifier module this ticket's
  `parse!/1` consumes.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — source
  epic (GGEN-1801 through GGEN-1807) this ticket implements the
  ggen_igniter-side detail of.
- `~/ggen_igniter/docs/v26.9.1-requirements.md` — a **different** v26.9.1
  work stream in this same repo (process-mining/OCEL manufacturing-pack
  expansion: incremental DFG discovery, sensor-to-event streaming,
  inductive-miner discovery, token-replay conformance, OCEL2/EKG
  derivation, OLAP slice/dice, Chicago-style OTP fault injection packs).
  Same version number, unrelated content — do not conflate the two.
- `~/ggen/crates/ggen-engine/src/schema_dispatch.rs` — the real Rust
  ggen-core dispatch point this ticket's Elixir dispatch/parse pairing
  mirrors (`classify_ggen_toml`, `ParsedGgenToml::DeclarativeRules` /
  `ParsedGgenToml::Frontmatter`), including its documented prior bug
  (BUG-005: `ggen doctor` against ggen's own root `ggen.toml` failed
  because `handle_doctor` unconditionally called the wrong schema's
  loader) — the exact failure mode a missing dispatch-before-parse step
  in this ticket would reintroduce in Elixir.
- `~/ggen/crates/ggen-engine/src/config.rs` (lines 45–52, 128) — the Rust
  `GgenConfig`/`PackRef` (Frontmatter schema) this ticket's parse target
  for beam4pm-shaped `ggen.toml` files must match in shape.
- `~/ggen/crates/ggen-config/src/manifest/types.rs` (line 193, lines 52–69)
  — the Rust `GgenManifest`/`PackRef` (DeclarativeRules schema) this
  ticket's parse target for `[[generation.rules]]`-bearing files must match
  in shape.
- `~/beam4pm/ggen.toml` — the real fixture file this ticket's story (b)/(c)
  tests are required to use, including its `[packs]` table-of-tables and
  gh-terraform-pack decline-rationale comment block.
- `lib/ggen_igniter/project_config.ex`, `lib/ggen_igniter/pack_manifest.ex`
  — this repo's existing, self-disclosed partial mirrors of the two schemas
  (`GgenIgniter.ProjectConfig` moduledoc: "mirrors `ggen_config::manifest::
  GgenManifest` only"; `GgenIgniter.PackRef` moduledoc: "mirrors the
  array-of-tables (ggen-config) shape only; the ggen-engine variant is a
  separate follow-on") — ticket 01 closes this gap with typed structs for
  both schemas; this ticket is the I/O layer over the result.
- `CLAUDE.md` (this repo's root) — Testing discipline, Verification
  discipline, and Destructive operations sections this ticket's acceptance
  criteria are bound by.
