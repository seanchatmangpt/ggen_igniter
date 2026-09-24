# semantic-jira-prose fixture

Fixture for `test/ggen_igniter_semantic_jira_prose_test.exs` (lane V23-C, GC-26.9.23
GC23-0/GC23-2): accepted prose, its PVOCAB candidate propositions, and a goal graph.

- `prose.md` -- the accepted prose; its bytes are the provenance
  (sha256:a08df167fb31a4493373cd19c70249acc722cdc5e8253c2632a3aa461380f5d6).
- `extract.json` -- the hand-authored extraction (the fixture's stand-in for the LLM edge;
  `sj:extractedBy "fixture:hand-authored@V23-C"`).
- `candidates.ttl` -- GENERATED, never hand-edited. Emitted by xaas
  `scripts/sjira/prose_spans.py` (git blob 55123e1e36452dcd525340f9009affc70fa46831,
  last changed in xaas 2244d8e18d368841fc6b0a3a892cb729b7729bd0):

```sh
python3 <xaas>/scripts/sjira/prose_spans.py emit --source prose.md --extract extract.json \
  --out candidates.ttl --source-path test/fixtures/semantic-jira-prose/prose.md \
  --extracted-by "fixture:hand-authored@V23-C" \
  --namespace "https://ggen-igniter.dev/sjira/fixture-prose#" --prefix fx
```

- `goal.ttl` -- root `fx:GC-PROSE` (binds the prose by `sj:sourceSha256`), gates
  `fx:GCP-0..2`, successor bucket `fx:GC-PROSE-NEXT`, and the `recipe:mix-format` capability.

Compile it with
`mix semantic_jira.compile_prose --source test/fixtures/semantic-jira-prose/prose.md
--candidates test/fixtures/semantic-jira-prose/candidates.ttl
--goal test/fixtures/semantic-jira-prose/goal.ttl --out-dir <dir>`:
9 admitted propositions, 7 required, 5 WorkOrders.
