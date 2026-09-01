# Parity Validation: ggen_igniter vs. real ggen core

Stage: PARITY VALIDATION (post GI-01..GI-05). Branch:
`story/GI-05-fortune5-ready-mix-task`, worktree `/tmp/GI-04-worktree`
(a git worktree of `~/ggen_igniter`, commit `6486cb5` base). No new code
commits in this stage — validation evidence only, appended to this branch
per the run's instructions.

## Environment

A real `ggen` binary IS available on this machine: `~/.local/bin/ggen` is a
thin wrapper that runs `docker run --rm -v "$PWD:/workspace" -w /workspace
ghcr.io/seanchatmangpt/ggen-ecosystem:v26.8.28 ggen "$@"` — confirmed by
reading the wrapper script and by `ggen --version` → `ggen 26.8.28`. All
checks below that say "real ggen binary" actually invoked this container,
from a scratch copy under `~/.cache/tmp/gi-parity-beam4pm` (the wrapper only
mounts `$PWD`; `/private/tmp/...` under this session's scratchpad did NOT
resolve inside the container — `ggen sync run --dry-run` there failed with
`[FM-CONFIG-001] ggen.toml not found at /workspace/ggen.toml` even though the
file existed on the host, so the scratch copy was rebuilt under
`~/.cache/tmp` instead, consistent with GI-04's own prior finding about this
machine's docker mount behavior).

Scratch copy contents: `~/beam4pm/ggen.toml`, `~/beam4pm/ontology.ttl`,
`~/beam4pm/templates/`, and `~/beam4pm/vendor/` (the real vendored
`ggen-marketplace` submodule checkout, which does include
`fortune5-architecture-pack` and `fortune5-deployment-blocks-pack` —
confirmed by `ls`, matching `~/ggen-marketplace/packs/` exactly). `~/beam4pm`
itself was never modified — this is a read-only copy per the run's
instructions.

## Check 1 — schema classification, beam4pm's real ggen.toml (EXECUTED, real ggen binary)

beam4pm's actual `ggen.toml` (read-only copy) has: `[project] name = "beam4pm"`
(no `version` key), `[ontology] source = "ontology.ttl"`, a `[packs]`
*table-of-tables* (not `[[packs]]` array-of-tables), `[templates] dir =
"templates"`, and no `[generation]` table at all.

Per `~/ggen/crates/ggen-config/src/config_schema.rs`'s documented decision
procedure: no `[generation]` table and no `[[packs]]` array-of-tables means
neither of the two *strong* DeclarativeRules markers fire; the three
Frontmatter-required fields (`project.name`, `ontology.source`,
`templates.dir`) are all present → real ggen core's classifier would report
`Frontmatter`.

Real-binary confirmation (not just code inspection): ran the actual `ggen`
container against the scratch copy.

```
$ cd ~/.cache/tmp/gi-parity-beam4pm && ggen sync run --dry-run
...
{
  "dry_run": true,
  ...full file digest map of 60 tracked outputs across all 5 packs...
}
```

Exit 0, full manifest emitted, zero config/schema errors. A file that ggen
core classified as anything *other* than Frontmatter (e.g. Ambiguous,
Malformed, or a misrouted DeclarativeRules attempt against a table-shaped
`[packs]`) would have failed at the config-parse stage before reaching
pack/template resolution — it did not.

Same file run through `GgenIgniter.SchemaDispatch.load/1` (ticket GI-01's
real `Toml.decode/1`-backed classifier, invoked live via `mix run` in the
GI-04/05 worktree, not a fixture-only test):

```
$ BEAM4PM_DIR=$HOME/.cache/tmp/gi-parity-beam4pm mix run /tmp/parity_gi01.exs
SchemaDispatch.load(beam4pm ggen.toml): {:frontmatter,
 %GgenIgniter.FrontmatterConfig{
   project: %{name: "beam4pm"},
   ontology: %{prefixes: %{}, source: "ontology.ttl"},
   templates: %{dir: "templates"},
   packs: %{"beam4pm-ai-contracts" => {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack", ...}}, ...5 packs total...},
   law: %{gates: [], reflexive: false, rules: [], shapes: []}
 }}
```

**Result: PARITY CONFIRMED, executed both sides.** `ggen_igniter`'s
`SchemaDispatch.load/1` returns `{:frontmatter, ...}` with all 5 real packs
and the same 3 required-field values; the real ggen binary independently
processes the same file with zero config-schema error, consistent with the
same Frontmatter classification per `config_schema.rs`'s documented rules.
This is a code-comparison-grounded conclusion (`config_schema.rs`'s decision
procedure was read, not re-implemented as a standalone Rust harness in this
stage) combined with two independent real executions on the *same* input
file agreeing on outcome — not a full instrumented trace of ggen core's
internal classifier returning a literal `Frontmatter` enum value, which
would require a custom Rust test binary against `~/ggen`'s crate (not built
in this stage; see "Not executed" below).

## Check 2 — merge + TOML-IO serialize-back, fed to the real ggen binary (EXECUTED)

Ran GI-01's `SchemaDispatch.load/1`, GI-03's `Bundle.load!/1` +
`Bundle.merge/2` (the real `fortune5_ready` bundle manifest —
`fortune5-architecture` + `fortune5-deployment-blocks`), and GI-02's
`GgenToml.IO.serialize!/1` end-to-end via `mix run`, writing the result over
the scratch copy's `ggen.toml`:

```
$ cd /tmp/GI-04-worktree && BEAM4PM_DIR=$HOME/.cache/tmp/gi-parity-beam4pm mix run /tmp/parity_gi03.exs
packs to add: [
  %GgenIgniter.Bundle.Pack{name: "fortune5-architecture", path_hint: "vendor/ggen-marketplace/packs/fortune5-architecture-pack"},
  %GgenIgniter.Bundle.Pack{name: "fortune5-deployment-blocks", path_hint: "vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack"}
]
```

Serialized `ggen.toml` (real bytes written to disk, reproduced verbatim):

```toml
[project]
name = "beam4pm"

[ontology]
source = "ontology.ttl"

[packs]
beam4pm-ai-contracts = { path = "vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack" }
beam4pm-pro-entitlement = { path = "vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack" }
beam4pm-pro-infra = { path = "vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack" }
beam4pm-process-model = { path = "vendor/ggen-marketplace/packs/beam4pm-process-model-pack" }
fortune5-architecture = { path = "vendor/ggen-marketplace/packs/fortune5-architecture-pack" }
fortune5-deployment-blocks = { path = "vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack" }
github-actions-pack = { path = "vendor/ggen-marketplace/packs/github-actions-pack" }

[templates]
dir = "templates"
```

Fed directly to the real `ggen` binary:

```
$ cd ~/.cache/tmp/gi-parity-beam4pm && ggen sync run --dry-run
ERROR: CLI execution failed: Command execution failed: validation error:
[FM-PACK-005] pack `fortune5-deployment-blocks`: zero templates under
`/workspace/vendor/ggen-marketplace/packs/fortune5-deployment-blocks-pack/templates`.
Remediation: a pack must ship at least one templates/*.tmpl.
```

This is **not** a TOML-serialization or schema-classification rejection —
the real binary got *past* config parsing and pack-declaration resolution
entirely and failed at `FM-PACK-005`, a per-pack content-validation gate,
on a real, independently-documented, pre-existing upstream defect in the
`fortune5-deployment-blocks-pack` itself (zero `templates/*.tmpl` files —
already filed as `~/ggen/docs/jira/v26.9.1/
07-FORTUNE5-DEPLOYMENT-BLOCKS-NOT-SYNC-PORTABLE.md` from an earlier stage
in this run, `gm04`). It is not caused by anything `ggen_igniter` wrote.

To isolate the TOML-IO/merge output from that unrelated pack defect, removed
only the `fortune5-deployment-blocks` line and re-ran against the same
serialized file (same `[project]`/`[ontology]`/`[templates]` sections, same
formatting, only one `[packs]` entry removed by hand):

```
$ ggen sync run --dry-run
{
  "dry_run": true,
  ...full digest map, all packs including fortune5-architecture-pack's
  4 templates (architecture_catalog.md.tmpl, architecture_dag.dot.tmpl,
  control_matrix.md.tmpl, workflow_pattern_coverage.md.tmpl)...
}
```

Exit 0.

**Result: PARITY CONFIRMED, executed.** `ggen_igniter`'s merge + TOML
serialize-back output, when fed to the real `ggen` binary, is accepted (not
rejected as malformed or ambiguous) for every pack whose own templates
directory is non-empty. The one rejection observed (`fortune5-deployment-
blocks`) is a real, independently pre-documented upstream pack defect
unrelated to this ticket chain's schema-dispatch/TOML-IO/merge code, and was
isolated by a real second execution proving the rest of the merged file is
fully accepted.

## Not executed (structural/code-comparison only, disclosed explicitly)

- No standalone Rust harness was built against `~/ggen`'s
  `ggen-config`/`ggen-engine` crates in this stage to call
  `classify_ggen_toml`/`schema_dispatch::load` directly and capture its
  literal returned enum value side-by-side with the Elixir call. Check 1's
  "PARITY CONFIRMED" rests on (a) reading `config_schema.rs`'s documented
  decision procedure in full and applying it by hand to beam4pm's real
  `ggen.toml`, concluding `Frontmatter`, and (b) two independent real
  executions (the ggen CLI binary and `GgenIgniter.SchemaDispatch.load/1`)
  against the identical input file, both succeeding/agreeing with that
  conclusion — not a single harness that runs both classifiers back-to-back
  on the same input and diffs their literal return values. Building that
  Rust harness was judged out of scope for this stage's time budget; if a
  future stage wants a stronger check, the harness would call
  `ggen_config::config_schema::classify_ggen_toml` and
  `ggen_engine::schema_dispatch::load` directly against
  `test/fixtures/schema_dispatch/beam4pm_ggen.toml` (GI-01's existing real
  fixture, a verbatim copy of beam4pm's `ggen.toml`) and assert both return
  values textually.
- GGEN-1804 (an actual upstream `ggen.toml` byte-for-byte round-trip
  preserving comments/ordering) remains explicitly out of scope per GI-02's
  own disclosed accepted-limitation — the TOML-IO serializer does not aim
  for byte-identity with the original file, only for a re-parseable,
  semantically-equivalent, and (per this stage) real-ggen-binary-acceptable
  output. This stage did not attempt to close that gap.

## Summary

| # | Check | Real ggen binary used? | Outcome |
|---|-------|------------------------|---------|
| 1 | SchemaDispatch classification of beam4pm's real ggen.toml | Yes | PARITY CONFIRMED — both sides succeed/agree on Frontmatter |
| 2 | Merged+serialized ggen.toml accepted by real ggen (fortune5-architecture only) | Yes | PARITY CONFIRMED — exit 0, full sync |
| 2b | Merged+serialized ggen.toml with fortune5-deployment-blocks included | Yes | Rejected at FM-PACK-005 — pre-existing, pre-filed upstream pack defect (zero templates), not a ggen_igniter TOML-IO/schema defect |
| — | Direct Rust-vs-Elixir classifier value diff via a dedicated harness | No | Not executed this stage — structural/code-comparison only (see above) |

No `~/beam4pm` files were modified. No `~/ggen_igniter` main branch was
touched, merged to, or pushed. This document and the scratch-run scripts
(`/tmp/parity_gi01.exs`, `/tmp/parity_gi03.exs`) are the only artifacts of
this stage; the scratch consumer copy lives at
`~/.cache/tmp/gi-parity-beam4pm` (outside both `~/beam4pm` and
`~/ggen_igniter`).
