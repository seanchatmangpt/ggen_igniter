# Fortune5-Ready Bundle Installer (ggen_igniter side) v26.9.1 — Overview

Index ticket for this directory's six-file ticket set: the `ggen_igniter`-side
implementation of the fortune5-ready bundle installer, the `ggen_igniter` slice of
the source epic at `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`
(stories GGEN-1801 through GGEN-1807). It gives a consumer project (beam4pm first)
a single `mix ggen_igniter.fortune5_ready` task that classifies the consumer's real
`ggen.toml` schema, parses it, merges in the fortune5 pack bundle with dedup, writes
it back idempotently, shells out to a real `ggen sync run`, and verifies the newly
added packs' own gates — all with Chicago-school real-collaborator tests against
beam4pm's actual `ggen.toml` as the primary fixture throughout.

**This is a distinct work stream from `~/ggen_igniter/docs/v26.9.1-requirements.md`**,
which is a *different*, pre-existing v26.9.1 release in this same repo: a
process-mining/OCEL manufacturing-pack expansion (incremental DFG discovery,
sensor-to-event streaming, inductive-miner discovery, token-replay conformance,
OCEL2/EKG derivation, OLAP slice/dice, Chicago-style OTP fault-injection packs).
The two share the `v26.9.1` version string only by coincidence of timing — no git
tag yet exists to disambiguate release boundaries (that document's own Open
Question 1) — and have zero functional or code-path overlap. Every ticket in this
directory states this distinction in its own scope note; do not conflate the two
when reading either.

All five implementation tickets (01–05) are **DONE**, each with real,
cited command output (`mix compile --warnings-as-errors`, scoped `mix test`
runs, and `grep` sweeps confirming zero real mock usage) — none merged to
`main`. Each ticket's branch is stacked on the previous stage's real branch,
not on `main`: `story/GI-02-ggen-toml-toml-io` is based on GI-01's
`story/GI-01-schema-dispatch-alignment` (commit `af13e0a`);
`story/GI-03-bundle-manifest-and-merge` is based on GI-02's commit `ff58f6c`;
`story/GI-04-sync-shellout-and-verify` is based on GI-03's commit `eae7397`;
and `story/GI-05-fortune5-ready-mix-task` is based on GI-04's commit
`c542eea`. A subsequent parity-validation pass (documented in
[PARITY-VALIDATION.md](PARITY-VALIDATION.md), committed as `ebf507c` on the
GI-05 branch) confirmed real behavioral agreement with ggen core: a real
`ggen` 26.8.28 binary was run against a read-only scratch copy of beam4pm's
actual `ggen.toml`, both for schema classification and for a
merge-and-serialize-back round trip through `GgenIgniter.Bundle.merge/2` and
`GgenIgniter.GgenToml.IO.serialize!/1` — with the one real rejection
observed (`fortune5-deployment-blocks-pack`, `FM-PACK-005`, zero templates)
traced to a pre-existing, already-filed upstream pack defect unrelated to
`ggen_igniter`'s own code.

## Tickets

1. [01-SCHEMA-DISPATCH-ALIGNMENT](01-SCHEMA-DISPATCH-ALIGNMENT.md) — **DONE.** build
   `GgenIgniter.SchemaDispatch`, the single shared classifier/dispatch point
   mirroring ggen core's `schema_dispatch.rs` + `classify_ggen_toml` (closing
   BUG-005's ad-hoc-guessing anti-pattern in Elixir before it can recur), and add
   `GgenIgniter.FrontmatterConfig`/`FrontmatterPackRef` as the missing sibling
   struct family for the `Frontmatter`/`GgenConfig` table-of-tables schema beam4pm's
   real `ggen.toml` actually uses.
2. [02-GGEN-TOML-TOML-IO](02-GGEN-TOML-TOML-IO.md) — **DONE.** real `Toml.decode`-backed
   `parse!/1` into ticket 01's typed dispatch result, an idempotent `serialize!/1`
   back to TOML text, and an explicit, evidence-backed resolution (preserve, or
   named accepted limitation) of comment/key-order survival for beam4pm's
   `[packs]` table-of-tables, including its real `gh-terraform-pack` decline-
   rationale comment block.
3. [03-BUNDLE-MANIFEST-AND-MERGE](03-BUNDLE-MANIFEST-AND-MERGE.md) — **DONE.** the
   `priv/bundles/fortune5_ready.json`-backed, name-keyed bundle manifest (v1:
   `fortune5-architecture` + `fortune5-deployment-blocks` only) and
   `GgenIgniter.Bundle.merge/2`, a name-keyed (never path-keyed) dedup merge
   proven idempotent and partial-install-aware against beam4pm's real 5-pack
   `ggen.toml`.
4. [04-SYNC-SHELLOUT-AND-VERIFY](04-SYNC-SHELLOUT-AND-VERIFY.md) — **DONE.** a real
   `System.cmd/3` shellout to `ggen sync run` (GGEN-1805, modeled on
   `ggen_igniter.doctor.ex`'s three existing subprocess-check patterns) plus
   post-sync per-gate SPARQL verification (GGEN-1806) that reports each newly
   added pack's gate results individually rather than one aggregate boolean.
5. [05-FORTUNE5-READY-MIX-TASK-AND-E2E-TEST](05-FORTUNE5-READY-MIX-TASK-AND-E2E-TEST.md)
   — **DONE.** GGEN-1807: the assembled `mix ggen_igniter.fortune5_ready` `Igniter.Mix.Task`
   wiring tickets 01–04 into one pipeline (dispatch → parse → merge → serialize →
   sync → verify gates → report), modeled on `ggen_igniter.install.ex`'s real
   structure, proven end-to-end against a real scratch fixture project (both
   schema shapes, plus a negative/fail-loud case) — not against beam4pm itself.
6. [06-KNOWN-LIMITATIONS-AND-NON-GOALS](06-KNOWN-LIMITATIONS-AND-NON-GOALS.md) — a
   scope-boundary document (not a story): no general ggen-core pack-dependency
   algebra, no resurrection of the dead `PackComposer`/`DependencyGraph`
   subsystem, no fix to the two non-portable fortune5 packs, no execution against
   beam4pm itself (and a restatement of that trial's hard blocking prerequisite —
   `beam4pm/scripts/gate_m2_check.sh`'s live destructive delete-before-regenerate-
   succeeds defect), and no claim of business/certification "Fortune 5 readiness."
7. [PARITY-VALIDATION](PARITY-VALIDATION.md) — **DONE** (copied here from the
   unmerged branch `story/GI-05-fortune5-ready-mix-task`, commit `ebf507c`;
   that branch copy is canonical). Real `ggen` 26.8.28 binary run against a
   read-only scratch copy of beam4pm's actual `ggen.toml`, confirming schema-
   classification agreement (`:frontmatter`, zero config error on both sides)
   and confirming the merge/serialize-back output of tickets 01–03's real
   code is accepted by real `ggen sync run --dry-run` for every pack whose
   own `templates/` dir is non-empty. The one rejection observed
   (`fortune5-deployment-blocks-pack`, `FM-PACK-005`) is a pre-existing,
   already-filed upstream pack defect, not a `ggen_igniter` defect.

## Definition of done for the set

Synthesized across all six tickets' own acceptance criteria:

- **Ticket 01**: `GgenIgniter.SchemaDispatch` correctly classifies both beam4pm's
  real `ggen.toml` (`:frontmatter`) and a synthetic `DeclarativeRules` fixture
  (`:declarative_rules`), and fails closed (typed refusal, never a crash or a
  silent wrong-schema guess) on an ambiguous/malformed fixture. The new
  `FrontmatterConfig`/`FrontmatterPackRef` structs parse beam4pm's real `ggen.toml`
  into exactly 5 correctly-shaped pack entries and correctly handle the `Git`
  variant. `ProjectConfig`/`PackRef`'s moduledocs are updated to state the
  `DeclarativeRules`-only scoping as resolved, not an open gap, with no struct
  shape change. All new tests are real `Toml.decode` over real fixtures with
  state-based assertions; `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib
  native` returns zero new matches; `mix compile --warnings-as-errors` and
  `mix test` both pass with real output pasted as evidence.
- **Ticket 02**: `parse!/1` classifies-and-parses beam4pm's real `ggen.toml` into
  the `Frontmatter` struct with correct field values (not an untyped map).
  `serialize!/1` round-trips; a real read-then-write-unchanged idempotency test
  runs against beam4pm's actual comment-bearing file and asserts on real file
  bytes. The `[packs]` comment/key-order question is resolved one of the two
  admissible ways (preserved, proven byte-for-byte; or an accepted limitation
  named in the moduledoc with the specific library-capability reason cited and a
  test asserting exactly what survives and what doesn't) — never silently
  discovered later. `grep -rn "Toml\.decode\|Toml\.encode\|Toml\.parse" lib/` now
  returns real non-test-only hits.
- **Ticket 03**: the bundle manifest names exactly the two portable packs (proven
  by a test asserting exactly 2 entries, catching any premature addition of the
  two blocked packs); `Bundle.merge/2` dedups on pack name (never path), proven
  by four real tests against beam4pm's actual `ggen.toml` — full merge (5+2=7,
  no dupes), idempotent re-merge, partial-install dedup, and a name-vs-path
  dedup-key proof.
- **Ticket 04**: `System.cmd/3` shellout to `ggen sync run` returns a typed
  `{:ok, output}` / `{:error, {exit_code, output}}` result (real invocation and
  real nonzero-exit capture both proven against real fixtures, with a named
  visible skip — never a mock — when no real `ggen` binary is on `PATH`); the
  shellout never runs if the upstream serialize-back step failed. Post-sync gate
  verification reports per-gate pass/fail (never one aggregate boolean) and
  refuses with a typed error naming the specific failed gate.
- **Ticket 05**: `mix ggen_igniter.fortune5_ready` exists as a real
  `Igniter.Mix.Task` calling tickets 01–04's named modules (not inlined
  reimplementations), proven by grep. A Chicago-style ExUnit end-to-end test
  exercises the full assembled pipeline against a real scratch fixture project in
  both schema shapes plus a fail-loud negative case, asserting only on real
  post-run disk state (`ggen.toml` content, generated files) — never on
  interaction/call-count. `mix ggen_igniter.fortune5_ready --help` runs for real
  and exits zero. `grep -rn "Mock\|mock(\|patch(\|monkeypatch"` over the new test
  file returns zero matches (the one named exception candidate — an unavailable
  real `ggen` binary — is a visible skip, not a mock).
- **Ticket 06**: its five non-goals hold as stated scope boundaries for the whole
  set — no pack-dependency algebra, no `PackComposer` resurrection, no fix to the
  two non-portable fortune5 packs, no beam4pm execution (and `gate_m2_check.sh`'s
  destructive defect stays a named, restated hard blocker for any future beam4pm
  trial), and no claim beyond generated scaffold/documentation/contract surfaces.
- **Across the set**: every acceptance bullet in every ticket is bound to Chicago-
  school testing discipline (`~/.claude/rules/testing-chicago-style.md`) — real
  collaborators, state-based assertions, zero `Mock`/`mock(`/`patch(`/`monkeypatch`
  verified by a fresh `grep`, real command output pasted as evidence rather than a
  narrated summary — and to the epic/story/acceptance format convention below.
  Compilation or file existence alone is never treated as a closed story.

## See Also

- `~/ggen/docs/jira/v26.9.1/00-OVERVIEW.md` — the source epic's own index (tickets
  01–06 there: pack-composition-gap findings, the two fortune5 pack portability
  fixes, architecture/deployment-blocks re-verification, the centerpiece
  `05-FORTUNE5-READY-BUNDLE-INSTALLER.md` epic this directory's ticket set is the
  `ggen_igniter`-side implementation detail of, and the downstream beam4pm-trial
  ticket). Read first for full origin context and non-goals.
- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the **other**, unrelated
  v26.9.1 work stream in this same repo (process-mining/OCEL manufacturing-pack
  expansion release). Shares the version string only; no functional overlap with
  this directory's bundle-installer stream — do not conflate the two.
- `~/beam4pm/docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the
  epic/story/acceptance-bullet format convention every ticket in this directory
  follows (exact subject, acceptance behavior, evidence; compilation or file
  existence alone is not a crown).
