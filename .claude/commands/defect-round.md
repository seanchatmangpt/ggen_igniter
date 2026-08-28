Invoke the `defect-round` skill and run one falsification-hardened defect-hunting round
against `ggen_igniter` per its protocol (select -> falsify-first -> fix -> read-back ->
mutate -> gate -> receipt -> commit). If `$ARGUMENTS` names a specific area/file, scope
step 1 (SELECT) to it; otherwise pick freely from real, disclosed gaps in `docs/status.md`
or untested branches.
