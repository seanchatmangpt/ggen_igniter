## Status update (round 3 — bundle-serializer comment/order-preservation fix)

**MERGED** — `story/GI-07-bundle-serialize-preserve-comments`, commit `a89fcf1`, now
merged to `ggen_igniter` `main` at `c7d3d64`.

This story fixes `GgenIgniter.Bundle`'s merge-then-serialize path: the merge logic
itself (§2 below, GGEN-1803) was already correct and unchanged, but the write-back
step that turns a merged config back into `ggen.toml` text previously went through a
full lossy re-render (`GgenIgniter.GgenToml.IO.serialize!/1`), which drops comments
and can reorder existing `[packs]` entries. GI-07 adds a new
`GgenIgniter.GgenToml.IO.splice_added_packs!/2` — a **textual splice over the raw
original file text**, not a re-render — that appends only the newly-merged pack
entries to the end of the existing `[packs]` table while leaving every byte of the
rest of the file (comments, ordering, whitespace) untouched.

- 2 new tests, 11/11 total passing for this module's test file.
- Addition-only diff proven for real against beam4pm's actual `ggen.toml`
  (`~/beam4pm/ggen.toml`) — the real fixture already used by this ticket's §2.2 merge
  tests.
- The `gh-terraform-pack` decline comment (an existing inline comment in a real
  consumer's `ggen.toml` explaining why that pack was deliberately not adopted)
  survives byte-for-byte through `splice_added_packs!/2`.
- Non-alphabetical original pack order is preserved — the splice never resorts or
  reformats existing entries, only appends new ones.

**Disclosed remaining gap, not closed by this story**: the `fortune5_ready` mix
task's own `serialize_step` (`lib/mix/tasks/ggen_igniter.fortune5_ready.ex:179-185`)
still calls the old lossy `serialize!/1` on a live run — it has not yet been rewired
to call `splice_added_packs!/2`. Wiring that is a natural GI-08 follow-on, not
performed as part of GI-07. See
`~/ggen_igniter/docs/jira/v26.9.1/05-FORTUNE5-READY-MIX-TASK-AND-E2E-TEST.md`'s
Status section for the cross-referenced note on this same gap from the mix-task
side.

## Status (updated after real implementation)

**DONE** — per gi03 evidence in `/tmp/full_results.json`.

- Branch: `story/GI-03-bundle-manifest-and-merge` (based on `story/GI-02-ggen-toml-toml-io` per instructions), worktree `/private/tmp/GI-03-worktree`, commit `eae7397` (committed only, not merged/pushed).
- **Stage1-outcome decision on GM-02/GM-03 (governs which packs made it into the v1 bundle manifest)**: GM-02 came back DONE but its fix lives only in an unmerged local worktree branch (`~/ggen-marketplace/.worktrees/GM-02-...`, commit `6c2170848`, never merged to ggen-marketplace `main`, never pushed) — not part of any consumer-visible ggen-marketplace ref. GM-03 came back PARTIAL (6/9 suites BUILD_BROKEN on an unrelated pre-existing CLI-argument-drift defect). Neither fix is actually landed/available to a real consumer yet, so **the ticket's own default v1-scope decision stands unchanged**: the bundle manifest ships **exactly the two packs originally scoped** — `fortune5-architecture` and `fortune5-deployment-blocks` — and continues to **exclude** `fortune5-required-capabilities` and `fortune5-testing-bblock` (both still gated on their upstream portability fixes actually landing merged, which they have not). This reasoning is stated in `priv/bundles/fortune5_ready.json`'s exclusion and in the commit message.
- GGEN-1801 (manifest): `priv/bundles/fortune5_ready.json` — name-keyed `"bundles"` map (not a hardcoded module attribute), `"fortune5_ready"` bundle with `manifest_version "1.0.0"` and exactly 2 packs (`fortune5-architecture`, `fortune5-deployment-blocks`), each with `name` + `path_hint` per the ticket's exact §1.3 shape. `lib/ggen_igniter/bundle.ex`: `GgenIgniter.Bundle.load!/1` (real `Jason.decode!/1`, atom-keyed `%GgenIgniter.Bundle.Pack{}` structs, not raw string-keyed maps) + `load_packs!/2`. Moduledoc restates both resolved design decisions (§1.2 co-location, §1.3 name-keyed not domain-aware) near-verbatim, verified by a real test reading `Code.fetch_docs/1`'s actual moduledoc text.
- GGEN-1803 (merge): `GgenIgniter.Bundle.merge/2(%GgenIgniter.FrontmatterConfig{}, bundle_packs)` dedupes strictly by pack name (`MapSet` of existing `Map.keys(packs)`), never path, returning only the entries to add.
- Tests: `test/ggen_igniter_bundle_test.exs`, real fixtures in `test/fixtures/bundle/` (`beam4pm_ggen.toml` = verbatim copy of beam4pm's real 5 packs; `beam4pm_partial_install.toml` = same 5 + `fortune5-architecture` already wired; `path_collision_different_name.toml` = a renamed entry whose path collides with `fortune5-architecture`'s `path_hint`), all parsed via the real `GgenIgniter.SchemaDispatch.load_raw/1` pipeline (tickets 01/02), never a hand-constructed struct. Test 1 (real merge against beam4pm's actual `ggen.toml`): exactly `{fortune5-architecture, fortune5-deployment-blocks}` to add, resulting 7-entry set has no dupes/collisions. Test 2 (idempotency): second merge fed from the first run's real output returns `[]`. Test 3 (partial-install dedup): exactly 1 new entry when `fortune5-architecture` is already wired. Test 4 (dedup key is name not path): a path collision under a different name still yields `fortune5-architecture` as new — proves dedup is name-keyed.
- Command output (real, from the run): `mix compile --warnings-as-errors` → clean, "Generated ggen_igniter app". `mix test test/ggen_igniter_bundle_test.exs` → **"9 tests, 0 failures"**. `grep -rn "Mock|mock(|patch(|monkeypatch" test/ggen_igniter_bundle_test.exs lib/ggen_igniter/bundle.ex` → one hit, a doc-comment sentence naming the discipline, zero real mock usage.
- **Disclosed caveat**: a full-repo `mix test` (background, log at `/tmp/gi03-mixtest.log`) was still running against this large repo's full 2500+-test suite (unrelated pre-existing suites) when this task's time budget was reached and was **not confirmed to completion**. Only the scoped run above (this ticket's own new test file, 9/0) is confirmed. Nothing in the new/touched files depends on the unrelated suites.
- Non-goals explicitly out of scope, not attempted: GGEN-1804 TOML write-back, GGEN-1805/1806 the installer mix task itself, GGEN-1802 wiring `SchemaDispatch` into other mix tasks, and re-running the live-regeneration re-test for the two gated-out packs once their upstream fixes actually land merged.

---

# Fortune5-ready bundle manifest and dedupe merge logic

## Scope note — two unrelated v26.9.1 work streams

This ticket set lives under `docs/jira/v26.9.1/` alongside
`docs/v26.9.1-requirements.md`, which is a **different** v26.9.1 work stream (a
process-mining/OCEL manufacturing-pack expansion — incremental DFG discovery,
sensor-to-event streaming, inductive-miner discovery, token-replay conformance,
OCEL2/EKG derivation, OLAP slice/dice, Chicago-style OTP fault-injection packs). The
version number collision is coincidental — both land under the same `v26.9.1` label
because no git tag yet exists to disambiguate release boundaries (see that
document's own Open Question 1). This ticket set is the **fortune5-ready bundle
installer** work stream instead: a separate epic tracked upstream at
`~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` (stories
GGEN-1801–GGEN-1807), of which this document is the `ggen_igniter`-side
implementation detail for GGEN-1801 (bundle manifest) and GGEN-1803 (dedupe merge).
Do not conflate the two work streams when reading this directory; see the
[See Also](#see-also) section for a cross-reference to both.

## 1. Bundle manifest (GGEN-1801)

### 1.1 What ships in v1

The fortune5-ready bundle names exactly two packs at launch, matching the source
epic's own scoping (GGEN-1801's acceptance criteria):

| Pack | Status this release |
|---|---|
| `fortune5-architecture-pack` | In bundle v1 — confirmed portable by GGEN-1801's live-generation re-test against a scratch consumer (source epic, not re-derived here) |
| `fortune5-deployment-blocks-pack` | In bundle v1 — same |
| `fortune5-required-capabilities-pack` | **Not** in bundle v1 — gated on its own portability fix (hardcoded `../../../../crates/ggen-marketplace` path, tracked elsewhere in this milestone) landing first |
| `fortune5-testing-bblock-pack` | **Not** in bundle v1 — gated on its own portability fix (`crates/ggen-cli`/`target/debug/ggen` self-detection) landing first |
| `fortune5-enterprise-architecture-pack` | Out of scope for this bundle — no portability audit has been run against it (source epic explicitly does not assume safe-by-omission) |

The manifest's own data structure carries a `version` field distinct from
`ggen_igniter`'s `mix.exs` version, and a bundle-name key rather than a hardcoded
single-bundle module attribute, so a second bundle (once one is actually proposed)
does not require a schema change — see §1.3.

The two currently-blocked packs join the manifest only in a follow-up release, once
their portability fixes are independently confirmed landed and this ticket's
GGEN-1801 live-regeneration re-test (against a scratch consumer, per the source
epic) is re-run against them specifically. This ticket does not implement that
re-test for the two blocked packs — it is out of scope until the upstream fixes
land.

### 1.2 Resolved: manifest location

**Decision: the manifest lives in `ggen_igniter` itself, at
`priv/bundles/fortune5_ready.json` (or equivalent Elixir data — see §1.3 for the
concrete shape), not alongside the packs in `ggen-marketplace`.**

Rationale (both real tradeoffs stated, one selected, not left open per the source
epic's own instruction not to resolve this silently):

- Co-locating with `ggen_igniter` means the bundle manifest and the installer task
  that reads it (`Mix.Tasks.GgenIgniter.Fortune5Ready`, out of scope for this
  ticket — see GGEN-1805/1806 in the source epic) always ship in lockstep. A
  manifest naming packs the installed `ggen_igniter` version doesn't yet know how
  to merge correctly (schema changes to `ProjectConfig`/`PackRef`, see ticket 01/02)
  cannot exist, because both live in the same release artifact.
- Co-locating with `ggen-marketplace` would let the manifest evolve at the pack
  corpus's own cadence (new fortune5-* packs added without a `ggen_igniter`
  release) but reintroduces exactly the vendoring-drift class of problem
  `beam4pm`'s own `vendor/ggen-marketplace` git submodule (pinned tags, not a live
  read) already exists specifically to manage. `ggen_igniter` has no equivalent
  vendoring mechanism today — bringing one in as a side effect of one bundle
  manifest is out of proportion to the problem this ticket solves.
- The selected shape (co-located, versioned independently of `mix.exs`) is the
  cheaper interim answer with the lower blast radius: if a second bundle or a
  pack-repo-side versioning need does arise, the manifest's own `version` field and
  name-keyed structure (§1.3) already accommodate it without a location change.

This decision is recorded here and restated in the manifest module's own moduledoc
when GGEN-1801's implementation lands (not left as tribal knowledge in this ticket
alone), per the source epic's acceptance requirement that both open design
questions be recorded in the manifest's own file documentation.

### 1.3 Resolved: bundle composition is name-keyed, not domain-aware yet

**Decision: bundle composition stays one-size-fits-all for v1 (a single
`"fortune5_ready"` bundle), but the manifest's own data shape is a name-keyed map
of bundles, not a single hardcoded module attribute — so a second, differently-scoped
bundle (e.g. a hypothetical `"process_mining_ready"` bundle naming a different pack
set) is a data addition, not a schema change, if and when one is actually proposed.**

Rationale: the source epic explicitly asks that the manifest's structure "not
foreclose [a second bundle] by accident (e.g. hardcoding a single bundle name as a
module attribute rather than a name-keyed map)." No second bundle is scoped or
justified by this release — inventing domain-awareness now would be speculative
generality with no real second consumer. The interim answer is: single bundle only,
no domain-awareness yet; manifest lives in `ggen_igniter` for v1 (§1.2); revisit
if a second bundle or pack-repo-side versioning need arises.

Concrete manifest shape (`priv/bundles/fortune5_ready.json`, loaded by a real
`GgenIgniter.Bundle.load!/1`-shaped function — implementation of the loader itself
is part of this ticket, not deferred):

```json
{
  "bundles": {
    "fortune5_ready": {
      "manifest_version": "1.0.0",
      "packs": [
        {
          "name": "fortune5-architecture",
          "path_hint": "vendor/ggen-marketplace/packs/fortune5-architecture-pack"
        },
        {
          "name": "fortune5-deployment-blocks",
          "path_hint": "vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack"
        }
      ]
    }
  }
}
```

`name` is the dedupe key used by the merge logic in §2 — it is the value expected
to match a consumer's existing `ggen.toml` `[packs]` key (beam4pm's own
`beam4pm-process-model`, `beam4pm-pro-infra`, etc. are examples of this same
naming convention already on disk). `path_hint` is the default relative path the
installer proposes when wiring a new entry into a consumer's `ggen.toml`; it is a
hint, not an authoritative value — GGEN-1804's TOML write-back is free to adjust it
per-consumer (e.g. a consumer whose `vendor/ggen-marketplace` lives at a different
relative depth), a decision explicitly out of scope for this ticket, which owns
only manifest definition and merge (not write-back).

### 1.4 Acceptance — manifest (GGEN-1801, this repo's slice)

- A real `priv/bundles/fortune5_ready.json` (or equivalent versioned Elixir data
  structure — module attribute is explicitly rejected per §1.3, so this must be a
  name-keyed map, JSON fixture or otherwise) exists on disk, naming exactly
  `fortune5-architecture` and `fortune5-deployment-blocks`, proven by a real test
  that loads the file and asserts on its parsed `packs` list — not by asserting the
  file exists.
- The loader function (`GgenIgniter.Bundle.load!/1` or equivalent) returns a typed
  struct/map, not a raw `Map` decoded from JSON with string keys left unconverted,
  proven by a real test asserting on atom-keyed or struct field access against the
  loaded result.
- Both open design questions from the source epic (manifest location, domain-aware
  composition) are recorded in the bundle module's own moduledoc, restating the
  decisions in §1.2 and §1.3 verbatim or near-verbatim — proven by reading the
  actual moduledoc text once GGEN-1801 lands, not merely citing this ticket.
- `fortune5-required-capabilities` and `fortune5-testing-bblock` are **not**
  present in the v1 manifest — proven by a real test asserting the loaded bundle's
  `packs` list has exactly 2 entries with the exact two names above, so a future
  accidental addition before the upstream portability fixes land is caught by a
  failing test, not a silent regression.

## 2. Merge-in logic with dedupe (GGEN-1803)

### 2.1 Function contract

`GgenIgniter.Bundle.merge(project_config, bundle)` takes a loaded
`%GgenIgniter.ProjectConfig{}` (populated by ticket 01/02's real TOML parse — see
`~/ggen_igniter/lib/ggen_igniter/project_config.ex:171-229`,
`~/ggen_igniter/lib/ggen_igniter/pack_manifest.ex:86-111` for the existing struct
shapes this ticket populates against) and a loaded bundle (§1.3's shape), and
returns the list of pack entries that need to be **added** — the entries already
present are never returned, never duplicated, never mutated.

Dedup key: **pack name/alias exactly as it appears in `ggen.toml` today** (e.g.
beam4pm's `beam4pm-process-model`), not path. The source epic explicitly requires
this (GGEN-1803 acceptance: "dedup matches on pack name/alias exactly as it appears
in `ggen.toml` today ... not on path, since two differently-named entries could
legitimately point at the same path in principle and this story does not assume
they can't"). This ticket's implementation must not silently switch to a path-based
dedup key for convenience — a path-based key would incorrectly treat two
legitimately-differently-named entries pointing at the same path as a conflict,
which is not this story's job to adjudicate.

### 2.2 Real fixture: beam4pm's actual `ggen.toml`

beam4pm's real, currently-wired `[packs]` table-of-tables entries (verified live
against `~/beam4pm/ggen.toml`, cited in the source epic and independently
confirmed here):

```toml
[packs]
beam4pm-process-model = { path = "vendor/ggen-marketplace/packs/beam4pm-process-model-pack" }
beam4pm-pro-infra = { path = "vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack" }
github-actions-pack = { path = "vendor/ggen-marketplace/packs/github-actions-pack" }
beam4pm-ai-contracts = { path = "vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack" }
beam4pm-pro-entitlement = { path = "vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack" }
```

This is the table-of-tables `[packs]` shape (`GgenConfig`/`Frontmatter` schema —
see §3 below), **not** the array-of-tables `[[packs]]` shape — this is the real,
first intended consumer for the fortune5-ready bundle installer, so the merge test
fixture in this ticket must be built against this exact real shape, not a
synthetic array-of-tables stand-in.

### 2.3 Acceptance — merge (GGEN-1803)

Chicago-school discipline throughout, per this repo's own `CLAUDE.md` ("Testing
discipline (enforced, not just preferred)" — real collaborators, state-based
assertions, no `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in `test`, `lib`, or
`native`, verified with `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib
native` expecting zero matches): the fixture below is a real file read from disk
via ticket 01/02's real TOML parser, never a hand-constructed struct standing in
for a parse the test never actually exercises.

- **Test 1 — real merge against beam4pm's actual `ggen.toml`.** Copy
  `~/beam4pm/ggen.toml`'s real content into a test fixture, parse it for real via
  ticket 01/02's `load/1`, merge it against the v1 bundle manifest (§1.3), and
  assert the resulting pack set is **exactly** the original 5 beam4pm entries
  (`beam4pm-process-model`, `beam4pm-pro-infra`, `github-actions-pack`,
  `beam4pm-ai-contracts`, `beam4pm-pro-entitlement`) plus the 2 new
  fortune5-* entries (`fortune5-architecture`, `fortune5-deployment-blocks`) — 7
  entries total, proven by inspecting the actual returned list's names, not by
  asserting a count alone. No duplicates (each name appears exactly once), no path
  collisions (the two new entries' `path_hint` values do not match any of the 5
  existing entries' `path` values, proven by a real string comparison, not
  assumed).
- **Test 2 — idempotency across repeated merges.** Run the merge described in Test
  1 twice in sequence, feeding the second run's input from the **first run's real
  output** (not a fresh copy of the original fixture) — i.e. the test proves that
  merging an already-fortune5-wired `ggen.toml` against the same bundle a second
  time is a true no-op: the second run's resulting pack set is byte-for-byte /
  field-for-field identical to the first run's, proven by a real equality
  assertion on the two returned structures, not merely asserting the second run
  "didn't error."
- **Test 3 — partial-install dedup.** Construct a fixture representing a partial
  prior install (beam4pm's 5 real entries plus exactly one of the two bundle packs
  already wired, e.g. `fortune5-architecture` present, `fortune5-deployment-blocks`
  absent), run the merge, and assert the result contains **exactly one** new
  entry (`fortune5-deployment-blocks`) — not two, not zero, not an error. This
  directly covers the source epic's GGEN-1803 second acceptance bullet.
- **Test 4 — dedup key is name, not path.** Construct a fixture with an existing
  entry whose `path` happens to collide with a bundle pack's `path_hint` but whose
  `name` differs from the bundle pack's `name` (a legitimately-differently-named
  entry pointing at the same underlying pack directory, per §2.1's stated
  assumption) — assert the merge still adds the bundle pack as a new entry rather
  than treating the path collision as a dedup match, proving the dedup key really
  is name/alias and not silently path.

## 3. Interaction with the resolved schema-dispatch finding

This ticket's merge logic operates on the **already-parsed**
`%GgenIgniter.ProjectConfig{}` produced by ticket 01/02, so it does not itself
re-implement schema classification — but it depends on ticket 01/02 having
correctly classified beam4pm's `ggen.toml` as the **`Frontmatter`/`GgenConfig`**
schema (table-of-tables `[packs]`), not `DeclarativeRules`/`GgenManifest`
(array-of-tables `[[packs]]`), per the now-resolved schema-dispatch finding:

- ggen core's `~/ggen/crates/ggen-engine/src/schema_dispatch.rs` is the single
  shared dispatch point every real call site goes through, classifying via
  `ggen_config::classify_ggen_toml` into either `ParsedGgenToml::DeclarativeRules`
  (`ggen_config::manifest::GgenManifest`, `~/ggen/crates/ggen-config/src/manifest/
  types.rs:193`, `packs: Vec<PackRef>`, used when `[[generation.rules]]` is
  non-empty) or `ParsedGgenToml::Frontmatter` (`crate::config::GgenConfig`,
  `~/ggen/crates/ggen-engine/src/config.rs:45-52`, `packs:
  BTreeMap<String, PackRef>`, used when `[[generation.rules]]` is empty).
- `~/beam4pm/ggen.toml` has `[packs]` as name-keyed table-of-tables entries and no
  `[[generation.rules]]` section — it classifies as `Frontmatter`/`GgenConfig`, not
  `DeclarativeRules`/`GgenManifest`. This is verified live, not assumed.
- `GgenIgniter.ProjectConfig`/`GgenIgniter.PackRef`'s own moduledocs (confirmed by
  direct read) already self-disclose this exact gap: `project_config.ex`'s
  moduledoc states it "mirrors `ggen_config::manifest::GgenManifest` only";
  `pack_manifest.ex`'s `GgenIgniter.PackRef` moduledoc states it "mirrors the
  array-of-tables (ggen-config) shape only; the ggen-engine variant is a separate
  follow-on." Both were written as known, disclosed gaps, not silently wrong code.

**This is the firm, resolved requirement for ticket 01/02 (not this ticket's own
scope to implement, but a hard dependency this ticket's fixtures assume is true):
`ggen_igniter` is not used yet by any production consumer, so there is no
backward-compatibility cost to fixing this properly.** The requirement is a real
Elixir equivalent of ggen core's `classify_ggen_toml` + `schema_dispatch::load`
pattern — one shared classifier function, one dispatch point, both schemas as
concrete typed structs — with `GgenConfig`/`Frontmatter`/table-of-tables treated as
the schema exercised **first and by default** in this bundle-installer work,
since that is what real consumers like beam4pm actually use.
`GgenManifest`/`DeclarativeRules` stays supported (real projects may use it) but is
not the assumed-default path. This ticket's Test 1–4 fixtures (§2.2, §2.3) are
built against the `Frontmatter`/`GgenConfig` table-of-tables shape specifically,
matching this default; a regression fixture exercising the array-of-tables
`[[packs]]` shape belongs to ticket 01/02's own acceptance criteria, not
duplicated here.

## See Also

- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the **other**, unrelated v26.9.1
  work stream sharing this version label (process-mining/OCEL manufacturing-pack
  expansion) — see the [Scope note](#scope-note--two-unrelated-v26.9.1-work-streams)
  above; not to be conflated with this bundle-installer work stream.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — the source
  epic (GGEN-1800 through GGEN-1807) this ticket implements the `ggen_igniter`-side
  slice of (GGEN-1801 manifest, GGEN-1803 merge); read it first for the full
  origin context, non-goals, and the six other stories (TOML parse, TOML
  write-back, sync shellout, gate verification, end-to-end fixture test) this
  ticket does not cover.
- `~/beam4pm/docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the
  epic/story/acceptance-bullet format this document follows (exact subject,
  acceptance behavior, evidence — compilation or file existence alone is not a
  crown).
- `~/ggen_igniter/CLAUDE.md` — this repo's real conventions: the
  `Ontology.load!/1 -> Engine.run/2 -> Render.render/2 -> Actuate.write_file!/3`
  pipeline shape, the reconciliation manifest, and the Chicago-school testing
  discipline this ticket's acceptance bullets are written against.
- `~/ggen_igniter/lib/ggen_igniter/project_config.ex`,
  `~/ggen_igniter/lib/ggen_igniter/pack_manifest.ex` — the existing
  `ProjectConfig`/`PackRef` structs this ticket's merge logic consumes, and whose
  moduledocs already self-disclose the schema-mismatch gap resolved in §3.
