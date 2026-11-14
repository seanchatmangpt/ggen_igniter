# 03-VERIFY-LADDER

Standing: UNVERIFIED

Cheapest-first ladder. None of these rungs was run by lane C2 (no build tools permitted).
`P` = `/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack`. `W` = scratch dir
(`/tmp/a2a_full`). FULL fixture = `ontology/app.ttl` containing the base app facts plus all
`P/fixtures/L01..L20*.ttl` concatenated (rung 1). Any pack edit changes the pack hash:
`rm W/ggen.lock` before re-sync until G3 closes.

## Rungs

1. Assemble the FULL fixture.
   `mkdir -p W/ontology && cp <base ggen.toml> W/` then
   `cat <base app.ttl> P/fixtures/L*.ttl > W/ontology/app.ttl`.
   Expect: file exists; prefixes merge without duplicate-prefix errors.
2. `cd W && ggen graph validate`. Expect: exit 0; every gate (010-030, L01_* to L20_*,
   L20_040-047) returns 0 rows. A row is a real finding or a gate defect; record the gate id.
   Cheapest signal: runs all SPARQL gates before any file is written.
3. `cd W && ggen sync run --skip-ea-admission`. Expect: exit 0; files generated for every lane
   whose trigger predicate matched; a second run is a no-op.
4. `cd W && ggen sync run` (no skip flag). Expect: exit 0 (falsifies FM-LAW-015 on empty SBBs,
   see 04). If refused, record the `broken_term`.
5. `cd W && mix deps.get && mix compile --warnings-as-errors`. Expect: exit 0, zero warnings.
   Separate dep warnings from generated-code warnings. ash_a2a verify_skills warns on custom
   module types by design (L12); record whether that surfaces as a compile warning.
6. `cd W && mix test`. Expect: exit 0; base card test, `test/courts/*_test.exs` and the L16
   court test; 0 failures. Failures in policy/identity/transition courts on the L20 fixture
   are real findings, not template defects (L20 notes).
7. Shim courts: `cd W && for s in scripts/shim_court/*.sh; do bash "$s" || exit 1; done`.
   Env: `SHIM_ROOT`, `GGEN_SYNC_CMD`, `SHIM_PACK_ROOT`. Expect per script: exit 0 PASS
   (mutation flips test, sha256 restore byte-exact); 1 FAIL or VACUOUS; 2 restore mismatch;
   3 loud SKIP. Only exit 0 counts; SKIP is not PASS.
8. Replay determinism: copy `lib test config` to `/tmp/a2a_run1`, `rm ggen.lock`, run
   `ggen sync run --skip-ea-admission` again, then `diff -r lib /tmp/a2a_run1/lib`.
   Expect: empty diff (byte-identical re-projection).
9. ggen_igniter tests: `cd /Users/sac/ggen_igniter && mix deps.get &&
   mix test test/ggen_igniter/pack_frontmatter/` (Tera interpreter plus sync unit and golden
   courts). Expect: 0 failures. Then the live-pack golden:
   `mix test --include live_pack test/ggen_igniter/pack_frontmatter/sync_test.exs`.
10. G1 byte-equality: `mix ggen_igniter.pack_sync --pack-dir P --ontology
    W/ontology/app.ttl --out /tmp/igniter_out`, then `diff -r /tmp/igniter_out/lib W/lib`.
    Expect: empty diff on the 8 golden files at minimum.
11. G3 lock: `mix ggen_igniter.pack_sync --relock ...` then the same with
    `--lock ggen_igniter.pack.lock` passes; change one pack byte and rerun with `--lock`:
    must refuse.
12. This repo: `cd /Users/sac/ash_a2a && mix test` is unaffected by pack work (pack lives
    outside it); run only if `mix.exs` deps were edited.

## Recording

Each rung's exit code and first failing line go in a receipt with the pack SHA and the ggen
version (`ggen --version`, baseline 26.11.5). A red rung masks later rungs: after fixing the
first red rung, expect new failures in the next.

## See Also

[01-LANES-INDEX](01-LANES-INDEX.md) · [02-GAP-REGISTER](02-GAP-REGISTER.md) ·
[04-ASSUMPTIONS-TO-FALSIFY](04-ASSUMPTIONS-TO-FALSIFY.md)
