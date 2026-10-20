# Witness: Semantic Jira completion into ~/smalt (v26.10.19)

Goal: "finish Semantic Jira so it can go from ~/ggen-marketplace & ~/ggen-legacy to
complete projects with ~/smalt." First end-to-end closure of a pack-sourced order into
the smalt tree through the full admission -> execute -> gates -> receipt -> ledger chain.

## Apparatus

- `mix semantic_jira.complete` (added this pass, `6f2aff7`): loops
  frontier -> execute -> reconcile over admitted orders until the frontier is empty;
  fail-closed on first per-order refusal; completion receipt.
- Multi-artifact orders: order-carried `outputs` list — one `Reconcile.run` per artifact
  (template pack-relative, out target-relative, per-artifact explicit queries), path-scope
  refusals (`bad_output_path`), artifact set inside the sealed export before digest.

## Run 1 — SMALT-SUBSTRATE-REGEN: REFUSED (fail-closed, honest)

`mix semantic_jira.complete --work-orders orders_smalt-substrate-pack.json --ledger
ledger-substrate.ndjson --pack-dir ~/ggen-marketplace/packs/smalt-substrate-pack
--target-dir ~/smalt --receipts-dir ... --verifier-suite ci --alias sac/smalt=smalt`

Refusal chain witnessed (each a typed refusal, ledger byte-unchanged each time):

1. `missing_alias sac/smalt` (descriptor hop) → order carries `--alias sac/smalt=smalt`.
2. `base_drift` (execute hop, `mu_on_O`): order pinned `deb07952`, real smalt HEAD was
   `8ca1b827` — the base-drift gate caught a real drift. Re-pinned.
3. `verification_failed` / `unbound_facts` (8 facts, gate `shapes-coverage`): the
   substrate pack FAILS its own fail-closed unbound court against current reality —
   the pack is stale relative to the smalt tree (note: `mix smalt.gen` never runs gates,
   so this court had never run against the current pack). Work happened, standing did
   not advance; the 5 actuated files were restored from HEAD (snapshot kept in
   /tmp/sj-smalt-witness/actuated-snapshot/). Ledger byte-unchanged.

## Run 2 — SMALT-SEMCONV-REGEN: EXECUTED, project complete (exit 0)

Fixes forced by the witness (each a real bug the fail-closed chain surfaced):
1. `receipt_digest_mismatch` — artifacts were placed after digest; fixed: artifact set
   inside the export before `Descriptor.receipt_digest/1`.
2. SemConv pack had NO gates/ — the reconciler correctly refuses promotion without
   witnessed courts (`promotion_refused [:courts]`); added the real fail-closed court
   `gates/010_semconv_census.rq` to the pack (marketplace `e12bc9007`).
3. `required_courts` must name real witnessed gate stems (`semconv_census`).

Final run: UNKNOWN → PARTIAL_ALIVE (honest local ceiling), receipt
`SMALT-SEMCONV-REGEN.json`, ledger event seq 1 with digests, completion receipt
`status: "complete"`, closed `["SMALT-SEMCONV-REGEN"]`. The admitted artifact
`lib/smalt/telemetry/semconv/registry.ex` compiles clean in smalt
(`MIX_BUILD_ROOT=_build-sjw mix compile` → "Generated smalt app"); its render is
semantically identical to the pre-witness file modulo `mix format` whitespace —
disclosed: the SJ local backend does not run `mix format` after actuation
(`smalt.gen` does); formatting after actuation is a named follow-on, since the
receipt already committed to the unformatted bytes.

## Honest boundaries

- Local ceiling stands: outcome `partial_alive`, `head_verified: false` — ALIVE
  remains xaas-fabric-only by the module's own law.
- The substrate order is honestly OPEN, not closed: the smalt-substrate-pack fails
  its own shapes-coverage unbound court and needs pack-side repair (stale pack vs.
  smalt tree) before its orders can close. This is the court working, not a gap in
  the driver.
- ggen-legacy packs: not exercised in this witness (no smalt-targeting legacy pack
  exists; the driver is pack-source-agnostic — any pack dir works as `--pack-dir`).
  A legacy-sourced witness order is the natural next falsifier.