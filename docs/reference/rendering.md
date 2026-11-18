# Template rendering (EEx / Tera)

Standing: PASS (focused suite green 2026-11-18)

Four render surfaces exist. Only two are on production sync spines; the
other two are intentional auxiliaries. This page discloses the Tera-vs-EEx
divergences so they are not mistaken for unfinished wiring.

## Dispatch matrix (production)

| Path | Engine | How selected |
|---|---|---|
| `GgenIgniter.Reconcile.run/1` | `Render.TeraWasm.render_for!/4` | `.tera` → WASM Tera; `.tmpl` → WASM Tera unless body is EEx-syntax-only (`<%` present, no `{{`/`{%`/`{#`); else EEx |
| `GgenIgniter.Reactors.ReconcileReactor` render step | same `render_for!/4` | identical predicate |
| `GgenIgniter.PackFrontmatter.Sync` | `PackFrontmatter.Tera.render/2` | frontmatter packs (`templates/*.tmpl` / `*.tera`) with Tera bodies |
| Direct / reports / health | `GgenIgniter.Render.render/2` | stdlib `EEx.eval_string/2` only |

Shared predicate: `GgenIgniter.Render.TeraWasm.tera_template?/2`. Extension-
driven on purpose — content-sniffing `{%` on `.eex` misroutes real fixtures
that contain Elixir `%{...}` / `{%{...}` map syntax (see
`priv/ggen/ash-manufacture-pack/templates/manufacture.ex.eex`).

## Engines

1. **`GgenIgniter.Render`** — stdlib EEx. Default for `*.eex` and unknown
   extensions. Atom/keyword bindings (SPARQL columns admitted via
   `BindingKeys.atomize!/1`).
2. **`GgenIgniter.Render.TeraWasm`** — real `tera` crate (`tera = "1.20"`)
   compiled to `wasm-artifacts/tera_wasm_renderer.wasm`, hosted by `wasmex`
   (WASI). Full Tera syntax the crate supports. Context is JSON-encoded
   (string keys after encode); keyword lists are normalized to maps first.
3. **`GgenIgniter.PackFrontmatter.Tera`** — hand-rolled Tera *subset* used
   only by `PackFrontmatter.Sync` for ggen-marketplace frontmatter packs.
   Supports the constructs those packs actually use (macros, `set_global`,
   whitespace control, named filters/tests). Unsupported constructs raise
   `ArgumentError` (never silent pass-through). No HTML autoescape (pack
   templates are `.tmpl`, matching real Tera's non-HTML default).
4. **`GgenIgniter.Render.Tera`** — smaller hand-rolled subset
   (`capitalize`, `filter(attribute=,value=)`, for/if/comments). **Not
   called by any production pipeline.** Kept as a standalone library /
   historical marketplace smoke path; do not assume sync routes here.

## Intentional divergences (do not "fix" without an operator decision)

| Divergence | Why it remains |
|---|---|
| Reconcile/Reactor use **WASM Tera**; PackFrontmatter sync uses **Elixir subset Tera** | PackFrontmatter needs fail-closed subset errors and zero WASI cost for pack authoring loops; Reconcile needs byte-faithful real `tera` for marketplace `.tmpl`/`.tera`. Unifying would either drop subset refusals or pay wasm on every pack_frontmatter render. |
| `Render.Tera` is unwired | Superseded for pipeline by `TeraWasm`; deleting it is a separate cleanup (tests still pin the subset). |
| `.tmpl` with EEx-only body still goes through EEx | Legacy EEx-in-`.tmpl` must not break; predicate is `eex_syntax_only?/1`. |
| EEx bindings are atom keys; TeraWasm context is JSON string keys | EEx requires atom-keyed assigns; WASM ABI is JSON. Call sites already flatten SPARQL rows before either path. |
| TeraWasm does not HTML-autoescape | Matches packing convention (code/Markdown `.tmpl`, not `.html`). |
| `PackFrontmatter.Tera` filter/test vocabulary is closed | Anything outside the moduledoc list raises; real `tera` would accept a larger set — pack templates must stay inside the subset or move to the Reconcile/TeraWasm spine. |
| Comparison ops in `PackFrontmatter.Tera` use a closed operator table | Parser only emits `== != < > <= >=`; no dynamic atom mint from template text. |

## Rebuild

```sh
cd native/tera_wasm_renderer && cargo build --target wasm32-wasip1 --release
cp target/wasm32-wasip1/release/tera_wasm_renderer.wasm ../../wasm-artifacts/
```

Nothing regenerates the wasm artifact automatically. See
`wasm-artifacts/README.md`.

## Focused gate

```sh
mix test test/ggen_igniter/render/tera_wasm_test.exs \
         test/render_tera_test.exs \
         test/ggen_igniter/pack_frontmatter/tera_test.exs \
         test/ggen_igniter_render_properties_test.exs
```

Integration coverage for mix-subprocess marketplace packs lives in
`test/ggen_igniter_pack_marketplace_sync_test.exs` (`@moduletag :integration`,
excluded from the default gate).
