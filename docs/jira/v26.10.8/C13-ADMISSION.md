# C13-ADMISSION — C13 Fixed-Point Self-Admission Receipt

# C13-ADMISSION

Landed: 2026-10-08. Subject: `/Users/sac/ggen_igniter` @ `e42dbab`
(`feat/adr-0010-gate-convention`), head `e42dbabb79a7af353d29eee895e57655209525e4`.

The C13 fixed-point acceptance is: "this order admits via
`semantic_jira.admit_candidates` and executes via `semantic_jira.execute`". This
receipt records the real run of both legs against the pack's own machinery.

## Admit leg — ADMITTED (the fixed-point's self-admission holds)

Extraction: `sj:c13-fixed-point` (ontology.ttl:1968) into a candidates JSONL
map with the 16 required keys (`identity title description subject repository
base_sha standing evidence_ceiling promotion_rule replay_identity
required_courts required_evidence acceptance falsifiers projections
origin_authority`), plus `path_scope` and `authority_requirement: "NONE"`.
Standing entered as literal `"UNKNOWN"` (per candidate-bounds gate); origin =
the objective the order itself names: `sj:objective-project-manufacturer`.

Command:

```
MIX_BUILD_ROOT=_build-laneadmit mix semantic_jira.admit_candidates \
  --candidates /tmp/c13-admit/candidates.jsonl
```

Real output:

```
admitted 1 C13-FIXED-POINT origin=https://ggen-igniter.dev/ontology/semantic-jira#objective-project-manufacturer origin_digest=sha256:639c07b80d557781fc76da0820feb43ac8b3161d527ccbb147533b7e645af0f8 work_order_digest=sha256:b61fcf665568828b47cbc670ca7fd0b75e84576f52434188c726318d933008d1
summary admitted=1 refused=0
```

Exit 0.

Digests:

- `origin_digest` `sha256:639c07b8…af0f8` — byte-matches the `sj:admissionDigest`
  pinned on `sj:objective-project-manufacturer` in the canonical ontology
  (ontology.ttl:2440), confirming the resolved authority is the pinned node.
- `work_order_digest` `sha256:b61fcf66…008d1` — the admitted order snapshot.
- Pack ontology sha256: `8ebad50fe56c6ae462524c28123723c032d459682a7e17e1e9249a56c7533043`.

## Execute leg — typed refusal: base_drift (the remaining rung)

Command: `mix semantic_jira.execute` (local backend, `--pack-dir
priv/ggen/semantic-jira-pack --target-dir /Users/sac/ggen_igniter`, ledger and
receipt-out under `/tmp/c13-admit/`).

Result: typed refusal at the `execute` hop, ledger byte-unchanged, no receipt
written (`refused.json` only):

```json
{
  "broken_term": "mu_on_O",
  "hop": "execute",
  "reason": [
    "base_drift",
    "target HEAD e42dbabb79a7af353d29eee895e57655209525e4 != order base_sha 52c00b7ca087df95d7273a19315169cfef6e3fe4"
  ],
  "standing": "REFUSED"
}
```

This is the honest result, not a failure of the admit leg: the order pins
`base_sha 52c00b7c…e3fe4` but the order itself landed on the branch as commit
`e42dbab`, so exact-head execution is unreachable until the order's base_sha
is re-bound to the head that carries it (or execution runs at the pinned base).
The fixed-point's ADMIT leg is proven; the execute leg remains the one
outstanding rung, blocked on base re-binding, not on admission machinery.

## Re-bind (2026-10-08, later pass)

The order's `sj:baseSha` was re-bound from `52c00b7c…e3fe4` to
`66aa197556b37297cff66acc4ff16c872c16ac2d` (ontology.ttl:1974, plus the court
description's pinned head). The honest reading: the order's subject is the pack
state AT the head that carries it, so the base must be the carrying head, not a
predecessor. The court description discloses the re-bind inline.

Re-admission (same candidates pipeline, rebuilt with the new base):

```
admitted 1 C13-FIXED-POINT origin=…objective-project-manufacturer
origin_digest=sha256:639c07b8…af0f8
work_order_digest=sha256:fea006056c0427d99d6bd48bf15465479a92aa180032bc993d1625ccb5b2a821
summary admitted=1 refused=0   (exit 0)
```

## Execute leg, second attempt — typed refusal: sync_failed (current rung)

With base_drift cleared, `mix semantic_jira.execute` advanced past the
base check and refused at the sync hop, ledger byte-unchanged, no receipt
written:

```json
{"broken_term":"mu_on_O","hop":"execute","standing":"REFUSED",
 "reason":["sync_failed",
 "GgenIgniter.Reconcile.run/1 raised: multiple templates found in
 priv/ggen/semantic-jira-pack/templates/ (a2a_agent_card.json.eex,
 a2a_manufacture.ex.eex, ard.md.eex, jira.md.eex, ocel.json.eex,
 plan.hddl.eex, prd.md.eex, projection.md.eex, target_pack.ex.eex,
 vision.md.eex, wbpr.md.eex) -- pass :template explicitly"]}
```

Cause: the local execute backend calls `Reconcile.run(pack_dir: pack_dir,
out: …)` with no `:template`
(`lib/ggen_igniter/semantic_jira/execute.ex:312`), and `Reconcile.run/1`
raises on multi-template packs (`lib/ggen_igniter/reconcile.ex:220`). The
semantic-jira-pack has 11 templates. This is a structural limit of the
execute backend (single-template assumption), not an admission or base
problem — the remaining rung for full execution is teaching the local
execute backend to resolve or accept an explicit template for multi-template
packs (or executing against a single-template pack subject).

## Standing

- `sj:c13-fixed-point` standing: UNKNOWN (admitted at UNKNOWN; standing only
  from receipts — none yet; the execute refusal confers none).
- Acceptance status: ADMIT leg ALIVE (re-admitted at new base,
  `work_order_digest fea00605…a821`), EXECUTE leg REFUSED(`sync_failed`
  after base re-bind; previously `base_drift`).

## Replay

```
MIX_BUILD_ROOT=_build-lanecourt mix semantic_jira.admit_candidates \
  --candidates <same jsonl>            # → admitted 1 … work_order_digest=b61fcf66…
mix semantic_jira.execute --work-orders <wo.json> --ledger <ndjson> \
  --identity C13-FIXED-POINT --verifier-suite ggen-igniter-local \
  --alias seanchatmangpt/ggen_igniter=ggen_igniter \
  --pack-dir priv/ggen/semantic-jira-pack --target-dir <repo> \
  --receipt-out <p> --out-dir <dir>    # → REFUSED sync_failed (multi-template
                                       #   pack; backend passes no :template)
```
