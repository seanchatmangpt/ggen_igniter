# `mix ggen_igniter.replay`

Source: `lib/mix/tasks/ggen_igniter.replay.ex` (`Mix.Tasks.GgenIgniter.Replay`,
a plain `Mix.Task`, not `Igniter.Mix.Task`). Status: **IMPLEMENTED, verified
2026-08-27** for the task's basic load/parse/exit-code contract — real,
self-contained code with no dependency on `GgenIgniter.Lock` or
`GgenIgniter.Reactors.ReconcileReactor.plan/1` (both currently missing from
this working tree — see `docs/status.md`). Confirmed by a real invocation:

```
$ mix ggen_igniter.replay /tmp/nonexistent.jsonl
ggen_igniter.replay: could not read receipt file /tmp/nonexistent.jsonl: :enoent
$ echo $?
2
```

A real end-to-end run against a genuinely-produced receipt (exercising the
`"output state changed"`/`"ontology changed"` drift-detection categories
themselves) was **not** exercised this pass — receipt production currently
requires the now-broken `mix ggen_igniter.sync` path (see `docs/status.md`'s
`GgenIgniter.Lock` row) — so those two categories are UNVERIFIED (this pass)
specifically, distinct from the task's basic invocation/parsing behavior,
which is confirmed working above.

`mix ggen_igniter.replay <receipt_file> [--verify-only] [--json] [--manifest-dir DIR]`

## Purpose

Diagnostic task. Loads one real `GgenIgniter.Receipt` and recomputes real,
current hashes of the same inputs the receipt recorded, to answer: "has
anything this receipt depended on drifted since it was written?" This is a
read-only comparison — it never re-actuates anything, never writes to disk,
and never acquires `GgenIgniter.Lock`.

## `receipt_file`

Accepts either on-disk shape a receipt genuinely exists in:

- A date-partitioned `.jsonl` partition
  (`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`, matching
  `GgenIgniter.Receipt.path/2`'s real format) — the **last** line (most
  recent attempt in that partition) is replayed.
- A single JSON object file — one receipt's
  `GgenIgniter.Receipt.to_json_map/1` shape, decoded directly via
  `Jason.decode!/1` with no receipt-specific wrapper. This is the shape a
  caller gets by extracting one line out of a `.jsonl` partition into its
  own file.

Exits `2` (invalid invocation) if the file does not exist or does not parse
as either shape — never guesses at a receipt's content.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--verify-only` | boolean | *(only mode implemented so far)* | Performs only the read-only drift comparison described below. Reserved for a future re-actuation mode — that mode is not implemented; passing or omitting this flag today has no behavioral difference. |
| `--json` | boolean | `false` | Prints the machine-readable report (`%{"drift" => bool, "categories" => [...], "receipt_id" => ..., "recipe_key" => ..., "template_path" => ..., "template_current_hash" => ...}`) instead of human-readable lines. |
| `--manifest-dir DIR` | string | `File.cwd!()` | Where `.ggen_igniter/manifest.json` is read from, for resolving the receipt's `recipe_key` to a `pack_dir` (needed only for the "ontology changed" category — see below). |

## What real drift this can and cannot detect

`GgenIgniter.Receipt`'s on-disk schema records, per attempt: `recipe_key`
(`"<template_path>=><out_template>"`), `files` (the real output paths this
attempt touched), `pre_run_hash`/`post_run_hash` (real content digests over
exactly those `files`, via `GgenIgniter.Receipt.hash_files/1`), and a
free-form `metadata` map — on an `:alive` receipt written by
`GgenIgniter.Reactors.ReconcileReactor`, `metadata["graph_hash"]` is a real
`"sha256:" <> hex` digest of the ontology file that produced this run.

This task recomputes and compares exactly what the schema makes
recomputable, and reports each as its own category rather than a single
pass/fail:

- **"output state changed"** — `GgenIgniter.Receipt.hash_files/1` is re-run
  over the receipt's own `files` list, right now, and compared to the
  receipt's recorded `post_run_hash`. A mismatch means at least one output
  this recipe wrote has been edited (or deleted) since this receipt was
  recorded.
- **"ontology changed"** — only checked when the receipt's `recipe_key`
  resolves to a `GgenIgniter.Manifest` entry recording a `pack_dir`
  (`--manifest-dir`'s manifest) *and* the receipt's `metadata["graph_hash"]`
  is present. `<pack_dir>/ontology.ttl` (the `--pack` convention's fixed
  subpath — see `priv/ggen/CLAUDE.md`) is re-read and re-hashed with the
  same `"sha256:" <> hex` algorithm the reactor used, and compared to
  `graph_hash`.

`GgenIgniter.Receipt`'s schema does **not** record a standalone baseline
hash of the template file, the gate query, the pack directory as a whole,
the query engine's version string, or arbitrary run config — there is no
recorded value for this task to compare a recomputed hash against for those
categories, so this task never fabricates a comparison for them. When the
receipt's `recipe_key` names a template path, its current hash is still
reported (`--json`'s `template_path`/`template_current_hash` fields, or the
human line `template: <path> (no baseline recorded -- informational only,
current hash: ...)`) so a human has the value on hand, but it is never
counted as drift. If `GgenIgniter.Receipt`'s schema grows recorded baselines
for these categories, `detect_drift/2`-equivalent logic should be extended
to compare them for real rather than this task widening its guesses.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Receipt loaded and compared; no real drift detected. |
| `1` | Receipt loaded and compared; at least one real drift category found. |
| `2` | Invalid invocation — missing/unreadable/unparsable receipt file, no positional argument given, or an unrecognized flag. |

`System.halt/1` is used directly here (not `Mix.raise/1`), because the
task's contract is a real, distinguishable 0/1/2 process exit code a CI step
or another tool can branch on — `Mix.raise/1` always exits 1, which would
collapse "invalid invocation" and "real drift found" into the same code.

## Output format

Human-readable (default):

```
ggen_igniter.replay: receipt <id> (<recipe_key>)
template: <path> (no baseline recorded -- informational only, current hash: <hash>)
<category>: recorded=<hash> current=<hash>
```

or `no drift detected` in place of the category lines when `categories` is
empty.

`--json`:

```json
{
  "receipt_id": "...",
  "recipe_key": "...",
  "template_path": "...",
  "template_current_hash": "sha256:...",
  "drift": false,
  "categories": []
}
```

## Examples

```
mix ggen_igniter.replay .ggen_igniter/receipts/2026-08-27.jsonl
mix ggen_igniter.replay .ggen_igniter/receipts/2026-08-27.jsonl --json
mix ggen_igniter.replay one_receipt.json --manifest-dir /path/to/project --verify-only
```
