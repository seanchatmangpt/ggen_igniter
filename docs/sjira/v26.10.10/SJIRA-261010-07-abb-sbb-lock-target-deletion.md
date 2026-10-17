# SJIRA-261010-07 — ggen-abb-sbb Cargo.lock + target/ deletion (USER-RUN)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P2 (user action; permission-denied to agents)
- **Blocked-by**: none

## Task

DoD #20: `crates/ggen-abb-sbb/Cargo.lock` and `crates/ggen-abb-sbb/target/` are
stale workspace-member artifacts. Agent deletion was permission-denied in Phase 1
(receipt table row 2: "NOT DONE — permission-denied; recorded, left open").
User runs:

```
rm -f /Users/sac/ggen/crates/ggen-abb-sbb/Cargo.lock
rm -rf /Users/sac/ggen/crates/ggen-abb-sbb/target
```

## Acceptance

- Both paths absent: `ls /Users/sac/ggen/crates/ggen-abb-sbb/` shows no `Cargo.lock`, no `target/`.
- `cargo check -p ggen-abb-sbb` exit 0 after deletion (workspace lock governs).

## Constraints

- User-run only; do not chmod/escalate around the permission denial.
- Do not add `Cargo.lock` to `.gitignore` as a workaround — the file should simply not exist in the member dir.
