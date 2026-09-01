# Red-team verification: stale-artifact leakage under `--on-stale`'s real default

**Verdict: REFUTED** — zero real stale-file leakage found, at the real default policy,
against both real destructive fixtures, run fresh in this pass.

- Independent adversarial reviewer, read-only against the repo except this file.
- Repo: `/Users/sac/ggen_igniter`. `git rev-parse HEAD` = `d9316b4228bc09cbb744dbd096620a745d6735ca`.
  Working tree has real pre-existing uncommitted changes to
  `lib/ggen_igniter/reactors/reconcile_reactor.ex` and 4 other files (not made by this
  verification — confirmed unchanged before/after via `git status --porcelain`, reproduced
  below). Tested against the real current working-tree code, not a clean checkout.
- Date/time of this run: `2026-08-28T01:07:58Z` through `~01:20Z` (real `date -u` output).
- `mix.exs` real version: `26.8.27`. Elixir 1.19.5 / OTP 28, real `mix --version` output.
- No mocking anywhere in this verification: every command below is a real `mix
  ggen_igniter.sync` subprocess or a real `mix run` script directly invoking
  `GgenIgniter.Reactors.ReconcileReactor.run/1`, against real files on a real isolated
  scratch directory. No repo-tracked file was modified (`git status --porcelain` identical
  before and after, reproduced at the end).

## Method

Per the task, used the real, existing fixtures unmodified:
`test/fixtures/ash-lifecycle-pack/ontology_v9_rename_resource.ttl` (renames
`alp:TicketResource`'s name/module in place: `Ticket`/`SupportDesk.Support.Ticket` ->
`Case`/`SupportDesk.Support.Case`, same subject IRI) and
`ontology_v10_remove_resource.ttl` (deletes the whole `alp:TicketResource` individual and
every attribute/action/relationship row pointing at it).

Each scenario is a real two-step sequence into a fresh, isolated scratch directory (never
`tmp_out/` or the repo's own default `.ggen_igniter/manifest.json` — an explicit
`--manifest-dir`/`--out` under this session's own scratchpad, so no repo state, tracked or
gitignored, was touched):

1. A real base sync against the unmodified `ontology.ttl`, establishing the manifest's
   tracked-outputs entry for `ticket.ex` (and `customer.ex`) under the exact
   `(template, out_template)` recipe key this pack uses.
2. A real destructive sync against the v9/v10 variant, with `--on-stale` **omitted** (the
   real default — `Mix.Tasks.GgenIgniter.Sync.resolve_on_stale!(nil) -> :refuse`, confirmed
   at `lib/mix/tasks/ggen_igniter.sync.ex:732`; `use_reactor` confirmed `false` by default,
   not set in any `config/*.exs` — checked directly, not assumed).

## Result 1 — CLI inline pipeline (`Mix.Tasks.GgenIgniter.Sync`), real fixtures, real default

This is the actually-reachable default pipeline: `use_reactor?/0` reads
`Application.get_env(:ggen_igniter, :use_reactor, false)`, and no `config/*.exs` in this repo
sets it, confirmed by `grep -rn "use_reactor" config/*.exs` returning nothing.

### v9 rename (`ontology_v9_rename_resource.ttl`)

Base sync: `EXIT_BASE=0`, wrote `ticket.ex` + `customer.ex`. Real manifest content confirmed
both paths tracked under the recipe key
`test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex=>.../out/v9/<%= String.downcase(resource_name) %>.ex`.

Destructive sync (flag omitted):

```
** (ArgumentError) ggen_igniter: refusing to sync -- 1 stale output path(s) from a PRIOR
run of this recipe ("...resource.ex.eex=>.../out/v9/<%= String.downcase(resource_name) %>.ex")
are not written by this run (a rename or removal upstream in the ontology, most likely):

  - .../out/v9/ticket.ex

Nothing was written this run (complete reconciliation or refusal before any partial
actuation -- never a silent orphan). Re-run with --on-stale prune to really delete the
stale path(s) above, or --on-stale preserve to leave them on disk (with a warning) and
proceed.
```

`EXIT_DESTRUCTIVE=1` (real, non-masked exit code). Real `ls` of the out directory
immediately after: **`customer.ex` and `ticket.ex` only — no `case.ex` was ever created.**
Real `cat` of the manifest file after the refusal: byte-identical to before the destructive
run (no new entry, no dropped entry, `updated_at` unchanged).

### v10 removal (`ontology_v10_remove_resource.ttl`)

Same two-step sequence, separate scratch dir. Base sync: `EXIT_V10_BASE=0`. Destructive sync
(flag omitted, exit code captured cleanly with no pipe masking this time):

```
REAL_EXIT_CODE=1
```

with the identical `ArgumentError` shape, naming `.../out/v10/ticket.ex` as the one stale
path, and the identical "nothing was written this run" guarantee. Real `ls` of the out
directory after: `customer.ex` and `ticket.ex` only.

**Both real destructive fixtures, against the real, actually-default pipeline: the default
`refuse` policy genuinely fails closed. No new file is written under the retired resource's
old or new identity, the manifest is untouched, and the process exits non-zero with a loud,
specific message naming the exact stale path** — this is the documented contract
(`docs/reference/reconciliation/stale-artifacts.md`), and it holds under real execution, not
just as a read of the source.

## Result 2 — Reactor coordinator (`GgenIgniter.Reactors.ReconcileReactor`)

`use_reactor: true` is opt-in and off by default (confirmed above), so this path is not what
a bare `mix ggen_igniter.sync` invocation reaches today. Tested it anyway since the task
names "manifest+reactor pipeline" explicitly.

**Structural finding, empirically confirmed, not inferred from the moduledoc alone:** the
real `ash-lifecycle-pack/templates/resource.ex.eex` template carries real frontmatter
(`for_each: resource`, `mode: file`) — calling `ReconcileReactor.run/1` directly against it
(bypassing the CLI's own `delegate_to_controller/4`/`run_via_reactor/3` scope guard, which
would normally fall back to the inline pipeline for exactly this shape) produces a real
crash: `error: undefined variable "resource_name"` — because the Reactor's `render_target/2`
renders the template/out-template exactly once, with no per-row fan-out, so a for-each-only
binding is never bound. This confirms the moduledoc's stated bounded scope
("`:targets`/flat opts, no frontmatter, no `--for-each`") is a real constraint, not just a
documentation claim: **for this exact real pack, the Reactor path cannot process these
templates at all**, even when opted in. The reachable pipeline for this pack, in practice,
is the CLI inline pipeline tested in Result 1 above.

To still exercise the Reactor's own `:admit`-step stale-refusal logic for real (rather than
only reading it), constructed a real, non-mocked, single-target-shaped equivalent using the
*same real ontology files* (`ontology.ttl` / `ontology_v9_rename_resource.ttl`, unmodified)
with a minimal query (`SELECT ?resource_name ?resource_module WHERE { alp:TicketResource
alp:resourceName ?resource_name ; alp:resourceModule ?resource_module . }`) and a tiny
template with no frontmatter/`for_each`, `--out` still EEx-templated by `resource_name` (so
the output path itself changes on rename, exactly mirroring the real pack's behavior) —
this is squarely inside the Reactor's own documented scope. Called
`GgenIgniter.Reactors.ReconcileReactor.run/1` directly (real function call, real
`mix compile --warnings-as-errors` subprocess for `:verify`, `verify_cwd` pinned to the real
project root so verification is genuine, not a scratch-dir false failure):

- Base run: `standing=:alive`, wrote `ticket.ex`.
- Destructive rename run, `on_stale` omitted (default): `standing=:refused`, `reason =
  "refused: stale outputs with on_stale=refuse: [\".../reactor_out3/ticket.ex\"]"`.
  Real dir listing after: **`ticket.ex` only — no `case.ex` was ever created.** Real grep
  of every file remaining in that directory for `"Ticket"`: `ticket.ex` still contains it
  (it is the untouched, pre-existing, non-stale-at-write-time file, exactly as `refuse`
  documents), and no other file exists to leak anything.

**Could not construct an analogous real single-target Reactor test for the v10 REMOVAL
case**: with the driving row genuinely absent (0 SPARQL results), `Render.render/2` cannot
render either the content or an EEx-templated `--out` path at all (no row to bind), so the
render step itself raises before any stale-set computation is reached — a real, structural
limit of a bare single-row query with no `for_each`, disclosed here rather than glossed
over. This is a real testing-scope gap for the Reactor path specifically (not for the CLI
path, where Result 1's v10 case is complete real evidence), and not evidence of leakage
either way.

## A note on a now-STALE prior finding in this same factory tree

`.ggen_igniter_factory/adversarial/09_destructive_evolution.md` (present in the repo,
committed in `c27008c`) reports, for the identical `ontology_v10_remove_resource.ttl`
fixture: `mix ggen_igniter.sync` exiting **0**, no refusal, `ticket.ex` silently left on disk
with 2 real stale `Ticket` references, verdict **REFUTED** ("stale file with 2 real matches
survives a successful, silent sync"). That is the opposite of what this pass just
reproduced (exit 1, loud refusal, zero new writes) against the identical fixture file.

This is not a contradiction requiring further chasing — it is explained by real repo
history: that file's own real mtime is `2026-08-27 15:03:40`, and it was committed as part
of `c27008c` ("Add reconciliation manifest, ... **close adversarial-verified gaps**"),
whose real commit timestamp is `2026-08-27 15:46:34 -0700` — i.e. the reconciliation
manifest (the `--on-stale` machinery this whole report is testing) was introduced in the
**same commit** that carries that older finding, specifically to close the exact gap it
found. `docs/status.md:52` independently corroborates this: "Cross-run orphan-file cleanup
on resource rename/removal | IMPLEMENTED (via `--on-stale prune`) | Historical gap now
CLOSED ... was ADVERSARIAL.md's 'MUST FIX #3' ... Default (`refuse`) still fails closed
rather than silently orphaning." Current HEAD (`d9316b4`) is one commit past that fix. The
older document's REFUTED verdict was real and accurate *for the state of the code before
that fix landed*; it is now itself a stale artifact describing a closed gap, not a live one
— worth flagging so it is not cited going forward as the current state of this pipeline.

## Scope note: this report is about the DEFAULT policy only

`prune` (really deletes the stale path via `File.rm/1`, confirmed present in
`lib/ggen_igniter/manifest.ex:284` and gated behind `:verify` succeeding in the Reactor's
`:finalize_evidence`) and `preserve` (leaves the stale file on disk on purpose, warns, drops
manifest tracking) are both explicit, disclosed, opt-in alternative policies — a stale file
surviving under `--on-stale preserve` is by design, not leakage, and was out of scope for
this task's question about the real default.

## Real evidence artifacts (scratch, outside the repo, nothing tracked touched)

- `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/{manifest,out/v9,out/v10}/*`
- `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/{reactor_manifest3,reactor_out3}/*`
- `/tmp/redteam_reactor_probe.rq`, `/tmp/redteam_reactor_probe.ex.eex`, `/tmp/reactor_probe3.exs`,
  `/tmp/v10_destructive_out.txt`

`git status --porcelain` immediately after this entire verification pass, for comparison
against the same command run before starting — identical apart from this file and other
reviewers' own pre-existing untracked `redteam-*.md`/scratch files, confirming this
verification made zero tracked-repo-state changes:

```
 M docs/architecture/adr/README.md
 M lib/ggen_igniter/reactors/reconcile_reactor.ex
 M test/e2e/lifecycle_test.ex
 M test/e2e/support/e2e_case.ex
 M test/ggen_igniter_receipt_test.exs
?? .ggen_igniter_factory/GGEN-PARITY-NOTE.md
?? .ggen_igniter_factory/dogfood-self.md
?? .ggen_igniter_factory/ggen-parity.json
?? .ggen_igniter_factory/redteam-actuation-before-admission.md
?? .ggen_igniter_factory/redteam-coordination-bypass.md
?? .ggen_igniter_factory/redteam-doc-contradiction.md
?? .ggen_igniter_factory/redteam-receipt-gaps.md
?? priv/
?? test/ggen_igniter_doctor_inprocess_test.exs
?? test/ggen_igniter_sync_inprocess_dispatch_test.exs
?? test/ggen_igniter_sync_inprocess_reconcile_test.exs
```

## Bottom line

**REFUTED**: against the real, current repository state, using the real
`ontology_v9_rename_resource.ttl` and `ontology_v10_remove_resource.ttl` fixtures, run
through real `mix ggen_igniter.sync` subprocesses (and, separately, a real direct
`ReconcileReactor.run/1` call for the rename case), with `--on-stale` at its real,
actually-shipped default (`refuse`) — the pipeline does **not** leave any stale owned file
behind silently. It fails closed every time tested: a real non-zero exit / `:refused`
receipt, a message naming the exact stale path, and zero new bytes written, for both a
resource rename and a whole-resource removal.
