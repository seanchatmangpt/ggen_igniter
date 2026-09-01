# Adversarial Verification: Mock / Placeholder / Scaffolding Discipline

Repo: /Users/sac/ggen_igniter
Real `mix.exs` version (as read from disk, not assumed from the task title):
`mix.exs:9` → `version: "26.8.27",`
(Task framing said "v26.7.27" — that is NOT what mix.exs says. Reporting the real value per instructions: **26.8.27**.)

Date of this verification pass: 2026-08-27. Independent pass — no builder reasoning consulted, only real disk state and commands run in this session.

---

## 1. Mock-library usage sweep

Command run exactly as specified:

```
grep -rnE "Mock|mock\(|patch\(|monkeypatch" test lib native
```

**Result: zero hits.** (Confirmed by direct execution — empty output, exit with no matches.)

Followed up with broader case-insensitive sweeps to rule out variants the exact-case regex could miss (`Mox`, lowercase `mock`, etc.), since Elixir's common mocking library is `Mox`, not `Mock`:

```
grep -rnE "Mox|mox" test lib native        → 1 hit
grep -rniE "mock" test lib native          → 49 hits
```

### Verdict: CONFIRMED — no mock-library usage found in test/lib/native

Every one of the 49 case-insensitive hits was inspected individually. Classification:

| File:line | Text | Classification |
|---|---|---|
| `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs:47` | `` `unittest.mock`/`Mox`/interaction-based assertion of any kind, per`` | Docstring naming banned patterns (disclosure of testing discipline), not usage |
| `test/*.exs` (28 files, e.g. `ggen_igniter_sync_qlever_engine_test.exs:3`, `actuate_inject_test.exs:3`, `ggen_igniter_oxigraph_engine_test.exs:3`, `ggen_igniter_cross_engine_equivalence_properties_test.exs:3,62`, `ggen_igniter_doctor_fixes_test.exs:3,11`, `ash_r2rml_gate_integration_test.exs:7,30`, `ash_r2rml_gate_qlever_test.exs:3,11`, `test/e2e/lifecycle_test.ex:14,216`, `test/e2e/support/e2e_case.ex:7`, etc.) | Moduledoc/comment text asserting "Chicago-style," "no mocks," "not mocked," "never a silent mock substitution," "no mocking of the shell" | Disclosure/self-description of testing discipline — not a mock-library call |
| `test/ggen_igniter_pack_fetch_test.exs:5` | "mocked HTTP layer. Tagged `:requires_network`" | Comment describing what this test *avoids* doing (real network call is used, tagged so it can be skipped) — not a mock |
| `lib/ggen_igniter/doctor_fixes.ex:23` | "no mocks) independent of whatever project is actually loaded" | Moduledoc disclosure (verified in full context, see below) — not a mock |
| `native/ggen_graph_nif/target/release/deps/rand-*.d` and `target/debug/deps/rand-*.d` (5 hits) | Cargo dependency-file (`.d`) paths pointing into `~/.cargo/registry/.../rand-0.9.5/src/rngs/mock.rs` | Third-party vendored build artifact (rustc `.d` dep-tracking file listing the `rand` crate's own `rngs/mock.rs` source file, which implements a mock RNG for testing — this is upstream `rand` crate internals pulled in via Cargo's build cache, not code this project wrote or a testing-discipline violation) |

`lib/ggen_igniter/doctor_fixes.ex:23` full context read directly (lines 1-25): the moduledoc states functions are "trivially testable against a real temp directory fixture (Chicago-style: real files on disk, real assertions on the resulting file content, no mocks)". This is an accurate, disclosed description of the module's own design, not an actual mock usage.

No `patch(`, `monkeypatch`, `unittest.mock`, `Mock(`, or `Mox` **usage** (as opposed to being named/disclaimed in prose) exists anywhere in `test/`, `lib/`, or `native/` source. The `native/ggen_graph_nif/target/` directory (3,304 files) is 100% Cargo build output (`.d`, `.rlib`, `.rmeta` files and vendored dependency sources under `target/{debug,release}`) — not source this project authored; it was swept by the literal `grep -r ... native` command as instructed, and every hit within it is the third-party `rand` crate's own `mock.rs`, not this project's code.

---

## 2. TODO / FIXME / unimplemented / not_implemented / placeholder / stub sweep (lib/ + native/src, test/ excluded per instructions)

Command run:

```
grep -rnE "TODO|FIXME|unimplemented|not_implemented|placeholder|stub" lib native/ggen_graph_nif/src
```

**6 hits, all inspected individually:**

### 2.1 `lib/ggen_igniter/ontology.ex:3`
> "Loads a Turtle ontology file into an in-memory RDF.Graph via the `rdf` library. Real IO/parsing, no fixture stubbing."

Disclosure that this code does NOT stub — asserting the opposite of a placeholder. **Not a placeholder.**

### 2.2 `lib/ggen_igniter/engine.ex:106`
> "...before ever reaching `GgenIgniter.Query.Qlever.load_store!/2` (whose own stub, compiled when `:gno` is missing, raises the same message)."

Refers to the conditional-compilation fallback module in `qlever.ex` (see 2.5/2.6 below) that raises a clear `RuntimeError` when the optional `:gno` dependency isn't present. Read in full context (`lib/ggen_igniter/engine.ex:90-110`): this is describing a real, working guard-rail design (fail loud with an actionable message when an optional dep is absent), not an accidental unfinished implementation. **Disclosed, honest fallback — not a masquerading placeholder.**

### 2.3 `lib/ggen_igniter/native/graph_nif.ex:11`
```elixir
@doc "NIF stub -- replaced by the loaded native implementation at runtime."
@spec query_turtle(String.t(), String.t()) ::
        {:ok, [%{optional(String.t()) => String.t()}]} | {:error, String.t()}
def query_turtle(_turtle, _sparql), do: :erlang.nif_error(:nif_not_loaded)
```
This is the standard, idiomatic Rustler NIF-loading boilerplate (every Rustler-based Elixir module has an Elixir-side function body that only exists to be overwritten by `:erlang.nif_error/1` until the native library loads and replaces it). This is a well-known, correct pattern, not a disguised unfinished feature. **Not a placeholder masquerading as done — standard Rustler idiom, disclosed as such in its own `@doc`.**

### 2.4 `lib/ggen_igniter/query/qlever.ex:15` and `:118`
Read in full context (`qlever.ex:1-30` and `95-130`). The file uses a compile-time `if Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do ... else ... end` branch:
- When `:gno` (an `optional: true` dep) IS loaded: the real module compiles, using real `Gno.Store.Adapters.Qlever` + real `SPARQL.Client.query/2` (a real hex-published rdf-elixir dependency), with real row-unwrapping logic (`unwrap_row/1`, `unwrap/1` handling `RDF.IRI`, `RDF.Literal`, `RDF.BlankNode`).
- When `:gno` is NOT loaded: a fallback module compiles instead, whose `load_store!/2` and `run/2` deliberately `raise RuntimeError` with a clear, actionable message ("ggen_igniter: :gno is required for --engine qlever ... add {:gno, \"~> 0.1\"} to your own mix.exs deps") — loud failure, not silent success.

This is exactly the `no-overclaiming-rust.md` floor's required shape: "Unimplemented ≠ stub-that-returns-success; unimplemented = typed `Err`/raise, loud not quiet." **Verdict: honest, disclosed conditional-compile fallback, not a hidden gap.**

### 2.5 `native/ggen_graph_nif/src/lib.rs:6`
```rust
//! ... `RemoteEngine` (the wasm32-safe path) is out of scope here: its
//! `query()` is a real `todo!()` stub with a disclosed sync/async architecture blocker --
//! that is separate, still-in-progress work on the WASM side, not something this native
//! NIF can or should route around.
```
Checked directly: `RemoteEngine` does **not exist anywhere in this repo's `native/ggen_graph_nif/src/`** (confirmed via `grep -rn "RemoteEngine" native/ggen_graph_nif/src/` → only this one comment line matches; `grep -rn "todo!\|unimplemented!"` over the same src/ tree → only this comment line matches, zero actual `todo!()`/`unimplemented!()` macro invocations in the crate's real Rust code). The comment is referencing external/out-of-repo work (elsewhere in the `~/ggen`/wasm ecosystem this project vendors from), explicitly labeled "out of scope here."

**Verdict: UNVERIFIABLE as a claim about this repo** (the referenced `RemoteEngine`/`todo!()` genuinely is not present in `ggen_igniter`'s own source tree, so there is nothing in THIS repo to confirm or refute — the comment is honest about pointing outside this codebase's boundary). What IS confirmed: this crate's own `lib.rs` `query_turtle/2` function (lines 29-47) is a real, complete implementation — calls real `OxigraphEngine::from_turtle`, real `.query()`, real row-to-HashMap conversion, real `Ok`/`Err` NIF encoding — no `todo!()`, no `unimplemented!()`, no stub return value anywhere in the actual executable path.

---

## Summary

| Check | Verdict |
|---|---|
| Real mock-library usage (`Mock`, `mock(`, `patch(`, `monkeypatch`) in test/lib/native | **CONFIRMED clean** — zero real usages; all 49 case-insensitive "mock" hits are either testing-discipline disclosure prose or third-party `rand` crate build artifacts under `native/.../target/` |
| TODO/FIXME/unimplemented/not_implemented/placeholder/stub in lib/ + native/src | **CONFIRMED** — all 6 hits are honest disclosures (Rustler NIF-loading idiom, compile-time optional-dependency fallback that raises loudly, a comment pointing at genuinely out-of-repo/out-of-scope external work). None found to be an accidental unfinished implementation silently masquerading as complete. |
| Repo version per real `mix.exs` | **26.8.27** (not "26.7.27" as stated in the task framing — reported as instructed, not assumed) |

No further action taken — this is a read-only verification report; nothing in the repository was modified.
