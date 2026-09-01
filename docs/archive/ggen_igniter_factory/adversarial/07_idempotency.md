# Adversarial Verification: Idempotency (Domain 07)

**Verifier**: independent, no access to prior builder reasoning/claims.
**Repo**: `/Users/sac/ggen_igniter` (not a git submodule of anything else checked)
**Real `mix.exs` version at verification time**: `26.8.27` (mix.exs line 9: `version: "26.8.27",`)
**NOTE**: the task brief referred to this repo's release target as "v26.7.27" — that string does **not** match the real `mix.exs`. Reporting the real value per instructions: it is **26.8.27**.
**Git HEAD**: `767bccea32d03790a1f4975596a06ecd16df365f` (2026-08-27 14:23:01 -0700) — same commit for both `lib/ggen_igniter/actuate.ex` and `lib/mix/tasks/ggen_igniter.sync.ex` per `git log -1 -- <path>`.
**Concurrency note**: while these commands ran, stdout showed `Waiting for lock on the build directory (held by process 60792)` / `(held by process 60827)` on run 3 — real evidence other concurrent processes (other adversarial-verifier agents, per the sibling files already present in this same `.ggen_igniter_factory/adversarial/` directory) were compiling this same repo concurrently. This did not affect correctness (run still completed, exit 0, correct `unchanged` notice), only added wait time.

---

## Claim 1: `mix ggen_igniter.sync` run 3x with identical inputs against `test/fixtures/ash-lifecycle-pack/` produces byte-identical output after run 1, with the notice line reading "unchanged" (not "wrote") on runs 2 and 3.

**Verdict: CONFIRMED**

### How the real invocation was derived (not guessed)

Read `lib/mix/tasks/ggen_igniter.sync.ex`'s moduledoc (lines 1–171) and `test/e2e/lifecycle_test.ex`'s real `sync!/3` helper (lines 350–366). The e2e test's real, working invocation is:

```elixir
cmd!("mix", ["ggen_igniter.sync", "--pack-dir", @pack_dir, "--ontology", ontology_path,
             "--template", template_path, "--engine", "sparql"], cd: app_dir)
```

`--out`/`--for-each` are deliberately omitted there because the pack's own templates carry `to:`/`for_each:` frontmatter (`test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex` lines 1–4: `to: "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`, `for_each: resource`, `mode: file`; `domain.ex.eex` lines 1–3: `to: "lib/support_desk/support.ex"`, `mode: file`). Per the moduledoc (lines 148–150, 221), an explicit CLI `--out` always overrides frontmatter `to:`, and `out_template` is itself EEx-rendered per row (`sync.ex` lines 437–441). This verification used that explicit-override path to redirect output into a throwaway directory instead of a full scaffolded Phoenix/Ash app (the e2e test's `app_dir`), avoiding an unnecessary multi-minute `phx.new`/`ash`/`deps.get` scaffold for a question that is purely about `Actuate.write_file!/3`'s own idempotency guard, not about Ash/Phoenix compilation. `--pack-dir` still auto-discovers the 5 named queries from `test/fixtures/ash-lifecycle-pack/gates/*.rq` exactly as the e2e test relies on.

Real commands run (verbatim, repo root `/Users/sac/ggen_igniter`, `--engine sparql` pinned to match the e2e test's own justification for pinning it — see `lifecycle_test.ex` lines 327-349 on the sparql/oxigraph default flux):

```
mix ggen_igniter.sync --pack-dir test/fixtures/ash-lifecycle-pack \
  --ontology test/fixtures/ash-lifecycle-pack/ontology.ttl \
  --template test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex \
  --engine sparql \
  --out "$OUTDIR/<%= String.downcase(resource_name) %>.ex"
```
(run 3 times, `$OUTDIR` unchanged across runs), plus a second independent trio against `templates/domain.ex.eex` with `--out "$SCRATCH/domain_out.ex"`.

### Real notice-line text, verbatim, all 3 runs (resource.ex.eex, for-each fan-out over 2 rows: Ticket, Customer)

```
Run 1: * ggen_igniter: wrote <OUTDIR>/ticket.ex; wrote <OUTDIR>/customer.ex (engine: sparql, 5 queries, 21 total row(s))
Run 2: * ggen_igniter: unchanged (skipped, identical content): <OUTDIR>/ticket.ex; unchanged (skipped, identical content): <OUTDIR>/customer.ex (engine: sparql, 5 queries, 21 total row(s))
Run 3: * ggen_igniter: unchanged (skipped, identical content): <OUTDIR>/ticket.ex; unchanged (skipped, identical content): <OUTDIR>/customer.ex (engine: sparql, 5 queries, 21 total row(s))
```

Full stdout captured at `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/idem_probe_59517/run{1,2,3}_stdout.txt`.

### Real byte-diff evidence

`ticket.ex`/`customer.ex` snapshotted with `cp` immediately after each run (`snap1/`, `snap2/`, `snap3/` in the same scratch dir); real `diff` command run pairwise:

```
diff snap1/ticket.ex   snap2/ticket.ex    -> no output (IDENTICAL)
diff snap1/customer.ex snap2/customer.ex  -> no output (IDENTICAL)
diff snap1/ticket.ex   snap3/ticket.ex    -> no output (IDENTICAL)
diff snap1/customer.ex snap3/customer.ex  -> no output (IDENTICAL)
```
sha256 of `snap1/ticket.ex` = `ff7b7891bd971c687f644554ff6860ecf21e4f08d84e31bb9a8942d762a0c5f4`, `snap1/customer.ex` = `cf4708130f40de7a7532259c18948c0a7fd670862b6897c55f71c0185b61a67b` (recorded for traceability; the pairwise `diff` is the actual identity proof).

### Second independent template, domain.ex.eex (single-row, no `--for-each`)

```
Run 1: * ggen_igniter: wrote <SCRATCH>/domain_out.ex (engine: sparql, 5 queries, 21 total row(s))
Run 2: * ggen_igniter: unchanged (skipped, identical content): <SCRATCH>/domain_out.ex (engine: sparql, 5 queries, 21 total row(s))
Run 3: * ggen_igniter: unchanged (skipped, identical content): <SCRATCH>/domain_out.ex (engine: sparql, 5 queries, 21 total row(s))
```
`diff domain_snap1.ex domain_snap2.ex` -> no output (IDENTICAL); `diff domain_snap1.ex domain_snap3.ex` -> no output (IDENTICAL).

This traces directly to `GgenIgniter.Actuate.write_file!/3`'s real decision table (`lib/ggen_igniter/actuate.ex` lines 74-101): `exists and existing == content -> {:ok, :unchanged}` is checked unconditionally on every call, matching `sync.ex`'s `outcome_verb(:unchanged)` (line 698) rendering `"unchanged (skipped, identical content):"`. All exit codes were 0 across all 6 real subprocess runs.

---

## Claim 2: `Actuate.inject_content!/5`'s `:before`-anchor idempotency fix genuinely holds (recently claimed) -- second identical injection call returns `:unchanged` and does NOT duplicate the injected content in the target file.

**Verdict: CONFIRMED** (verified directly against `GgenIgniter.Actuate.inject_content!/5`, not via `sync.ex` -- no CLI/frontmatter layer involved)

### Why `:before` specifically was worth adversarial suspicion

Reading `lib/ggen_igniter/actuate.ex` lines 329-357 (`already_present_at?/4`) shows the `:before` clause is NOT the same code path as `:after`/`:at_line` -- it has its own comment (lines 337-346) explaining that after a real first injection, the marker's line index shifts forward by `length(body_lines)`, so a naive re-use of the same "check the slice starting at insert_at" logic (correct for `:after`/`:at_line`) would silently duplicate the block on second injection for `:before`. This is exactly the kind of asymmetric, easy-to-get-wrong logic a "recently fixed" claim would be about, so it was independently exercised end to end rather than trusted from the code comment alone.

### Real script and 3 real sequential calls (not mocked, real file on disk, real `File.read!`)

Ran via `mix run <script>.exs` inside `/Users/sac/ggen_igniter` (script at `/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/idem_probe_59517/actuate_probe.exs`) against a real target file at `/private/tmp/.../actuate_target.ex`:

Target file seed content:
```elixir
defmodule Probe do
  # ANCHOR: insert before this line
  def existing, do: :ok
end
```

Marker: `"# ANCHOR: insert before this line"` (literal string, `:before` mode). Injected body: `"  def injected_fn, do: :new_thing"`.

Real output:
```
call 1 outcome: :injected
=== AFTER CALL 1 ===
defmodule Probe do
  def injected_fn, do: :new_thing
  # ANCHOR: insert before this line
  def existing, do: :ok
end

call 2 outcome: :unchanged
=== AFTER CALL 2 ===
defmodule Probe do
  def injected_fn, do: :new_thing
  # ANCHOR: insert before this line
  def existing, do: :ok
end

occurrences of injected_body in final file: 1
call1 == call2 file content byte-identical: true
outcome1 == :injected: true
outcome2 == :unchanged: true
call 3 outcome: :unchanged
call3 == call1 byte-identical: true
```

Real, in-script assertions computed from actual file reads (`File.read!/1` after each call), not assumed:
- `outcome1 == :injected` -- **true**
- `outcome2 == :unchanged` -- **true**
- `outcome3 == :unchanged` -- **true** (third call added for extra rigor beyond the requested two)
- Occurrences of the injected body string in the final file content, counted via a real `String.split/2` + length count -- **1** (not 2; the fix genuinely prevents duplication)
- File content after call 1 vs. after call 2 -- **byte-identical** (`after_call1 == after_call2` -> `true`)
- File content after call 3 vs. after call 1 -- **byte-identical** (`after_call3 == after_call1` -> `true`)

### Conclusion

The claimed `:before`-anchor idempotency fix in `GgenIgniter.Actuate.inject_content!/5` (`lib/ggen_igniter/actuate.ex` lines 337-351, the `already_present_at?(lines, body_lines, insert_at, :before)` clause checking the slice ending AT `insert_at` rather than starting there) is real and holds under direct, repeated, real-file exercise: two and three consecutive identical `:before` injections neither duplicate the content nor mutate the file beyond the first real injection.

---

## Summary table

| # | Claim | Verdict | Evidence |
|---|-------|---------|----------|
| 1 | `mix ggen_igniter.sync` (resource.ex.eex, for-each) is idempotent over 3 identical runs; notice says "unchanged" on runs 2-3 | CONFIRMED | 3 real subprocess runs, verbatim notice text above, real `diff` = no output all pairs |
| 2 | `mix ggen_igniter.sync` (domain.ex.eex, single-row) is idempotent over 3 identical runs | CONFIRMED | 3 real subprocess runs, verbatim notice text above, real `diff` = no output all pairs |
| 3 | `Actuate.inject_content!/5`'s `:before`-anchor fix genuinely prevents duplicate injection on re-run | CONFIRMED | Direct real-file script, 3 sequential calls, outcome + content verified, 1 occurrence (not 2) of injected body in final file |

No REFUTED or UNVERIFIABLE findings in this domain. All evidence above is from real commands executed in this session against real disk state; no prior builder claims were consulted or assumed.
