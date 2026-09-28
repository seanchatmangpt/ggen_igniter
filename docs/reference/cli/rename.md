# `mix ggen_igniter.rename`

Defect-routed wrapper over `Igniter.Refactors.Rename.rename_function/4`
(`GgenIgniter.Refactors.SafeRename`): fixes two upstream defects (guarded `def` heads left
un-renamed; parenless zero-arity `def` crash).

```bash
mix ggen_igniter.rename --from Mod.old/1 --to Mod.new [--arity N] [--deprecate soft|hard] [--path GLOB]
```

`--help` and `-h` both print the task's own help. Proofs:
`test/ggen_igniter_rename_task_test.exs`, `test/ggen_igniter_safe_rename_test.exs`,
`test/ggen_igniter_upstream_rename_blocker_test.exs`.
