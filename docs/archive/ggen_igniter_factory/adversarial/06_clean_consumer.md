# Adversarial Verification 06: Clean Fresh Consumer

**Scope**: Independent, from-scratch reproduction of the "bare consumer" claim for
`ggen_igniter`. No prior agent's reasoning or claims were consulted. All commands
below were executed by this verifier, in this session, against real repository disk
state and a real throwaway `/tmp` mix project.

**Repo under test**: `/Users/sac/ggen_igniter`
**Repo HEAD at verification time**:
`767bccea32d03790a1f4975596a06ecd16df365f` — "Add hygen-parity frontmatter,
mode:eval/inject actuation, oxigraph default engine, optional tesla/gno, doctor
--fix, and full-lifecycle e2e tier"

**Note on stated release target**: the task framing named "v26.7.27" as the release
target. The real `mix.exs` (`/Users/sac/ggen_igniter/mix.exs:9`) declares
`version: "26.8.27"`. Reporting the real value per instructions — this is a
version-label discrepancy in the task framing, not a repo defect; not otherwise
investigated further as it's out of this check's scope.

**Toolchain**: `elixir --version` → `Elixir 1.19.5 (compiled with Erlang/OTP 28)`,
Erlang/OTP 28 [erts-16.2].

**Probe directory**: `/tmp/probe_verifier_bare_1787868029_58629` (created via
`mix new`, deleted at the end of this run — confirmed via `ls` returning "No such
file or directory" after `rm -rf`).

---

## Claim 1: `mix new` + path dep on `ggen_igniter` + `mix deps.get` succeeds

**Verdict: CONFIRMED**

Command:
```
mix new /tmp/probe_verifier_bare_1787868029_58629 --module ProbeVerifierBare
```
Exit code: `0` ("Your Mix project was created successfully.")

Added to the generated `mix.exs`'s `deps/0`:
```elixir
defp deps do
  [
    {:ggen_igniter, path: "/Users/sac/ggen_igniter"}
  ]
end
```

Command: `mix deps.get` (run inside the probe dir)
Exit code: `0`. Real output: "Resolution completed in 1.433s", followed by 27
resolved packages (decimal, ex_ast, finch, glob_ex, hpax, igniter, jason, jcs, mime,
mint, nimble_csv, nimble_options, nimble_pool, owl, protocol_ex, rdf, req, rewrite,
rustler, sourceror, sparql, spitfire, sweet_xml, telemetry, text_diff, toml, uniq,
yamerl, yaml_elixir).

**Neither `tesla` nor `gno` appear in the resolved deps list.**

---

## Claim 2: `:tesla`/`:gno` are absent from the consumer's own dep tree

**Verdict: CONFIRMED**

Command: `mix deps.tree`

Real output (full tree reproduced below) shows the dependency closure of
`ggen_igniter` from the consumer's perspective — `igniter`, `rdf`, `rustler`,
`sparql`, `toml`, `yaml_elixir`, and their respective transitive deps
(`ex_ast`, `glob_ex`, `jason`, `decimal`, `owl`, `req`, `finch`, `mime`, `mint`,
`hpax`, `nimble_options`, `nimble_pool`, `telemetry`, `nimble_csv`, `rewrite`,
`sourceror`, `text_diff`, `spitfire`, `jcs`, `protocol_ex`, `sweet_xml`, `uniq`,
`yamerl`). No `tesla` or `gno` node anywhere in the tree.

```
probe_verifier_bare_1787868029_58629
└── ggen_igniter (/Users/sac/ggen_igniter)
    ├── igniter ~> 0.8 (Hex package)
    │   ├── ex_ast ~> 0.5 (Hex package)
    │   │   ├── jason ~> 1.4 (Hex package)
    │   │   └── sourceror ~> 1.7 (Hex package)
    │   ├── glob_ex ~> 0.1.7 (Hex package)
    │   ├── jason ~> 1.4.5 (Hex package)
    │   │   └── decimal ~> 1.0 or ~> 2.0 or ~> 3.0 (Hex package)
    │   ├── owl ~> 0.11 (Hex package)
    │   ├── req ~> 0.5 (Hex package)
    │   │   ├── finch ~> 0.21 (Hex package)
    │   │   │   ├── mime ~> 1.0 or ~> 2.0 (Hex package)
    │   │   │   ├── mint ~> 1.8 (Hex package)
    │   │   │   │   └── hpax ~> 0.1.1 or ~> 0.2.0 or ~> 1.0 (Hex package)
    │   │   │   ├── nimble_options ~> 0.4 or ~> 1.0 (Hex package)
    │   │   │   ├── nimble_pool ~> 1.1 (Hex package)
    │   │   │   └── telemetry ~> 0.4 or ~> 1.0 (Hex package)
    │   │   ├── jason ~> 1.0 (Hex package)
    │   │   ├── mime ~> 2.0.6 or ~> 2.1 (Hex package)
    │   │   └── nimble_csv ~> 1.0 (Hex package)
    │   ├── rewrite >= 1.1.1 and < 2.0.0-0 (Hex package)
    │   │   ├── glob_ex ~> 0.1 (Hex package)
    │   │   ├── sourceror ~> 1.0 (Hex package)
    │   │   └── text_diff ~> 0.1 (Hex package)
    │   ├── sourceror ~> 1.4 (Hex package)
    │   └── spitfire >= 0.1.3 and < 1.0.0-0 (Hex package)
    ├── rdf ~> 3.0 (Hex package)
    │   ├── decimal ~> 3.0 (Hex package)
    │   ├── jason ~> 1.4 (Hex package)
    │   ├── jcs ~> 0.2 (Hex package)
    │   │   └── jason ~> 1.4 (Hex package)
    │   ├── protocol_ex ~> 0.5 (Hex package)
    │   └── uniq ~> 0.6 (Hex package)
    ├── rustler ~> 0.36 (Hex package)
    │   └── jason ~> 1.0 (Hex package)
    ├── sparql ~> 0.3 (Hex package)
    │   ├── jason ~> 1.0 (Hex package)
    │   ├── nimble_csv ~> 1.0 (Hex package)
    │   ├── protocol_ex ~> 0.4 (Hex package)
    │   ├── rdf ~> 3.0 (Hex package)
    │   ├── sweet_xml ~> 0.6 (Hex package)
    │   └── uniq ~> 0.6 (Hex package)
    ├── toml ~> 0.7 (Hex package)
    └── yaml_elixir ~> 2.9 (Hex package)
        └── yamerl ~> 0.10 (Hex package)
```

Confirmed via `mix deps.tree 2>&1 | grep -iE "tesla|gno"` → no output (`NO MATCH
(confirmed absent)`).

Corroborated at the source: `/Users/sac/ggen_igniter/mix.exs:99` declares
`{:tesla, "~> 1.8", optional: true}` and `mix.exs:133` declares
`{:gno, "~> 0.1", optional: true}` — `optional: true` is the mechanism that keeps
both out of a *consumer's* own resolved dep tree while still letting `ggen_igniter`
compile them for its own dev/test/prod when present.

---

## Claim 3: `mix compile --warnings-as-errors` succeeds (exit 0) without tesla/gno

**Verdict: CONFIRMED**

Ran twice independently for reproducibility, including a fully clean rebuild
(`rm -rf _build` before the second run):

Run 1 (first compile after `deps.get`):
```
mix compile --warnings-as-errors
```
Exit code: `0`. Compiled ggen_igniter's 18 `.ex` files plus the native
`ggen_graph_nif` Rust crate (`Compiling crate ggen_graph_nif in release mode`,
copied to `priv/native/ggen_graph_nif.so`), then the probe app itself. Real output
ends with `Generated probe_verifier_bare_1787868029_58629 app`.

Run 2 (clean rebuild, `rm -rf _build` then recompile, output redirected to file so
the exit code is captured unambiguously):
```
rm -rf _build deps/ggen_igniter/_build
mix compile --warnings-as-errors > /tmp/full_recompile_out.txt 2>&1
echo "EXITCODE=$?"
```
Real output: `EXITCODE=0`.

**Caveat worth recording precisely** (not a contradiction of the claim, but a real
observation about *why* it passes): the compile output does contain several
`warning:` blocks from Elixir 1.19's new set-theoretic type checker — e.g.
"typing violation found at: ... `body = http_get!(url)` ... because the right-hand
side has type: none()" at `lib/ggen_igniter/pack.ex:236` and `:276`, and at
`lib/mix/tasks/ggen_igniter.doctor.ex:286` for the `Qlever.load_store!` call — plus
pre-existing warnings inside third-party deps (`toml`'s single-quoted-charlist
warnings in `lib/decoder.ex`, `uniq`'s unused-private-function warnings in
`lib/scoped_uuid.ex`, `sweet_xml`'s struct-update typing warning). None of these
caused `--warnings-as-errors` to fail the build on this toolchain
(Elixir 1.19.5 / OTP 28) — the observed, reproduced behavior is exit code `0`
despite their presence, in both the fresh-`deps.get` compile and the fully clean
`rm -rf _build` recompile.

---

## Claim 4: `--engine qlever` without `:gno` raises a clear, named `RuntimeError`

**Verdict: CONFIRMED**

Command, executed for real inside the probe project (no `:gno` in its deps, per
Claims 1-2 above):
```elixir
mix run -e '
try do
  GgenIgniter.Query.Qlever.load_store!(RDF.Graph.new(), "http://example.org/store")
rescue
  e in RuntimeError -> IO.puts("CAUGHT_RUNTIME_ERROR: " <> Exception.message(e))
  e -> IO.puts("CAUGHT_OTHER: " <> inspect(e.__struct__) <> " -- " <> Exception.message(e))
end
'
```
Real captured output:
```
CAUGHT_RUNTIME_ERROR: ggen_igniter: :gno is required for --engine qlever (Gno.Store.Adapters.Qlever) but is not loaded -- add {:gno, "~> 0.1"} to your own mix.exs deps
```
This is a genuine `RuntimeError` (not `UndefinedFunctionError`, not a compile
crash) — the `rescue e in RuntimeError` clause matched. Source:
`/Users/sac/ggen_igniter/lib/ggen_igniter/query/qlever.ex:125-135` — the
`Code.ensure_loaded?(Gno.Store.Adapters.Qlever)` branch at line 20 compiles a stub
module (no reference to `Gno`/`SPARQL.Client` anywhere in it) whose `load_store!/2`
and `run/2` both unconditionally `raise(RuntimeError, message: @missing_gno_message)`.

---

## Claim 5: `--pack github:`/`hex:` fetch without `:tesla` raises a clear, named `RuntimeError`

**Verdict: CONFIRMED**

Command (github: spec), executed for real:
```elixir
mix run -e '
try do
  GgenIgniter.Pack.fetch_pack!("github:owner/repo")
rescue
  e in RuntimeError -> IO.puts("CAUGHT_RUNTIME_ERROR: " <> Exception.message(e))
  e -> IO.puts("CAUGHT_OTHER: " <> inspect(e.__struct__) <> " -- " <> Exception.message(e))
end
'
```
Real captured output:
```
CAUGHT_RUNTIME_ERROR: ggen_igniter: :tesla is required for --pack fetch from github:/hex: URLs but is not loaded -- add {:tesla, "~> 1.8"} to your own mix.exs deps
```

Command (hex: spec), executed for real:
```elixir
mix run -e '
try do
  GgenIgniter.Pack.fetch_pack!("hex:some_package")
rescue
  e in RuntimeError -> IO.puts("CAUGHT_RUNTIME_ERROR: " <> Exception.message(e))
  e -> IO.puts("CAUGHT_OTHER: " <> inspect(e.__struct__) <> " -- " <> Exception.message(e))
end
'
```
Real captured output (identical message — both specs route through the same
`http_get!/1` stub):
```
CAUGHT_RUNTIME_ERROR: ggen_igniter: :tesla is required for --pack fetch from github:/hex: URLs but is not loaded -- add {:tesla, "~> 1.8"} to your own mix.exs deps
```

Both are genuine `RuntimeError`s (the `rescue e in RuntimeError` clause matched in
both cases), not raw `UndefinedFunctionError`s or compile crashes. Source:
`/Users/sac/ggen_igniter/lib/ggen_igniter/pack.ex:382-409` — `Code.ensure_loaded?(Tesla)`
gates a real-Tesla `http_get!/1` branch vs. a stub branch (lines 403-409) whose
`http_get!/1` unconditionally `raise`s `RuntimeError` with the tesla-missing
message; `fetch_github!/4` (line 234) and `fetch_hex!/3` (line 250, chaining to
`http_get_json!/1`) both funnel through this same `http_get!/1`.

---

## Cleanup

**Verdict: CONFIRMED**
```
rm -rf /tmp/probe_verifier_bare_1787868029_58629
ls /tmp/probe_verifier_bare_1787868029_58629
```
Real output: `ls: /tmp/probe_verifier_bare_1787868029_58629: No such file or
directory` — probe directory fully removed after verification.

---

## Summary table

| # | Claim | Verdict |
|---|-------|---------|
| 1 | Fresh consumer `mix new` + path dep + `mix deps.get` succeeds | CONFIRMED |
| 2 | `:tesla`/`:gno` absent from consumer's own `mix deps.tree` | CONFIRMED |
| 3 | `mix compile --warnings-as-errors` exits 0 without tesla/gno present | CONFIRMED |
| 4 | `--engine qlever` path raises named `RuntimeError` (not UndefinedFunctionError/crash) without `:gno` | CONFIRMED |
| 5 | `--pack github:`/`hex:` fetch path raises named `RuntimeError` without `:tesla` | CONFIRMED |

**Note on task framing**: the task described the release target as "v26.7.27"; the
real `mix.exs:9` says `version: "26.8.27"`. Flagging per instructions to report the
real value rather than assume the framing was correct — not itself a pass/fail
verdict, just a factual correction to the framing.

No claim in this domain was found to be false. All five were independently
reproduced from a clean `/tmp` probe with no reliance on any other agent's prior
output.
