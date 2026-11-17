# Lane 03: Render, EEx, and the Tera Subsets

Standing: UNVERIFIED

Exploration lane 03 for v26.11.17. Read-only, static. No `mix`, `elixir`, or `cargo`
was available in this session (`which elixir` returned nothing; `_build/` absent), so no
behavior below was executed. Every finding is a source read with `file:line` evidence and
stays UNVERIFIED until a probe is run. The render layer is not one engine but four:
stdlib EEx (`Render.render/2`), a WASM-hosted real `tera` crate (`Render.TeraWasm`), a
hand-rolled subset (`Render.Tera`) with no `lib/` caller, and a second hand-rolled subset
(`PackFrontmatter.Tera`) used only by the frontmatter-pack path. Which engine renders a
`.tmpl` depends on the entry path, and the engines disagree on undefined variables and on
unsupported syntax. Branch: `claude/kind-ptolemy-imv2b6`; remote `seanchatmangpt/ggen_igniter`.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| R01 | `Render.render/2` is a bare `EEx.eval_string/2`; no `file:`/`line:` opts, so template errors lack the template path | UNVERIFIED | `lib/ggen_igniter/render.ex:10-11` |
| R02 | EEx bindings must be atom-keyed; a string-keyed map is converted by `Map.to_list` and handed to EEx as-is, so `%{"x" => 1}` likely fails or is ignored | UNVERIFIED | `render.ex:10`; no test passes string keys (`grep -n '"x" =>' test/ggen_igniter_render_properties_test.exs` not run) |
| R03 | EEx templates execute arbitrary Elixir (`System.cmd`, file IO) with no sandbox; a marketplace `.eex` is code, not data | UNVERIFIED | `render.ex:11` evaluates the full template as code |
| R04 | Two hand-rolled Tera engines plus the WASM one; `Render.Tera` has zero callers in `lib/` (only a moduledoc mention) and one test file | UNVERIFIED | `grep -rn "Render.Tera\b" lib` -> only `render/tera_wasm.ex:10`; test use only `test/render_tera_test.exs` |
| R05 | `docs/status.md:147` says `*.tmpl` pipeline dispatch to `Render.Tera` is "planned"; in fact `.tmpl` dispatches today, to `TeraWasm`, not `Render.Tera` | UNVERIFIED | `docs/status.md:147` vs `lib/ggen_igniter/render/tera_wasm.ex:64`, `reconcile.ex:157,303` |
| R06 | Same `.tmpl` file renders on different engines by entry path: `Reconcile`/`ReconcileReactor` use `TeraWasm.render_for!`, `--pack-dir` frontmatter packs use `PackFrontmatter.Tera` | UNVERIFIED | `reconcile.ex:157`; `reactors/reconcile_reactor.ex:1670,1707`; `pack_frontmatter/sync.ex:221,230`; `mix/tasks/ggen_igniter.sync.ex:907-925` |
| R07 | `PackFrontmatter.Tera` raises on undefined `{{ var }}`; `Render.Tera` renders it as empty string; real tera (WASM) behavior unprobed. Parity not asserted by any test I found | UNVERIFIED | `pack_frontmatter/tera.ex:587-593,687-690`; `render/tera.ex:203`; `grep -rln "PackFrontmatter.Tera" test` -> `sync_test.exs`, `tera_test.exs` only |
| R08 | `Render.Tera` silently passes unsupported syntax: `{% if a == 1 %}` goes through `eval_path`, parses as a path, evaluates `nil`, takes the else branch; no `elif`, `==`, `and`, `not` support | UNVERIFIED | `render/tera.ex:190,223-232`; moduledoc lists only truthiness `if` (`render/tera.ex:14-20`) |
| R09 | `Render.Tera` splits expressions on every `|`, including inside string literals; filter args only accept double-quoted strings; `filter(attribute=...)` without `value` raises `KeyError` via `Map.fetch!` | UNVERIFIED | `render/tera.ex:212,290-293,310` |
| R10 | `Render.Tera` `for` over a map yields `{k, v}` tuples then `to_string(tuple)`, which would raise `Protocol.UndefinedError`; `for` has no `loop` variable | UNVERIFIED | `render/tera.ex:180-187,205` |
| R11 | `PackFrontmatter.Tera` tag scanner closes on the first `}}`/`%}`/`#}`, so a string literal containing a closer would truncate the tag; real Tera behavior here unprobed | UNVERIFIED | `pack_frontmatter/tera.ex:85-105` (`:binary.match(rest, close)`) |
| R12 | `PackFrontmatter.Tera` has no `{% raw %}`, `include`, `extends`, `break`, `continue`; they raise `ArgumentError`, so a template cannot emit a literal `{{` | UNVERIFIED | `pack_frontmatter/tera.ex:159-204,253` (only set/set_global/macro/for/if handled) |
| R13 | `PackFrontmatter.Tera` `/` by zero raises `ArithmeticError`, not the documented `ArgumentError`; `compare/3` builds atoms with `String.to_atom(op)` over a closed operator set (safe if the lexer stays closed) | UNVERIFIED | `pack_frontmatter/tera.ex:637-649,724-731`; moduledoc claim at `:27` |
| R14 | `PackFrontmatter.Tera` env is string-keyed only; an atom-keyed binding map reports "not defined". `Render.Tera` normalizes top-level keys, so the two have different calling contracts | UNVERIFIED | `pack_frontmatter/tera.ex:587-593`; `render/tera.ex:46-48` |
| R15 | `TeraWasm.render/2` calls `Wasmex.start_link` per render and never stops the instance; process and wasm memory live until the caller exits | UNVERIFIED | `render/tera_wasm.ex:110` (no `GenServer.stop` anywhere in the file) |
| R16 | `TeraWasm.render/2` uses `Jason.encode!`, which raises (not `{:error, _}`) on non-encodable bindings (tuples, structs without an encoder), contradicting the `{:ok,_}|{:error,_}` spec; `render_for!` then never reaches its own raise | UNVERIFIED | `render/tera_wasm.ex:107,104` |
| R17 | `TeraWasm` loads the wasm file at a compile-time-expanded path relative to `__DIR__`, and reads the whole file on every render; the path breaks if compiled in one tree and run from another | UNVERIFIED | `render/tera_wasm.ex:18-27,141-142`; `mix.exs:143-147` lists the file in the package |
| R18 | `.tmpl` routing is content-sniffed: a body with `<%` and no `{{`/`{%`/`{#` stays EEx; a mixed body (EEx tag plus a Tera delimiter) goes to Tera and the `<%` passes through literally | UNVERIFIED | `render/tera_wasm.ex:64,69-73`; `tera_wasm_test.exs:41-73` covers path cases, mixed-body case not found by grep |
| R19 | Frontmatter `to:` follows the template body's engine via `kind_body`, so a `.tmpl` with an EEx `to:` and Tera body (or the reverse) is untested | UNVERIFIED | `render/tera_wasm.ex:83-93`; `reconcile.ex:157` |
| R20 | `tera_pack?/1` re-reads every template twice (`templates/1` called twice) and detects Tera by regex `\{\{\|\{%` on any frontmatter file, so an EEx pack whose body contains `{%{...}` text can route to `PackFrontmatter.Tera` | UNVERIFIED | `pack_frontmatter/sync.ex:77-84`; cf. `render/tera_wasm.ex:50-57` (same hazard documented for `.eex`) |
| R21 | Test coverage: EEx has only property tests; `Render.Tera` has 14 tests, none for error paths (missing endfor, unknown filter/tag, malformed for); `PackFrontmatter.Tera` covers error paths; WASM has 4 render tests, no test of `ERROR:` prefix collision (a template that legitimately renders text starting `ERROR: `) | UNVERIFIED | `test/render_tera_test.exs:6-135`; `tera_test.exs:55,102,152`; `tera_wasm_test.exs:21-39`; `render/tera_wasm.ex:126-127` |
| R22 | `TeraWasm` treats any output beginning `ERROR: ` as an error, so a valid template whose output begins with that text is misreported | UNVERIFIED | `render/tera_wasm.ex:126-128` |

## Next

1. Install Elixir/Rust and run `scratchpad`-style probes per finding (R02, R07, R08, R10,
   R11, R13, R16, R22 are one-line `render/2` calls); promote or refute each.
2. Decide the engine contract: delete `Render.Tera` (R04) or document it as test-only, and
   correct `docs/status.md:147` (R05).
3. Add a differential test rendering one `.tmpl` through `PackFrontmatter.Tera` and
   `TeraWasm`, asserting byte parity or a typed refusal (R06, R07, R14).
4. Add mixed-syntax `.tmpl` and EEx-`to:`/Tera-body cases to `tera_wasm_test.exs` (R18, R19).
5. Wrap `Jason.encode!` and stop the Wasmex instance in `TeraWasm.render/2` (R15, R16).
6. File findings that need code changes through the sJira admission path, not by hand.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/status.md` (row at line 147)
- `lib/ggen_igniter/render/tera_wasm.ex` (dispatch predicate and its `.eex` hazard note)
- `docs/reference/cli/sync.md`
