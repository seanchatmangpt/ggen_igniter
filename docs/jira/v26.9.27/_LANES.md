# _LANES.md — epoch-law write wave, 2026-09-27 (session: ggen_igniter @ 5ac166b)

Task: encode the v26.10.1 CalVer epoch boundary as an executable manufacturing law
(plan approved this session). Eight write lanes, disjoint file ownership, one pinned
contract. Lanes never run git state commands and never run mix; the coordinator owns
every git transition, format, compile, and the verify ladder.

## Lane partition

| lane | owns (create/edit, nothing else) |
|---|---|
| L1 | `lib/ggen_igniter/epoch_watermark.ex`, `lib/mix/tasks/ggen_igniter.epoch.watermark.ex` |
| L2 | `lib/ggen_igniter/epoch_freshness.ex` |
| L3 | `lib/mix/tasks/ggen_igniter.epoch.check.ex`, `lib/mix/tasks/ggen_igniter.epoch.explain.ex` |
| L4 | `priv/ggen/semantic-jira-pack/ontology.ttl` (additive), `priv/ggen/semantic-jira-pack/gates/epoch_boundary.rq`, `priv/ggen/semantic-jira-pack/VOCABULARY.md` (additive) |
| L5 | `lib/ggen_igniter/semantic_jira/epoch_plan.ex`, `lib/mix/tasks/semantic_jira.admit_candidates.ex` (additive gate) |
| L6 | `test/ggen_igniter_epoch_freshness_test.exs` |
| L7 | `test/ggen_igniter_epoch_admission_test.exs` |
| L8 | `CLAUDE.md` (epoch section only) |

## Shared seams

None beyond the contract below. `admit_candidates.ex` (L5) is the only lane editing an
existing code file; no other lane reads or writes it.

## Contract v1 (binding, identical text in every dispatch prompt)

Closed verdict set: `ALIVE_GENERATED | ALIVE_FRESH_RESIDUE | REFUSED_NO_ATTRIBUTION |
REFUSED_PRE_EPOCH_RECEIPT | REFUSED_LEGACY_EDIT | REFUSED_COPY_READD |
REFUSED_UNEXPLAINED_SIMILARITY | REFUSED_GENERATED_ARTIFACT_MUTATED |
UNKNOWN_PROVENANCE`. Alive iff name starts `ALIVE_`.

`GgenIgniter.EpochWatermark`: manifest JSON `schema_version:"1"`, `epoch`,
`watermark_instant` (ISO8601 UTC Z), `head_sha`, `tree_sha` (40-hex),
`implementation_glob` (default `lib/**/*.ex`), `files: [{"path","blob_sha"}]`
path-sorted; persisted `<base>/.ggen_igniter/epoch/<epoch>/watermark.json`.
`stamp!(base_dir, epoch, opts \\ []) :: {:ok, manifest, path} |
{:error, {:refused_epoch_watermark, %{code: :not_a_git_work_tree | :restamp_required |
:empty_implementation_set, detail: binary}}}`; opts `glob:`, `restamp: %{reason: binary} |
false`, `now: DateTime.t()`. Blob shas from `git ls-files -s -- <glob>` (3rd column).
Identical re-stamp idempotent; different tree under same epoch needs `restamp` opt else
`:restamp_required`. `load(base_dir, epoch) :: {:ok, manifest} | {:error, :not_found}`.

Candidate blob sha: pure-Elixir git blob id — `:crypto.hash(:sha, "blob " <> size <>
<<0>> <> content)` hex lowercase.

`GgenIgniter.EpochFreshness`: `check(base_dir, epoch, opts) :: {:ok, report} |
{:error, {:refused_epoch_check, %{code: :watermark_not_found | :not_a_git_work_tree,
detail}}}`; opts `watermark:` (loaded manifest), `threshold:` (float; watermark
`similarity_threshold` else 0.9), `report_path:`, `now:`. Report keys: `schema_version`,
`epoch`, `subject_tree` (sha256 hex over sorted `"path blob_sha"` candidate lines),
`watermark_tree`, `threshold`, `implementation_files: %{"total","admitted_generated",
"admitted_residue","refused"}`, `files: [file_report]`, `standing: :ALIVE | :REFUSED`,
`checked_at`. file_report keys: `path, blob_sha, provenance_kind ("generated"|"residue"|
"none"), manufacture_receipt, source_inputs, closest_pre_epoch_match, similarity,
authorship_newest (informing only), verdict`.

Attribution inputs: `<base>/.ggen_igniter/manifest.json` (recipes, `outputs`
`%{path => blob_sha}`); `<base>/.ggen_igniter/receipts/*.jsonl` (rows `id`, `standing`,
`finished_at`, `files`, `outputs`); residue ledger `<base>/HANDWRITTEN.md` rows
`path | ... | YYYY-MM-DD` (date ≥ watermark date ⇒ residue attribution).

Verdict precedence (deterministic): run-level refusal first (missing watermark /
non-git). Per file: (1) post-watermark alive receipt lists file → recorded output hash
present and ≠ current blob ⇒ `REFUSED_GENERATED_ARTIFACT_MUTATED`, else
`ALIVE_GENERATED` (similarity recorded, never refuses); (2) residue row ⇒ similarity ≥
threshold ⇒ `REFUSED_UNEXPLAINED_SIMILARITY` else `ALIVE_FRESH_RESIDUE`; (3) no
attribution ⇒ same-path-in-watermark `REFUSED_LEGACY_EDIT`; exact blob match any legacy
path `REFUSED_COPY_READD`; similarity ≥ threshold `REFUSED_UNEXPLAINED_SIMILARITY`;
only pre-watermark receipts `REFUSED_PRE_EPOCH_RECEIPT`; else `REFUSED_NO_ATTRIBUTION`.
Post-watermark receipt: `finished_at` parses ≥ watermark_instant AND standing alive.
Unparseable/other-standing receipts never attribute.

`EpochFreshness.similarity(a, b) :: float`: byte-equal ⇒ 1.0; else max(ast_jaccard,
token_jaccard). AST features: `{call, arity}` pairs + literal atoms from
`Code.string_to_quoted` (rescue ⇒ skip); token features: comment-stripped
whitespace-collapsed non-blank lines. Jaccard per set; deterministic.

`explain(base_dir, epoch, rel_path, opts) :: {:ok, file_report + "law" => binary} |
{:error, refused_epoch_check}`.

Mix tasks (exit 0 alive / 1 refusal-or-unknown / 2 invocation): `ggen_igniter.epoch.watermark
--epoch REQ [--base-dir] [--glob] [--restamp REASON]`; `ggen_igniter.epoch.check --epoch REQ
[--base-dir] [--threshold F] [--report P]`; `ggen_igniter.epoch.explain --epoch REQ --file
REQ [--base-dir]`. Print Jason JSON + summary line `epoch check: standing=... admitted_generated=N
admitted_residue=N refused=N`.

`GgenIgniter.SemanticJira.EpochPlan.check(order :: map(), watermark :: map() | nil) ::
:ok | {:error, {:refused_epoch_plan, code}}`; codes `:legacy_edit |
:unattributed_implementation | :reuses_pre_watermark_artifact | :watermark_unavailable`;
`refusal_code_string/1` maps to `REFUSED_EPOCH_LEGACY_EDIT`,
`REFUSED_EPOCH_UNATTRIBUTED_IMPLEMENTATION`,
`REFUSED_EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT`,
`REFUSED_EPOCH_WATERMARK_UNAVAILABLE`. Gate applies iff `order["epoch"]` nonempty
string; applies + watermark nil ⇒ `:watermark_unavailable` (fail closed). Order keys
`plan_touches: [path]`, `manufacture_plan: %{path => "generated"|"residue"}`,
`source_artifacts: [path]`. Rules: plan_touches path in watermark files without
manufacture_plan entry ⇒ `:legacy_edit`; plan_touches path glob-matching
`implementation_glob`, not in watermark files, without manufacture_plan entry ⇒
`:unattributed_implementation`; source_artifacts path in watermark files without
manufacture_plan entry ⇒ `:reuses_pre_watermark_artifact`.

`semantic_jira.admit_candidates`: new `--epoch-manifest PATH` (watermark.json). Per
line, gate fires only when the line carries `"epoch"`; missing/unreadable manifest with
epoch lines present ⇒ every epoch line refused `REFUSED_EPOCH_WATERMARK_UNAVAILABLE`;
lines without `"epoch"` byte-identical (no-regression contract).

Ontology (additive only): `sj:EpochBoundary` class; `sj:epochLabel`, `sj:watermarkTree`,
`sj:similarityThreshold`, `sj:implementationGlob`; work-order props `sj:epoch`,
`sj:planTouches`; instant reuses `dcterms:issued`. `gates/epoch_boundary.rq` mirrors
`020_work_orders.rq` OPTIONAL-column pattern.

Tests: real temp git repos (init + user config + commit via System.cmd; never
worktrees); every verdict atom witnessed ≥ 1; anti-vacuity pair (fresh tree passes,
one legacy revert fails); watermark idempotency + restamp refusal; fail-closed cases;
admission typed refusals + no-regression line.

Style: repo idiom — moduledoc states WHY with evidence, `@spec` everywhere, typed
refusals, comments only for constraints code cannot show.
