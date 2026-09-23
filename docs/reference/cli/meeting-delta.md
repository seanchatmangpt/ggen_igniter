# `mix ggen_igniter.meeting_delta`

Projects a typed, authority-free meeting semantic delta into canonical Semantic Jira
WorkOrder candidates.

```bash
mix ggen_igniter.meeting_delta \
  --delta /secure/zoe-youth.delta.json \
  --binding /secure/zoe-youth.binding.json \
  --out /secure/zoe-youth.work-orders.json
```

The delta is expected to contain candidate work manufactured by the upstream project
gym. Every candidate must remain `CONSTRUCT_ONLY / CANDIDATE / NOT_EXECUTED` with
`do_authority=false`. The task fails closed if a candidate attempts to cross that
boundary or if its delta class and work kind disagree.

The binding supplies the exact repository/base SHA, bounded path scope, courts,
evidence requirements, acceptance criteria, falsifiers, projection set, receipt
classes, evidence ceiling, and promotion rule. Those values are never inferred from
meeting prose.

The output WorkOrders are kernel-admitted with `standing=UNKNOWN` and
`authority=NONE`. This task does **not** perform SHACL admission, frontier selection,
XaaS materialization, SA2A/BRCE dispatch or DO, receipt verification, replay, merge,
publication, deployment, or standing promotion.
