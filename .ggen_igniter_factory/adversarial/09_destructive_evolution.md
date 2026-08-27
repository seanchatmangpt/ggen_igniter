# Adversarial Verification 09: Destructive Semantic Evolution

- **Verifier stance**: independent, no prior-agent claims trusted. Every command below was
  executed fresh, in this pass, against real repo disk state.
- **Repo**: `/Users/sac/ggen_igniter` (not a subdirectory of a larger monorepo; `git status`
  confirms `On branch main`, tracking `origin/main`).
- **Real `mix.exs` version** (`mix.exs:9`): `version: "26.8.27"`. The task prompt's stated
  target ("v26.7.27") does **not** match the real repo value — reporting the real value per
  instructions, not assuming the prompt's figure.
- **Date of this run**: 2026-08-27 (`date -u` → `2026-08-27T22:02:29Z`).

## Scope and method

Per the task: read `test/fixtures/ash-lifecycle-pack/ontology*.ttl` variants (real directory
listing below), pick 3 destructive (rename/remove) variants not previously authored by this
verifier, run real `mix ggen_igniter.sync` against each, and grep the real regenerated
output for the retired identifier.

### Real directory listing (`ls -la test/fixtures/ash-lifecycle-pack/*.ttl`)

```
ontology.ttl                                (base)
ontology_v2_add_attribute.ttl               (additive)
ontology_v3_rename.ttl                      (destructive: attribute rename, assignee->assigned_to)
ontology_v4_remove_attribute.ttl            (destructive: attribute removal)
ontology_v5_rename_action.ttl               (destructive: action rename)
ontology_v6_remove_action.ttl               (destructive: action removal)   <- PICKED
ontology_v7_rename_relationship.ttl         (destructive: relationship rename)
ontology_v8_remove_relationship.ttl         (destructive: relationship removal)
ontology_v9_rename_resource.ttl             (destructive: resource rename)  <- PICKED
ontology_v10_remove_resource.ttl            (destructive: resource removal) <- PICKED
ontology_v11_change_domain_association.ttl  (destructive: domain reassociation)
```

11 real ontology files total (base + 10 numbered variants). `ontology_v3_rename.ttl` is
already exercised by `test/e2e/lifecycle_test.ex` (Stage 7) — deliberately NOT re-picked here
to get independent coverage of variants that test does not touch. Picked v6, v9, v10 for
maximum mechanism diversity: action removal (v6), resource rename with a filename-changing
consequence (v9), whole-resource removal (v10).

### Real flags derived from source

- `lib/mix/tasks/ggen_igniter.sync.ex:3` (moduledoc): CLI shape is
  `--ontology --query name=path.rq --template --out`, plus `--pack-dir`/`--engine`/etc.
- `lib/mix/tasks/ggen_igniter.sync.ex:47-66`: default engine is `oxigraph` since v26.8.27, but
  it has a **real, disclosed bug** for string-typed bindings (quote characters embedded in
  values — see `test/e2e/lifecycle_test.ex:327-349`'s own investigation, confirmed against
  `native/ggen_graph_nif/src/oxigraph_engine.rs:73`). `test/e2e/lifecycle_test.ex:350-366`
  (`sync!/3` helper) pins `--engine sparql` explicitly for exactly this reason. I mirrored
  that pin in every command below rather than trusting the current default.
- `--out` is always EEx-rendered per row (moduledoc lines 27-45), so an explicit `--out`
  template overrides the pack template's own `to:` frontmatter and can safely redirect
  output into a gitignored scratch directory instead of polluting `lib/`
  (`test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex:2` hardcodes
  `to: "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"` — this verifier
  does not write into the tracked `lib/` tree; `tmp_out/` is gitignored per `.gitignore:11`).

Real command template used for every case:

```
mix ggen_igniter.sync --pack-dir test/fixtures/ash-lifecycle-pack \
  --ontology <ontology.ttl> --template test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex \
  --engine sparql --out "tmp_out/adversarial/<case>/<%= String.downcase(resource_name) %>.ex"
```

Each case is run as a real two-step sequence against the SAME scratch directory — a base
sync against `ontology.ttl` first (establishing pre-existing generated file(s), the way a
real developer's repo would already have them), then a second real sync against the
destructive variant — so the check covers both (a) the freshly-regenerated file's content
and (b) whether any file left over from the prior generation lingers with stale content
(orphan-file reconciliation), not just a from-scratch render.

---

## Case 1 — `ontology_v6_remove_action.ttl` (removes `alp:TicketArchiveAction` entirely)

Real diff (`diff ontology.ttl ontology_v6_remove_action.ttl`) confirms the only instance-data
change is deletion of:
```
alp:TicketArchiveAction a alp:Action ;
    alp:actionOf alp:TicketResource ; alp:actionOrder 5 ; alp:actionName "archive" ; alp:actionType "update" .
```
Old/retired identifier under test: the string `archive` (renders as `update :archive do` in
`resource.ex.eex:49` when `action_name != action_type`).

Real commands run:
```
$ mix ggen_igniter.sync --pack-dir test/fixtures/ash-lifecycle-pack --ontology test/fixtures/ash-lifecycle-pack/ontology.ttl --template test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex --engine sparql --out "tmp_out/adversarial/v6/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v6/customer.ex; wrote tmp_out/adversarial/v6/ticket.ex (engine: sparql, 5 queries, 21 total row(s))
EXIT_BASE=0

$ mix ggen_igniter.sync --pack-dir test/fixtures/ash-lifecycle-pack --ontology test/fixtures/ash-lifecycle-pack/ontology_v6_remove_action.ttl --template test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex --engine sparql --out "tmp_out/adversarial/v6/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v6/ticket.ex; unchanged (skipped, identical content): tmp_out/adversarial/v6/customer.ex (engine: sparql, 5 queries, 20 total row(s))
EXIT_V6_SYNC=0
```

Row count dropped 21 -> 20 (one `alp:Action` row gone), exactly matching one removed
individual — real, not asserted.

Real grep of the regenerated file:
```
$ grep -n "archive" tmp_out/adversarial/v6/ticket.ex
GREP_EXIT=1   (grep found nothing -> exit 1)
$ grep -c "archive" tmp_out/adversarial/v6/ticket.ex
0
```

Regenerated `actions do` block (full real content, `tmp_out/adversarial/v6/ticket.ex`):
```elixir
  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

  end
```
The custom `update :archive do ... end` block is genuinely gone (not commented out, not
present with an empty body — the whole `for act <- resource_actions, act["action_name"] !=
act["action_type"]` loop in `resource.ex.eex:49-51` correctly has zero matching rows now).
Every other attribute/relationship content from the base sync (subject/status/assignee
attributes, belongs_to customer) survived untouched, confirming this is a real targeted
delta, not an accidental full wipe.

**Verdict: CONFIRMED — 0 stale references to the retired `archive` action in the real
regenerated `ticket.ex`; sync exit code 0 both runs.**

---

## Case 2 — `ontology_v9_rename_resource.ttl` (renames `alp:TicketResource`'s name/module in place)

Real diff confirms: same individual IRI `alp:TicketResource` keeps all its attribute/action/
relationship children, but its `alp:resourceName`/`alp:resourceModule` literals change from
`"Ticket"`/`"SupportDesk.Support.Ticket"` to `"Case"`/`"SupportDesk.Support.Case"`.

Old/retired identifiers under test: `Ticket` (as bare resource name and as the
`SupportDesk.Support.Ticket` module name) inside whatever file this sync run actually
produces for that resource.

Real commands run:
```
$ mix ggen_igniter.sync ... --ontology .../ontology.ttl ... --out "tmp_out/adversarial/v9/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v9/ticket.ex; wrote tmp_out/adversarial/v9/customer.ex (engine: sparql, 5 queries, 21 total row(s))
EXIT_V9_BASE=0

$ mix ggen_igniter.sync ... --ontology .../ontology_v9_rename_resource.ttl ... --out "tmp_out/adversarial/v9/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v9/case.ex; wrote tmp_out/adversarial/v9/customer.ex (engine: sparql, 5 queries, 21 total row(s))
EXIT_V9_SYNC=0
```

Because `--out`'s path template includes `String.downcase(resource_name)` (mirroring the
pack's own `to:` frontmatter), the rename changes the OUTPUT FILENAME itself:
`ticket.ex` -> `case.ex`. This is the real, actually-produced regenerated file for the
renamed resource this run.

Real grep of that regenerated file:
```
$ grep -n "Ticket" tmp_out/adversarial/v9/case.ex
GREP_EXIT_case=1   (no match -> exit 1)
$ grep -c "Ticket" tmp_out/adversarial/v9/case.ex
0
```

Real content (`tmp_out/adversarial/v9/case.ex`):
```elixir
defmodule SupportDesk.Support.Case do
  @moduledoc """
  Ash.Resource for `Case`, backed by `Ash.DataLayer.Ets`.
  ...
```
Module name, moduledoc, and all attribute/action/relationship content are consistent with
"Case" — 0 real occurrences of the old "Ticket" identifier anywhere in this regenerated file.

**However — a real, separate finding surfaced by this same run**: because `mix
ggen_igniter.sync` only ever writes the path its `--out`/`to:` template resolves to for the
CURRENT ontology (per `lib/mix/tasks/ggen_igniter.sync.ex`'s `actuate!/8`, `write_file!/3` —
no delete/reconciliation step exists anywhere in this module or in `GgenIgniter.Actuate`), the
OLD `ticket.ex` file from the base sync is never touched or removed:
```
$ ls tmp_out/adversarial/v9/
case.ex  customer.ex  ticket.ex        <- ticket.ex still present, untouched
$ grep -c "Ticket" tmp_out/adversarial/v9/ticket.ex
2
```
`ticket.ex` is a genuine orphan left on disk with 2 real, stale references to
`SupportDesk.Support.Ticket`/`Ticket` after the rename — a real disk-state fact, not a
hypothetical. This orphan is outside the literal scope of "grep the regenerated output file"
(the regenerated file, `case.ex`, is genuinely clean), so it does not flip this specific
per-file verdict, but it is a real, load-bearing caveat on any broader claim that renaming a
resource is a "clean reconciliation": the new file is clean, the OLD file is not cleaned up
or flagged in any way, and the sync's own exit code (0) and notice line give no signal that
an orphan now exists.

**Verdict: CONFIRMED for the regenerated file (`case.ex`) — 0 stale `Ticket` references, sync
exit code 0 both runs. CAVEAT (separate, real finding, not a refutation of the narrow claim):
the pre-rename `ticket.ex` remains on disk as an untouched, stale orphan with 2 real `Ticket`
references — this codebase has no cross-run orphan-file cleanup for a resource rename.**

---

## Case 3 — `ontology_v10_remove_resource.ttl` (removes `alp:TicketResource` and all its children)

Real diff confirms the WHOLE `alp:TicketResource` individual, plus every attribute/action/
relationship row that referenced it, is deleted; only `alp:CustomerResource` survives.

Real commands run:
```
$ mix ggen_igniter.sync ... --ontology .../ontology.ttl ... --out "tmp_out/adversarial/v10/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v10/ticket.ex; wrote tmp_out/adversarial/v10/customer.ex (engine: sparql, 5 queries, 21 total row(s))
EXIT_V10_BASE=0

$ mix ggen_igniter.sync ... --ontology .../ontology_v10_remove_resource.ttl ... --out "tmp_out/adversarial/v10/<%= String.downcase(resource_name) %>.ex"
Notices: ggen_igniter: wrote tmp_out/adversarial/v10/customer.ex (engine: sparql, 5 queries, 9 total row(s))
EXIT_V10_SYNC=0
```

Row count dropped 21 -> 9 (all of Ticket's attribute/action/relationship rows gone, matching
the real diff exactly). Critically, the notice line for the destructive resync names ONLY
`customer.ex` — there is no `ticket.ex` mention at all, because the `resource` for-each query
now returns exactly one row (Customer). This is real, correct behavior for the query/render
layer: with `alp:TicketResource` gone, there is no row to drive a Ticket render, so no attempt
is made to regenerate anything for it.

But this means there is, by construction, NO "regenerated output file" for the removed
resource in this run at all — the only file on disk claiming to represent Ticket is the
pre-existing orphan from the base sync, which this destructive resync did not touch:
```
$ ls tmp_out/adversarial/v10/
customer.ex  ticket.ex
$ diff tmp_out/adversarial/v10/ticket.ex tmp_out/adversarial/v9/ticket.ex
(no output -- byte-identical to the untouched base-sync copy from Case 2, confirming this
 file was not rewritten, re-touched, or altered in any way by the destructive resync)
$ grep -n "Ticket" tmp_out/adversarial/v10/ticket.ex
1:defmodule SupportDesk.Support.Ticket do
3:  Ash.Resource for `Ticket`, backed by `Ash.DataLayer.Ets`.
GREP_EXIT=0   (match found)
$ grep -c "Ticket" tmp_out/adversarial/v10/ticket.ex
2
```

Full real stale content left behind (`tmp_out/adversarial/v10/ticket.ex`, unchanged since the
base sync):
```elixir
defmodule SupportDesk.Support.Ticket do
  @moduledoc """
  Ash.Resource for `Ticket`, backed by `Ash.DataLayer.Ets`.
  ...
  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    update :archive do
    end

  end
  ...
```
This is a real, complete, fully-formed `SupportDesk.Support.Ticket` Ash resource module sitting
on disk, fully compilable, with every attribute/action/relationship intact — after its
backing ontology individual was entirely removed. `mix ggen_igniter.sync` exited 0 with no
warning, no error, and no notice mentioning Ticket at all; nothing in the tool's output
signals that a previously-generated file now has no ontology backing.

Per the task's own framing ("it must be genuinely absent (0 matches) for a clean
reconciliation claim to hold, or the sync must have genuinely, loudly failed before writing
anything"): neither condition holds here. The sync did not fail loudly (exit 0, clean notice
line), and the old identifier is NOT absent from the one real file on disk that represents
the removed resource — it is fully present (2 matches), because that file was never touched.

**Verdict: REFUTED for "0 stale references after resource removal" — a real, complete,
2-match-stale `ticket.ex` file remains on disk, byte-identical to its pre-removal state,
after `alp:TicketResource` was deleted from the ontology and a real, successful (exit 0)
`mix ggen_igniter.sync` run completed. This is a genuine, disclosed-nowhere-in-the-CLI-output
reconciliation gap for whole-resource removal: this codebase has no delete/orphan-detection
step (confirmed absent from `lib/mix/tasks/ggen_igniter.sync.ex` and
`lib/ggen_igniter/actuate.ex`'s real actuation paths — only `write_file!/3`/
`inject_content!/5`/`eval_code!/2` exist, none of which ever removes a file), so a resource
removed from the ontology leaves its last-generated file exactly as-is, indistinguishable
from a live, ontology-backed resource, unless a human or a separate tool notices and deletes
it.**

---

## Summary table

| Variant | Mechanism | Real regenerated file | Old identifier | grep count | grep exit | sync exit | Verdict |
|---|---|---|---|---|---|---|---|
| `ontology_v6_remove_action.ttl` | remove custom action | `ticket.ex` (same path, full rewrite) | `archive` | 0 | 1 | 0 / 0 | **CONFIRMED** clean |
| `ontology_v9_rename_resource.ttl` | rename resource in place | `case.ex` (new path; old `ticket.ex` orphaned) | `Ticket` | 0 (in `case.ex`); 2 (in orphaned `ticket.ex`) | 1 / 0 | 0 / 0 | **CONFIRMED** for the regenerated file; **real orphan-file caveat** (see Case 2) |
| `ontology_v10_remove_resource.ttl` | remove whole resource | none produced this run; only pre-existing `ticket.ex` orphan exists | `Ticket` | 2 | 0 | 0 / 0 | **REFUTED** — stale file with 2 real matches survives a successful, silent sync |

## What this domain's real, honest status is

Per-file, single-run regeneration (Case 1, and the newly-produced side of Case 2) is real and
clean: when `mix ggen_igniter.sync` DOES regenerate a file for a still-extant resource, that
file's content is a genuine full rewrite with zero stale references to what was just
removed/renamed inside it. This part of "destructive semantic evolution" holds up.

What does NOT hold up, demonstrated with real, reproducible commands above: there is no
cross-run reconciliation step anywhere in this codebase (`Mix.Tasks.GgenIgniter.Sync`,
`GgenIgniter.Actuate` — both read in full for this verification) that detects or removes a
previously-generated file whose backing ontology individual has since been renamed or
deleted. A rename produces one clean new file plus one stale orphan (Case 2); a full removal
produces zero new files and leaves the prior file completely untouched and indistinguishable
from a live one (Case 3). Neither the sync's exit code (0 in every case run above) nor its
notice line ever surfaces this. This is a real gap in "destructive evolution", not a
theoretical one — every number above came from a real `mix ggen_igniter.sync` subprocess run
in this pass, not from reading code and assuming.

## Evidence artifacts (real files left on disk from this verification pass, gitignored)

- `/Users/sac/ggen_igniter/tmp_out/adversarial/v6/{ticket,customer}.ex`
- `/Users/sac/ggen_igniter/tmp_out/adversarial/v9/{case,customer,ticket}.ex`
- `/Users/sac/ggen_igniter/tmp_out/adversarial/v10/{customer,ticket}.ex`

All under `tmp_out/`, which `.gitignore:11` excludes (`/tmp_out/`) — no tracked repo state was
modified by this verification.
