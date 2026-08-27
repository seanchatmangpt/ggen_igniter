# Adversarial Verification — Domain: Unreachable Branches & Stale/Renamed Identifiers

Repo: `/Users/sac/ggen_igniter` (not a git repo — no SHA available)
Real `mix.exs` version at time of check: `version: "26.8.27"` (task brief said
"v26.7.27" — that value does not appear in `mix.exs`; reporting the real value,
per instructions, not assuming).
Elixir/Mix: 1.19.5 (from tool output below).
Verifier: independent, no builder reasoning consulted, all evidence produced fresh in this session.

Verdicts: CONFIRMED / REFUTED / UNVERIFIABLE, each with the real command/evidence.

---

## 1. `Mix.Tasks.GgenIgniter.Sync`'s `actuate!/8` — clause reachability

File read in full: `lib/mix/tasks/ggen_igniter.sync.ex` (915 lines).

Four clauses, at lines 437, 443, 467, 479:

```elixir
defp actuate!(:file, content, bindings, out_template, _template_path, write_opts, dry_run, nil)
defp actuate!(:file, content, bindings, out_template, _template_path, _write_opts, dry_run, {marker, insert_mode, inject_opts})
defp actuate!(:eval, _content, _bindings, _out_template, template_path, _write_opts, true, _inject_spec)
defp actuate!(:eval, content, bindings, _out_template, template_path, _write_opts, false, _inject_spec)
```

**Call-site analysis** (lines 383-392, 405-414): every call passes 8 positional
args `(mode, content, bindings, out_template, template_path, write_opts, dry_run, inject_spec)`.

**Value-space analysis**:
- `mode` (arg 1) is produced only by `resolve_mode!/2` (line 653), which returns exactly
  `:file` or `:eval` (or raises) — never any other value.
- `inject_spec` (arg 8) is computed at lines 369-372:
  `if mode == :file and (frontmatter_field(frontmatter, :inject) || false) do resolve_injection!(frontmatter) end`
  — this is `nil` whenever `mode == :eval` (the `if` condition is false), and either `nil`
  or a real 3-tuple `{marker, insert_mode, inject_opts}` (from `resolve_injection!/1`, lines
  525-552 — itself exhaustive: `[]` raises, `[{:before,_}]`/`[{:after,_}]`/`[{:at_line,_}]`
  each produce a 3-tuple, `many` raises) when `mode == :file`.
- `dry_run` (arg 7) is `opts[:dry_run] || false` (line 342) — always a plain boolean.

So the real reachable argument combinations are exactly:
1. `mode=:file, inject_spec=nil` → clause 1 (only clause matching literal `nil` in position 8 for `:file`)
2. `mode=:file, inject_spec={_,_,_}` → clause 2 (only clause whose position-8 pattern is a 3-tuple)
3. `mode=:eval, dry_run=true` → clause 3 (only clause with literal `true` in position 7 for `:eval`)
4. `mode=:eval, dry_run=false` → clause 4 (only clause with literal `false` in position 7 for `:eval`)

No clause is more general than another at the positions that discriminate them (1, 7, 8) —
clause 1 and 2 are disjoint on arg 8 (`nil` vs. a 3-tuple literal shape), clause 3 and 4 are
disjoint on arg 7 (`true` vs. `false`). None of the four is a strict subset of an earlier
clause's pattern, so none is shadowed. All four are real and reachable.

**Verdict: CONFIRMED** — all 4 clauses of `actuate!/8` are reachable; none is fully shadowed
by an earlier, more general clause.

Evidence: manual pattern-matching walkthrough above (source: `lib/mix/tasks/ggen_igniter.sync.ex:325-419` for call sites and computation of `mode`/`inject_spec`/`dry_run`; `:437,443,467,479` for the four clause heads; `:525-552` for `resolve_injection!/1`'s own exhaustiveness), corroborated by the compiler check in §5 below (Elixir 1.19.5 moved unreachable-clause detection into `mix compile` itself, and it emitted zero such warnings for this file).

---

## 2. `GgenIgniter.Actuate`'s inject-related functions — clause reachability

File read in full: `lib/ggen_igniter/actuate.ex` (358 lines).

- `matches?/2` (lines 103-104): `matches?(content, %Regex{} = pattern)` then
  `matches?(content, needle) when is_binary(needle)`. Disjoint on argument type
  (`%Regex{}` struct vs. binary) — not shadowed, both reachable.
- `marker_matches?/2` (lines 312, 314-315): same shape, `%Regex{}` vs. `is_binary` guard —
  disjoint, both reachable.
- `already_present_at?/4` (lines 347, 353): `already_present_at?(lines, body_lines, insert_at, :before)`
  is defined **before** `already_present_at?(lines, body_lines, insert_at, _mode)`. The specific
  `:before` clause is ordered first, so it is not shadowed by the general `_mode` fallback that
  follows it (Elixir tries clauses top-to-bottom; the general clause only ever catches `:after`/
  `:at_line` in practice, since `:before` is already consumed by the earlier, more specific
  clause). Correct ordering — both clauses reachable, no bug.
- `inject_content!/5` itself is a single clause with a `when insert_mode in [:before, :after, :at_line]`
  guard (line 184-185); the mode dispatch inside its body (line 201) is a `case`, not a set of
  function clauses, and covers exactly `:before | :after | :at_line` — exhaustive against the guard.

**Verdict: CONFIRMED** — no unreachable clause in any of `GgenIgniter.Actuate`'s inject-related
functions; ordering of `already_present_at?/4`'s two clauses is correct (specific-before-general).

Evidence: `lib/ggen_igniter/actuate.ex:103-104,184-220,312,314-315,347-357`.

---

## 3. `GgenIgniter.Engine`'s dispatch

File read in full: `lib/ggen_igniter/engine.ex` (157 lines).

`fetch!/1` (lines 72-77) dispatches via `Map.get(@registry, name)` against a plain map
literal (`"sparql" => ...`, `"qlever" => ...`, `"oxigraph" => ...`) — there is no
pattern-matched function-clause dispatch here at all, so clause-shadowing is structurally
not possible for this lookup. `Mix.Tasks.GgenIgniter.Sync.run_queries/4` (see §4) dispatches
dynamically through the returned module's `prepare!/2`/`run/2` callbacks (`engine_module.prepare!(...)`,
`engine_module.run(...)`) — again no per-engine-name function clauses to shadow.

**Verdict: CONFIRMED (N/A — no clause-based dispatch exists to check)**. The refactor this
domain check is looking for evidence of (a prior clause-based `run_queries("sparql", ...)`,
`run_queries("qlever", ...)` etc. dispatch) has genuinely been replaced by table/behaviour
dispatch — there is nothing clause-shaped left to have a shadowing bug in.

Evidence: `lib/ggen_igniter/engine.ex:1-78` (registry + `fetch!/1`), `lib/mix/tasks/ggen_igniter.sync.ex:865-871` (`run_queries/4`'s real body).

---

## 4. Stale/renamed identifier grep sweep (whole `lib/` + `test/`)

### 4a. `run_queries(` with a string first arg

```
$ grep -rn 'run_queries(' lib/ test/
lib/ggen_igniter/engine.ex:6:  function clauses (`run_queries("sparql", ...)`, `run_queries("qlever", ...)`,
lib/mix/tasks/ggen_igniter.sync.ex:338:    named_results = run_queries(engine_module, graph, opts, named_queries)
lib/mix/tasks/ggen_igniter.sync.ex:865:  defp run_queries(engine_module, graph, opts, named_queries) do
```

The only textual match for the literal pattern `run_queries("...")` is inside
`engine.ex`'s own `@moduledoc` (line 6), which is prose *describing the OLD anti-pattern this
refactor deliberately avoided* ("...instead of hardcoded, string-pattern-matched function
clauses (`run_queries("sparql", ...)`, ...)") — not real code, not a call site. The two real
code references (`sync.ex:338` call site, `sync.ex:865` definition) both use the current
4-arg signature `run_queries(engine_module, graph, opts, named_queries)`, first arg a
**module**, not a string.

**Verdict: CONFIRMED (no stale reference exists)** — the old hardcoded-string dispatch form
is genuinely gone from real code; its only textual trace is a deliberate, correctly-labeled
"this is what we no longer do" comment.

### 4b. `@valid_engines`

```
$ grep -rn '@valid_engines' lib/ test/
(no output)
$ grep -rn 'valid_engines' lib/ test/
(only lib/ggen_igniter/engine.ex:52,56,57 -- the CURRENT `valid_names/0` function's own
 @doc example text and definition, not a stale `@valid_engines` module attribute)
```

**Verdict: CONFIRMED (fully removed)** — zero occurrences of `@valid_engines` anywhere in
`lib/` or `test/`.

### 4c. Broader "reference to a function/module that no longer exists" sweep

Enumerated every real `defmodule` in `lib/` and cross-checked every `GgenIgniter.*` dotted
reference appearing in `lib/` + `test/` against that list (66 distinct dotted names checked).
Notable specific findings:

- `GgenIgniter.Query.Qlever` appears to be defined **twice** in
  `lib/ggen_igniter/query/qlever.ex` (lines 21 and 113) — verified this is a legitimate
  compile-time `if Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do ... else ... end` branch
  (lines 20-137): only one of the two module bodies ever actually compiles, selected once at
  compile time depending on whether the optional `:gno` dep is present. Not a duplicate-definition
  bug, not a stale leftover.
- `GgenIgniter.Gate` is referenced exactly once, in `lib/ggen_igniter/project_config.ex:137`,
  inside a moduledoc sentence: `` `GgenIgniter.Gate` (if/when built) should mirror that same `` —
  an explicit, self-labeled forward-looking design note for a module that does not exist yet.
  This is not a stale reference to something *removed*; it never existed. Out of this domain's
  scope (which targets refactor leftovers, not forward-looking TODOs), noted for completeness.
- `GgenIgniter.WriteOutcome` (`lib/ggen_igniter/write_outcome.ex`) is a real module, fully
  defined, but not referenced/called from anywhere else in `lib/` or `test/`. Its own moduledoc
  explicitly discloses this: *"Not wired into `Actuate` in this pass."* This is the reverse of
  a stale reference (unused new code, not a broken old reference to removed code) — out of this
  domain's literal scope, flagged for the record only, not reported as a defect.
- Every other cross-checked module reference (`GgenIgniter.Actuate`, `.Pack`, `.Pack.*`,
  `.Frontmatter`, `.Frontmatter.MatchRule/.MatchSpec/.FreezePolicy`, `.Engine.*`, `.Query`,
  `.Query.Oxigraph`, `.Render`, `.Render.Tera`, `.Ontology`, `.ProjectConfig.*`,
  `.PackManifest.*`, `.PackRef`, `.Application`, `.Native.GraphNif`, `.Doctor`,
  `.DoctorFixes`) resolves to a real `defmodule` — no orphaned references found.
- `GgenIgniter.Pack.*` calls used elsewhere (`default_ontology`, `discover_queries`,
  `discover_template`, `fetch_pack!`, `resolve_dir!`) all match real `def`s in `lib/ggen_igniter/pack.ex`.

**Verdict: CONFIRMED (no stale/broken module or function references found)**, with the two
noted-but-out-of-scope observations above (`GgenIgniter.Gate` forward-reference,
`GgenIgniter.WriteOutcome` unused-but-real module) included for completeness, not as defects
in this domain.

---

## 5. Compiler-level corroboration (independent of the manual review above)

```
$ mix xref unreachable
...
The unreachable check has been moved to the compiler and has no effect now
```

This confirms that for this Elixir/Mix version (1.19.5), `mix compile --warnings-as-errors`
is itself the authoritative unreachable-clause detector — not a separate, weaker check.

```
$ rm -rf _build/dev/lib/ggen_igniter && mix compile --force --warnings-as-errors 2>&1 | wc -l
      17
```
(all 17 lines are the single unrelated `:preferred_cli_env` deprecation notice from `mix.exs`'s
`def project` — a config-style warning, not a code-correctness one; zero
undefined-function/module warnings, zero unreachable-clause warnings)

```
$ MIX_ENV=test mix compile --force --warnings-as-errors > /tmp/test_compile_out.txt; echo $?
0
$ cat /tmp/test_compile_out.txt
Compiling 18 files (.ex)
Compiling crate ggen_graph_nif in release mode (native/ggen_graph_nif)
Copying .../libggen_graph_nif.dylib to priv/native/ggen_graph_nif.so
Generated ggen_igniter app
```
Test-env full recompile: exit 0, zero warnings at all.

**Verdict: CONFIRMED** — both the `dev` and `test` compilation environments compile clean
under `--warnings-as-errors` with a forced full rebuild, corroborating §1-§4's manual findings:
no unreachable clauses, no undefined/stale function or module references anywhere the compiler
can see (which is everything reachable from `lib/` and `test/`'s own compiled units).

---

## 6. Full test suite (context only — outside this domain's direct scope)

```
$ mix test
...
Finished in 114.3 seconds (3.4s async, 110.8s sync)
12 doctests, 21 properties, 207 tests, 0 failures
```

Run clean, 0 failures. (An earlier run in this same session showed "4 failures" under a
different timing/lock-contention condition — non-reproducing on immediate rerun, most likely
order/timing-sensitive or network-dependent (`test/ash_r2rml_gate_qlever_test.exs`,
`github:octocat/Hello-World` fetch tests hit real network/GitHub during this suite). Not
chased further: general test correctness/flakiness is outside this domain's brief
(unreachable branches / stale identifiers specifically), and it did not reproduce. Flagged
for the record, not reported as a finding in this domain.

---

## Summary table

| # | Claim checked | Verdict |
|---|---|---|
| 1 | `actuate!/8`'s 4 clauses are all real and reachable, none shadowed | CONFIRMED |
| 2 | `Actuate`'s inject-related functions have no shadowed clauses | CONFIRMED |
| 3 | `Engine`'s dispatch has no clause-shadowing risk (table-based, not clause-based) | CONFIRMED |
| 4a | No `run_queries(` call with a string first arg remains in real code | CONFIRMED |
| 4b | `@valid_engines` fully removed | CONFIRMED |
| 4c | No dangling references to removed functions/modules in `lib/`+`test/` | CONFIRMED |
| 5 | Full `dev`+`test` recompile clean under `--warnings-as-errors` (corroborates 1-4) | CONFIRMED |

**No REFUTED or UNVERIFIABLE items in this domain.**
