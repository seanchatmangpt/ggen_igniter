# Ghost dirs lane verdict — packs/ without pack.toml (2026-10-09)

Sibling of `SJIRA-261010-13-pack-corpus-dedup-execution.md`. This lane owns only
this file; no deletions, no git state, no pack-dir writes.

**Status (2026-10-09 refresh #2)**: verdict COMPLETE — 2 dirs classified DEAD
(user-gated for deletion); 2 remaining ghost dirs have manifests being applied
by a lane in flight.

## 1. claude-config-max-pack — DEAD (list for user approval)

2 files total, both a stray `.ggen/keys` signing/verifying pair under
`examples/consumer/` (newest mtime epoch 1790290146). No pack.toml, no ggen.toml,
no README, no ontology/templates. Zero references in either repo's ggen.toml,
marketplace, or docs. Same stray-keys class as item 2's documented finding.
Safe to `rm -r` after approval.

## 2. legacy-equivalence-verifier-pack — DEAD (list for user approval)

2 files: stray `.ggen/keys` signing/verifying pair only. Confirmed DEAD by
`/Users/sac/ggen/docs/architecture/PROOF_CARRYING_MANUFACTURING_PRD_TRACEABILITY.md`
(line 33): content migrated 2026-08-02 to `seanchatmangpt/ggen-legacy`
(coordinate in `config/ggen-legacy-corpus.toml`); the doc explicitly states the
path holds no pack artifacts and must not be cited. Also named as pack.toml-less
in `docs/PUBLICATION_JUDGMENT.md` condition 22 (2026-08-07 ERRC closure).
Safe to `rm -r` after approval.

## 3. multi-projection-pack — MANIFEST-MISSING (real, in active use)

15 files: `ggen.toml` (9 generation rules), `ontology.ttl`, `example.ttl`,
`README.md`, `queries/fields.rq`, 8 `templates/projection.*.tera`,
`tests/verify_pack.py`. Actively referenced by
`examples/cs2-projections/ggen.toml` (18 relative-path references) and audited
clean in `docs/audits/2026-10-08-ggen-law-dod9-hygiene-audit.md`.
Needs a pack.toml. Draft (NOT written to the pack dir — for cap loop next slot):

```toml
[pack]
name = "multi-projection-pack"
version = "0.1.0"
description = "Manufacture language/schema projections (Rust, Python, TypeScript, SQL, Protobuf, GraphQL, JSON Schema, JSON-LD context, manifest) from one RDF ProjectionSpec. Consumed by examples/cs2-projections/ggen.toml."

[capabilities]
provides = ["urn:ggen:pack:multi-projection-pack"]
requires = []
```

## 4. rust-dialect-pack — MANIFEST-MISSING (real, deliberately unwired research)

14 files: `ontology.ttl`, `shapes.ttl`, `README.md`, 8 `rules/*.rq`,
`fixtures/gec-facts.ttl`, `fixtures/adversarial-typing-violations.ttl`
(newest epoch 1784822756). README self-describes as "experimental, not wired
into ggen sync/CI" research built on a real 109-template/21-pack corpus sweep;
audited clean (510 triples) in the 2026-10-08 DOD9 hygiene audit. Content is
real but the pack explicitly is not a production capability. Register only if
the corpus dedup wants it; draft (for cap loop next slot):

```toml
[pack]
name = "rust-dialect-pack"
version = "0.1.0"
description = "EXPERIMENTAL (not wired into ggen sync/CI): RDF/SHACL/SPARQL encoding of a decidable subset of GEC (ggen-emitted-core) Rust for graph-checker pre-screening before cargo build. 55 classes, 30 SHACL shapes, 12 SPARQL boundary rules over a 109-template corpus sweep."

[capabilities]
provides = ["urn:ggen:pack:rust-dialect-pack"]
requires = []
```

## Summary

- DEAD, pending user approval, do not delete in this lane:
  `claude-config-max-pack`, `legacy-equivalence-verifier-pack`.
- MANIFEST-MISSING, drafts above for the cap loop's next slot:
  `multi-projection-pack`, `rust-dialect-pack`.
- Evidence gathered via find/stat listings, pack.toml existence checks, and
  greps over both repos' ggen.toml files, marketplace paths, docs/, and
  `.claude/` (bash hook blocked direct `cat` of the stray key dirs; contents
  were never needed — file listing suffices).
