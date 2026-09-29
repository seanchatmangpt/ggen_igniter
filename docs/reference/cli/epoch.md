# Epoch boundary suite: `ggen_igniter.epoch.*`

Status: **IMPLEMENTED** — verified against the real moduledocs of
`lib/mix/tasks/ggen_igniter.epoch.watermark.ex`,
`lib/mix/tasks/ggen_igniter.epoch.check.ex`, and
`lib/mix/tasks/ggen_igniter.epoch.explain.ex` (plus
`GgenIgniter.EpochWatermark` / `GgenIgniter.EpochFreshness` /
`GgenIgniter.SemanticJira.EpochPlan`).

An epoch is a CalVer implementation boundary: `epoch.watermark` stamps which
implementation files exist, as exactly which git blob SHAs, at the moment an
epoch closes; `epoch.check` judges a candidate tree's implementation
freshness against that stamp; `epoch.explain` shows one file's full
provenance chain. Identity-based by design — `git blame` attributes a
delete-and-re-added file to the re-adding commit, so the boundary is stamped
as exact blob identities instead of authorship history.

## Tasks

- **`mix ggen_igniter.epoch.watermark --epoch LABEL [--base-dir DIR]
  [--glob GLOB] [--restamp REASON]`** — writes
  `.ggen_igniter/epoch/<epoch>/watermark.json`. Re-stamping the same epoch
  over an UNCHANGED tree is idempotent; over a CHANGED tree it is refused
  unless `--restamp REASON` (the reason is recorded in the manifest —
  redefining what "legacy" means for an epoch is not an invisible act).
  Exit `0` stamped (or idempotent no-op), `1` refused (typed JSON on
  stderr), `2` bad invocation.
- **`mix ggen_igniter.epoch.check --epoch LABEL [--base-dir DIR]
  [--threshold F] [--report PATH]`** — the epoch self-gate, the WITNESS:
  judges every implementation-plane file in the tree against the watermark
  and refuses anything carried over from the pre-epoch implementation.
  Detector law: **receipts admit; similarity falsifies; blame informs.** A
  refusal exit of 1 is the DESIGNED outcome for a legacy-carrying tree — a
  verdict, not a crash. Exit `0` every file ALIVE, `1` any
  refusal-or-unknown (report JSON printed), `2` bad invocation.
- **`mix ggen_igniter.epoch.explain --epoch LABEL --file PATH [--base-dir
  DIR]`** — read-only by design: one file's provenance chain — attribution
  evidence, closest pre-epoch match with similarity, informing git
  authorship, verdict, and the specific condition that would make it ALIVE.
  This task ALWAYS exits 0 on a judged file, even when the verdict inside is
  a `REFUSED_*` atom; `epoch.check` is the gate whose exit code decides.
  Exit `0` judged, `1` could not judge, `2` bad invocation.

## The two-layer law

Admission (`semantic_jira.admit_candidates --epoch-manifest`) refuses
known-illegal plans BEFORE they run; `epoch.check` proves the resulting
BYTES afterwards. Promotion requires both. Admission ≠ proof, proof ≠
prevention.

## Related

- `docs/reference/cli/index.md` — the Semantic Jira suite entry, including
  `admit_candidates`' `--epoch-manifest` gate and its `REFUSED_EPOCH_*`
  refusals.
- `priv/ggen/semantic-jira-pack/VOCABULARY.md` — "Epoch boundary terms"
  (`sj:EpochBoundary`, `sj:epochLabel`, `sj:watermarkTree`,
  `sj:similarityThreshold`, `sj:implementationGlob`, `sj:epoch`,
  `sj:planTouches`).
