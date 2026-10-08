# Parity Validation — Final Re-Validation (post Stage1/Stage2)

Stage: FINAL PARITY RE-VALIDATION, run after Stage1 (GM-03, GM-07 deploy-blocks
fix, ggen-core bblock project-wiring, GM2 gate fix) and Stage2 (GI-06 beam4pm
fortune5 trial). This document re-executes exactly the checks that could be
re-executed for real given what Stage1/Stage2 actually landed, and explicitly
separates those from findings carried forward unchanged from the prior
`PARITY-VALIDATION.md` (which remains the canonical record for checks 1 and
2/2b's *original*, pre-GM-07 run).

No new code was written in this stage. Branch: `story/GI-final-parity-validation`
(worktree `/Users/sac/worktrees/GI-final-parity-validation`, base `main` @
`ef06713`). Not merged, not pushed.

## 1. FM-PACK-005 / fortune5-deployment-blocks-pack — RE-EXECUTED, RESOLVED

**Prior state** (`PARITY-VALIDATION.md` check 2/2b): the real `ggen` binary
rejected any `ggen.toml` including `fortune5-deployment-blocks-pack` with
`[FM-PACK-005] pack fortune5-deployment-blocks: zero templates`, because the
pack shipped no `templates/*.tmpl` file. Confirmed a pre-existing upstream
pack defect, not a `ggen_igniter` TOML-IO/schema defect.

**Stage1 fix** (`gm03fix`/`deployBlocksFix` record): GM-07 added
`packs/fortune5-deployment-blocks-pack/templates/deployment_catalog.md.tmpl`
on branch `story/GM-07-deployment-blocks-templates-fix` (commit
`df61773e3ba4554e5af0602bf0bcfcc5526f693c`) in
`~/ggen-marketplace-worktrees/GM-07-deployment-blocks`. Confirmed still
present and on that branch in this stage:

```
$ cd ~/ggen-marketplace-worktrees/GM-07-deployment-blocks && git log -1 --format="%H %s" && git branch --show-current
df61773e3ba4554e5af0602bf0bcfcc5526f693c fix(fortune5-deployment-blocks-pack): add real template, unblock ggen sync run [FM-PACK-005]
story/GM-07-deployment-blocks-templates-fix
$ ls packs/fortune5-deployment-blocks-pack/templates
deployment_catalog.md.tmpl
```

**Re-execution this stage**: built a fresh scratch consumer
(`~/.cache/tmp/gi-parity-final2`, copied from the prior stage's scratch
consumer `~/.cache/tmp/gi-parity-beam4pm`, outside both `~/beam4pm` and
`~/ggen_igniter`) with the GM-07-fixed `deployment_catalog.md.tmpl` copied
into its vendored `fortune5-deployment-blocks-pack/templates/`, and a
`ggen.toml` restoring the full 7-pack `[packs]` table from the prior
validation's Check 2 (5 beam4pm packs + `fortune5-architecture` +
`fortune5-deployment-blocks`). Ran the real `ggen` binary (the same
`~/.local/bin/ggen` docker wrapper, `ggen 26.8.28`, used throughout Stage1/2
and the prior validation):

```
$ cd ~/.cache/tmp/gi-parity-final2 && ~/.local/bin/ggen sync run --dry-run > /tmp/gi-final-check2b.log 2>&1
$ echo $?
0
$ grep -c "FM-PACK-005\|ERROR" /tmp/gi-final-check2b.log
0
$ grep -c "fortune5-deployment-blocks-pack/templates/deployment_catalog.md.tmpl" /tmp/gi-final-check2b.log
1
```

Real dry-run output shows `pipeline.emit ... pipeline.files_generated=67`
(vs. the 60 tracked outputs from Check 1's pre-fix 5-pack config — 7 more
files across the 2 fortune5 packs' templates+gates+ontology, consistent) and
the full digest map includes
`vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack/templates/deployment_catalog.md.tmpl`
with a real BLAKE3-style digest, alongside all 4 `fortune5-architecture-pack`
template digests already confirmed accepted in the prior validation.

**Verdict: FM-PACK-005 rejection is RESOLVED for `fortune5-deployment-blocks-pack`
against the real `ggen` binary, when the GM-07 template fix is applied.**
Caveat (disclosed, not new): the GM-07 fix lives only on the unmerged
`ggen-marketplace` branch `story/GM-07-deployment-blocks-templates-fix` — it
was manually copied into a scratch consumer for this check, exactly as GI-06
did for the beam4pm trial in Stage2. `vendor/ggen-marketplace`'s submodule
pin used by both beam4pm's real checkout and the GI-06 trial worktree
(`20a8732b9e...`) still carries the unfixed, zero-template pack. Until GM-07
is merged and the submodule pointer bumped, any consumer using the pinned
submodule directly (not a hand-patched scratch copy) still hits FM-PACK-005.
This is an integration/merge gap, not a defect in the fix itself — the fix's
content was re-verified against the real binary in this stage, not merely
re-asserted from Stage1's record.

## 2. beam4pm trial's ggen.toml delta vs. bundle manifest — RE-INSPECTED, CONFIRMED

Bundle manifest (`fortune5_ready`), re-read this stage from the GI-05
worktree used in Stage2:

```
$ cat /private/tmp/GI-04-worktree/priv/bundles/fortune5_ready.json
{
  "bundles": {
    "fortune5_ready": {
      "manifest_version": "1.0.0",
      "packs": [
        {"name": "fortune5-architecture", "path_hint": "vendor/ggen-marketplace/packs/fortune5-architecture-pack"},
        {"name": "fortune5-deployment-blocks", "path_hint": "vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack"}
      ]
    }
  }
}
```

Real `ggen.toml` delta from the GI-06 trial commit, re-inspected this stage
(worktree `/Users/sac/worktrees/GI-06-beam4pm-trial`, commit
`aff85f6f9924a569411366f257a1fd380471a8f8`, still present and unmerged):

```
$ cd /Users/sac/worktrees/GI-06-beam4pm-trial && git show HEAD -- ggen.toml
[packs]
-beam4pm-process-model = { ... }
-beam4pm-pro-infra = { ... }
-github-actions-pack = { ... }
 beam4pm-ai-contracts = { ... }
 beam4pm-pro-entitlement = { ... }
-# gh-terraform-pack: investigated 2026-08-30, NOT wired -- ... (4-line comment block)
+beam4pm-pro-infra = { ... }
+beam4pm-process-model = { ... }
+fortune5-architecture = { path = "vendor/ggen-marketplace/packs/fortune5-architecture-pack" }
+fortune5-deployment-blocks = { path = "vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack" }
+github-actions-pack = { ... }
```

**Pack-membership check (this stage's specific question): CONFIRMED, no
silent extra or missing packs.** All 5 original packs
(`beam4pm-ai-contracts`, `beam4pm-pro-entitlement`, `beam4pm-pro-infra`,
`beam4pm-process-model`, `github-actions-pack`) are still present post-merge
— only reordered, not dropped or duplicated. Exactly the 2 packs named in
the bundle manifest (`fortune5-architecture`, `fortune5-deployment-blocks`)
were added — no third pack appeared, and no unrelated pack silently
vanished.

**Carried forward unchanged from Stage2's own record (not re-litigated
here, already correctly disclosed as a real defect):** the diff is *not*
addition-only — `GgenIgniter.Bundle`'s merge/serialize step alphabetically
reorders the entire `[packs]` table and drops the `gh-terraform-pack`
decline comment block, violating this ticket chain's own "addition-only
diff, comment preserved" acceptance bullet. This defect is orthogonal to
pack membership (which is correct) and was not re-executed in this stage
since Stage2's git-log evidence for it is still directly inspectable and
unchanged (verified above: `git show HEAD -- ggen.toml` on the same,
still-present, unmerged commit reproduces the identical diff Stage2
reported).

## 3. What was re-executed for real in this stage vs. carried forward

| Item | This stage | Prior stage |
|---|---|---|
| Real `ggen` binary run against a `ggen.toml` including the GM-07-fixed `fortune5-deployment-blocks-pack` | **Re-executed** — fresh scratch consumer, exit 0, 67 files, zero FM-PACK-005/ERROR occurrences | Stage2 (GI-06 trial) also exercised this via the fortune5_ready mix task + manual template copy into its own worktree; this stage independently reproduced it via a separate, minimal scratch copy |
| GM-07 fix branch/commit still present and unmerged | **Re-confirmed** via `git log`/`ls` in `~/ggen-marketplace-worktrees/GM-07-deployment-blocks` | Landed in Stage1 |
| Bundle manifest content (2-pack scope) | **Re-read** from `/private/tmp/GI-04-worktree/priv/bundles/fortune5_ready.json` | Unchanged since ticket 03's original bundle; Stage1 did not touch it |
| GI-06 trial's `ggen.toml` diff (pack membership) | **Re-inspected** via `git show HEAD -- ggen.toml` on the still-present, unmerged commit `aff85f6f9924a569411366f257a1fd380471a8f8` | Diff content identical to Stage2's own report — not a new run, but independently re-read from the real commit, not from Stage2's prose alone |
| GI-06 trial's 9-gate SPARQL pass, `gate_m2_check.sh` PASS, mix task success | **Not re-executed** this stage (would require re-running the full Elixir/rdflib pipeline against the trial worktree; the worktree's `mix.exs` still carries its TEMPORARY local-path override and `vendor/ggen-marketplace`'s untracked hand-patch, both consistent with Stage2's disclosed state, but the actual `mix ggen_igniter.fortune5_ready` / gate SPARQL / `gate_m2_check.sh` commands were not re-run for real in this stage) — carried forward from Stage2's record only | Executed in Stage2 |
| Direct Rust-vs-Elixir `SchemaDispatch`/`GgenToml.IO` code paths (Check 1) | **Not re-executed** — no code in `ggen_igniter`'s schema-dispatch/TOML-IO/merge logic changed between the prior validation and this stage, so Check 1's Frontmatter-classification parity finding is carried forward unchanged | Executed in prior `PARITY-VALIDATION.md` |
| GGEN-1804 (byte-for-byte `ggen.toml` round-trip) | Not attempted, same disclosed out-of-scope status as before | N/A |

## 4. Overall verdict — does the installer + bundle packs now behave consistently end to end?

**PARTIAL, not full parity — the specific gap named, not glossed over.**

- The one previously-disclosed hard rejection (FM-PACK-005 against
  `fortune5-deployment-blocks-pack`) **is resolved** at the pack-content
  level: the real `ggen` binary now accepts a `ggen.toml` wiring that pack,
  when the GM-07 template fix is present. Re-verified for real in this
  stage with a fresh scratch consumer, not merely re-asserted from Stage1.
- The beam4pm trial's pack membership **is consistent** with what the
  bundle manifest declares — exactly 2 packs added, all 5 pre-existing packs
  retained, no silent extras or omissions. Re-inspected for real in this
  stage against the still-present, unmerged trial commit.
- **Full end-to-end consistency is still blocked by three integration gaps,
  none fixed in this stage, all previously disclosed and none newly
  discovered here:**
  1. The GM-07 template fix is not merged into `ggen-marketplace`, so
     `beam4pm`'s real vendored submodule pin (and any consumer that has not
     hand-patched a scratch copy the way this validation and GI-06 both
     did) still hits FM-PACK-005 in practice.
  2. `GgenIgniter.Bundle`'s TOML merge/serialize step does not produce an
     addition-only diff (reorders `[packs]`, drops a comment block) —
     `ggen_igniter`'s own installer output diverges from its stated
     contract even though the *content* it produces is accepted by the real
     `ggen` binary.
  3. The GM2 atomic-delete fix for `gate_m2_check.sh` (`story/GM2-gate-fix`)
     is real and committed but not merged to `beam4pm`'s `main` — so
     `gate_m2_check.sh` on `main` today is still the unprotected version;
     Stage2's own incident (a killed redundant run leaving 317 generated
     files deleted with no restore trap, manually recovered) is live
     evidence this gap is not hypothetical.
- Check 1 (`SchemaDispatch` Frontmatter-classification parity) and the
  GI-06 trial's 9-gate/`gate_m2_check.sh` results were **not re-executed**
  in this stage — carried forward from their respective prior stages
  because nothing in their inputs changed. Per this run's own instruction
  not to claim full parity if a check could not be re-executed for real:
  this document does not claim those two items as freshly re-verified —
  see the table in §3 for exactly which lane each finding belongs to.

## See Also

- `~/ggen_igniter/docs/jira/v26.9.1/PARITY-VALIDATION.md` — the prior-stage
  validation this document re-validates against (canonical for Check 1 and
  the original, pre-GM-07 FM-PACK-005 finding)
- Stage1/Stage2 structured records (`gm03fix`, `deployBlocksFix`,
  `bblockWiring`, `gateM2Fix`, `beam4pmTrial`) — the source of every "carried
  forward" claim in §3's table
