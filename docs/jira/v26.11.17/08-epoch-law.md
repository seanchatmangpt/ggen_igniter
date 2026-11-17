# 08 Epoch Law Exploration

Standing: UNVERIFIED

Lane 08 of v26.11.17. Scope: `EpochWatermark`, `EpochFreshness`, `SemanticJira.EpochPlan`,
the closed verdict set, the similarity detector and fail-closed behavior. Method: static
read of `lib/` and `test/` plus `ls`/`grep`. No code was executed: `elixir`, `mix` and
`erl` are absent from this sandbox (`which mix erl` printed nothing; `elixir` returned
`command not found`) and no `.ggen_igniter/epoch/` directory exists in this checkout.
Every finding is therefore a static-read claim and is UNVERIFIED until a run confirms it.
The verdict set in code matches CLAUDE.md (nine atoms). The gaps below are fail-open
edges, a latent crash, vacuous-pass edges and untested paths.

## Findings

Evidence key: F=lib/ggen_igniter/epoch_freshness.ex, W=epoch_watermark.ex,
P=semantic_jira/epoch_plan.ex, FT=test/ggen_igniter_epoch_freshness_test.exs,
T.check/T.explain/T.watermark=lib/mix/tasks/ggen_igniter.epoch.*.ex.

|id|finding|standing|evidence|
|---|---|---|---|
|E1|Verdict atoms = 9, equal to CLAUDE.md table|UNVERIFIED|F:72-82|
|E2|Bad `watermark_instant` falls back to unix 0; all receipts post|UNVERIFIED|F:864-871|
|E3|`put_manifest_hash` nests a list on a 2nd hash for one path|UNVERIFIED|F:599-601|
|E4|E3 list reaches `Regex.match?` in `hash_matches?`: likely raise|UNVERIFIED|F:606-617|
|E5|Receipt with no recorded hash and no manifest hash is ALIVE_GENERATED|UNVERIFIED|F:547-552|
|E6|`standing/1` on zero files is `:ALIVE` (vacuous pass)|UNVERIFIED|F:835-837|
|E7|Court does not require `"files"` key; EpochPlan does|UNVERIFIED|F:691-697|
|E8|Missing `files` makes legacy sets empty: no LEGACY_EDIT, no COPY_READD|UNVERIFIED|F:701-703|
|E9|Unparsable receipt lines are counted, never gate the exit code|UNVERIFIED|F:630-634|
|E10|`load_receipts` uses `File.read!`: unreadable receipt file crashes run|UNVERIFIED|F:627|
|E11|Residue row admits any path string; no check the path is in-tree|UNVERIFIED|F:678-687|
|E12|Residue date compared to watermark calendar date, not instant|UNVERIFIED|F:647-676|
|E13|Residue row ALIVE even if file is byte-identical to legacy blob|UNVERIFIED|F:391-406|
|E14|Receipt with `files` AND path in legacy set still ALIVE_GENERATED first|UNVERIFIED|F:374-389|
|E15|Receipts keyed by path only; no check receipt output exists in manifest|UNVERIFIED|F:503-507|
|E16|Similarity: unparsable source gives empty AST set; token Jaccard only|UNVERIFIED|F:945-979|
|E17|Both-empty feature sets score 0.0; empty file never trips threshold|UNVERIFIED|F:947,1001-1004|
|E18|`strip_comment` cuts at first `#`, including inside strings|UNVERIFIED|F:1017-1022|
|E19|Size band prune scores 0.0 beyond 4x; shared-module splits evade|UNVERIFIED|F:735|
|E20|Legacy compare is O(files x legacy) with `git cat-file` per blob, cached|UNVERIFIED|F:701-756|
|E21|Unreadable `git cat-file` blob yields nil content, score 0.0 silently|UNVERIFIED|F:745-752|
|E22|`--threshold` is CLI-overridable; lowering needs no restamp reason|UNVERIFIED|T.check.ex:28-34|
|E23|Threshold in watermark is parsed leniently; junk string reverts to 0.9|UNVERIFIED|F:273-290|
|E24|`explain` ignores `--threshold`; `check` honors it|UNVERIFIED|T.explain.ex:25-37|
|E25|`explain` of a path outside the globs still gets a full verdict|UNVERIFIED|F:175-196|
|E26|Planes: old watermark gets plane standing UNKNOWN but files judged alone|UNVERIFIED|F:790-809|
|E27|Empty plane with `watermarked` true reports `:ALIVE` (vacuous)|UNVERIFIED|F:795-800|
|E28|`stamp!` only sees TRACKED files; untracked legacy is invisible|UNVERIFIED|W:46-55|
|E29|`stamp!` refuses only if ALL globs empty; one empty plane stamps silently|UNVERIFIED|W:276-285|
|E30|Stamp records HEAD; a dirty working tree is stamped as the committed tree|UNVERIFIED|W:131-133|
|E31|Restamp reason is free text; any non-empty string redefines the boundary|UNVERIFIED|W:171-174|
|E32|Restamp overwrites in place; prior identity is not retained in the file|UNVERIFIED|W:214-234|
|E33|Idempotency ignores `implementation_globs`: globs change with same tree|UNVERIFIED|W:193-198|
|E34|Watermark task exposes `--glob` only, no plural globs flag|UNVERIFIED|T.watermark.ex:31-32|
|E35|EpochPlan: `"epoch"` must be non-empty binary; non-binary epoch skips gate|UNVERIFIED|P:52,89|
|E36|EpochPlan: non-list/non-binary `plan_touches` becomes `[]` and passes|UNVERIFIED|P:106-109|
|E37|EpochPlan: `manufacture_plan` value `generated` is trusted, not verified|UNVERIFIED|P:114-116|
|E38|EpochPlan: touch paths are not normalized (`./lib/x.ex`, `lib//x.ex`)|UNVERIFIED|P:65-72|
|E39|EpochPlan: `glob_matcher(nil)` clause is unreachable from `impl_globs`|UNVERIFIED|P:150|
|E40|Court uses `Path.wildcard`; plan gate uses regex; two glob dialects|UNVERIFIED|P:161-183|
|E41|Tests exist for 9 verdicts incl. UNKNOWN via unreadable path|UNVERIFIED|FT:64-248|
|E42|No test for bad `watermark_instant` (E2)|UNVERIFIED|grep: only valid instants in tests|
|E43|No test for two manifest entries on one path (E3)|UNVERIFIED|grep manifest.json: none|
|E44|No test for unparsable receipts or standing variants|UNVERIFIED|grep "unparsable": none|
|E45|No test for empty-tree standing or `--threshold` override|UNVERIFIED|grep threshold: echo only|
|E46|No epoch step in ci.yml or mix.exs aliases|UNVERIFIED|grep epoch: no hits|
|E47|UNKNOWN trigger matches CLAUDE.md; test exists|UNVERIFIED|FT:231-247|

## Notes on the highest-risk items

- E2 is the sharpest fail-open. `parse_instant/1` returns `DateTime.from_unix!(0)` for a
  missing or undecodable `watermark_instant`. The file is otherwise valid JSON, so `load/2`
  does not return `:corrupt`. Every receipt with alive standing then counts as
  post-watermark. This contradicts the moduledoc "fail closed" claim for corrupt stamps.
- E3/E4 are a suspected crash, not a verdict error. The same output path in two manifest
  entries yields `[["h2"], "h1"]` shape. A run on an Elixir toolchain is needed to confirm.
- E5/E15 weaken `ALIVE_GENERATED`. A receipt row with `files` but no hashes admits any
  bytes at that path. CLAUDE.md says admission needs a recorded hash equal to the blob.
- E6/E27 mean a tree whose globs match zero files reports ALIVE. The stamp refuses an
  all-empty set, but the court has no matching guard.
- E22 lets a caller lower the similarity falsifier at check time with no recorded reason.

## Next

1. Run `mix test test/ggen_igniter_epoch_*_test.exs` on a toolchain host and paste output.
2. Write falsifiers for E2, E3, E5, E6, E9, E22 as failing-first tests (defect-round).
3. Decide whether E2 should refuse with `watermark_not_found`-style code; owner: court.
4. Add an epoch check step to CI or record in `docs/status.md` that none exists (E46).
5. Probe E38 with a `./lib/x.ex` plan line against a stamped manifest.
6. Probe E13 with a residue row over a byte-identical legacy file.
7. Probe E19 with a legacy file split into three modules, then run `epoch.check`.
8. Reconcile E40 by a property test over both glob dialects on the same path set.

## See Also

- `CLAUDE.md` (Epoch boundary section)
- `docs/jira/v26.11.17/LANES.md`
- `docs/archive/jira/v26.9.27/_LANES.md` (Contract v1)
- `lib/ggen_igniter/epoch_freshness.ex`, `lib/ggen_igniter/epoch_watermark.ex`
- `lib/ggen_igniter/semantic_jira/epoch_plan.ex`
