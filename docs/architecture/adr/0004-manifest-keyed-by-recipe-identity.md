# ADR-0004: Reconciliation Manifest Keyed by `(template_path, out_template)` Recipe Identity

## Status

**Accepted.** Live in `GgenIgniter.Manifest.recipe_key/2` and consumed
identically by both `Mix.Tasks.GgenIgniter.Sync`'s inline pipeline and
`GgenIgniter.Reactors.ReconcileReactor`'s own manifest steps.

## Context

`ggen_igniter` needed a way to know, on a re-run, what a prior run of "the
same recipe" actually wrote to disk — so a rename or removal in the
upstream ontology could be mechanically detected as a *stale output*
(`docs/reference/reconciliation/stale-artifacts.md`) instead of silently
orphaning a file. This requires choosing a stable identity for "the same
recipe" across runs where the ontology's own *content* legitimately
changes.

Two candidate keys were considered and rejected, per the module's own
moduledoc:

- **Ontology path alone** — a real developer re-syncs the same
  `--ontology ontology.ttl` repeatedly as they edit its content in place;
  the ontology *path* stays constant across a rename. Keying by path would
  make the same recipe register as a brand-new key on every content edit,
  defeating reconciliation entirely.
- **Pack name alone** — a plain `--ontology`/`--query`/`--template`
  invocation (no `--pack`/`--pack-dir`) has no pack name to key by; this
  would fail to cover a real, supported usage shape.

## Decision

Key manifest entries by `recipe_key(template_path, out_template) =
template_path <> "=>" <> out_template` — the **resolved** template path
plus the **raw, unrendered** `--out`/`to:` string. `pack_dir` is recorded
in each entry as informational metadata only, never part of the identity
key.

## Consequences

- Editing an ontology's content in place while re-syncing the same
  template/out pair is correctly recognized as the same ongoing recipe —
  the manifest key does not change just because the ontology's content did.
- A `--for-each` recipe (multiple rendered rows from one template) still
  has one stable `out_template` string (the unrendered path template, e.g.
  `"lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`) —
  only the per-row *rendered* paths differ, which is exactly what
  reconciliation diffs old-vs-new against.
- This key shape is real, tested, and reused identically by both live
  coordinators (`sync.ex`'s inline pipeline and `ReconcileReactor`) — a
  design choice deliberately not re-derived independently by either.
- `GgenIgniter.Reconcile.run/1` has no manifest awareness at all (see
  ADR-0003's Consequences) — this key shape is irrelevant to that pipeline
  until/unless it gains manifest support.

## See also

- `docs/reference/reconciliation/manifest.md` — full API and JSON shape
- `docs/contributing/adding-a-pack.md` — how pack identity interacts with this key
