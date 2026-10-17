# SJIRA-261010-02 — refuse-effect hook consumer rewiring (ggen)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P0
- **Status** (2026-10-09 refresh #6): upstream refuse-effect hook support
  COMPLETE — hooks refuse-effect 432/0 workspace; graphlaw workspace
  re-verified clean. Refuse-consumer closure GREEN on its own gates;
  `reflexive_law_e2e` was blocked on a pack.rs compile error — error since
  fixed, e2e unblocked. ggen consumer rewiring IN FLIGHT; seam rewire is
  the critical path to cutover.
- **Blocked-by**: none (upstream landed)
- **Lane**: single lane; no worktrees

## Task

Once graphlaw supports refuse-effect hooks, close the one GAP left by the
`GraphLawStore` repoint (DoD #5 = DONE with "1 GAP: refuse-effect hooks → typed
load refusal"):

1. Rewire the `load_hook_pack` path in ggen-engine to consume graphlaw's
   refuse-effect hook surface (replacing the current typed load refusal).
2. Rewire the **FM-LAW-016** fuse path so N3 rule refusals trigger hook effects
   through the new upstream mechanism.
3. Delete any shim/temporary typed refusal left in place pending upstream.

## Acceptance

- A test loading a manifest whose law declares a refuse-effect hook loads the
  hook pack and fires the effect on refusal (real graphlaw store, no doubles).
- Existing refusal-without-hook cases still produce typed refusals; suite
  `cargo test -p ggen-engine --test law_engine_bridge_e2e` green.
- `grep -rn "load_hook_pack" crates/ggen-engine/src` shows no fallback shim path.

## Constraints

- No worktrees; lane owns ggen-engine law/hook files only.
- Blocked until upstream lands — do not stub upstream behavior (London ban).
