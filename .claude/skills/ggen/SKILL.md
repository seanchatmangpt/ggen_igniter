---
name: ggen
description: Use when replacing a hand-rolled Rust CLI (ad hoc clap/`fn main()`) with a ggen-marketplace-generated clap-noun-verb CLI, or when asked to make a CLI's domain logic reusable/generated while keeping the real logic hand-written — walks the six-pack pipeline (schema/crate/routing/behavior/boundary/verification), the RDF individual graph shape, and where hand-written domain logic goes (`cnv:CustomBehavior` → `custom_handlers.rs`, generated once, never overwritten).
---

# ggen-marketplace: generate a clap-noun-verb CLI, keep the domain logic hand-written

`~/ggen-marketplace` is a ggen pack registry. One pack family —
`clap-noun-verb-*-pack` — is a "zero-code compiler": you describe a CLI as an
RDF graph (nouns, commands, arguments, behaviors), `ggen sync run` manufactures
every Rust file, and the **only** hand-written Rust it ever asks you for is
domain logic explicitly marked `cnv:CustomBehavior`, scaffolded once into
`src/custom_handlers.rs` (generated `unless_exists: true` — never overwritten
on re-sync).

This is the mechanism to reach for whenever a task says "replace this CLI with
ggen-marketplace clap-noun-verb but keep the domain logic" — that phrase maps
directly onto `cnv:CustomBehavior`.

## The six packs (in generation order)

| Pack | Emits |
|---|---|
| `clap-noun-verb-schema-pack` | No individuals — just the RDF vocabulary (`cnv:Cli`, `cnv:Noun`, `cnv:Command`, `cnv:Argument`, `cnv:Behavior` subclasses) and fail-closed SPARQL gates in `gates/*.rq` — each is a `SELECT` that returns zero rows on a clean graph and any returned row is a refusal, validated before anything renders. |
| `clap-noun-verb-crate-pack` | `Cargo.toml`, `src/main.rs`, `src/lib.rs`. |
| `clap-noun-verb-routing-pack` | `src/generated_cli.rs` — `#[verb]` functions per command, argument parsing, dispatch. |
| `clap-noun-verb-behavior-pack` | `src/generated_behavior.rs` — the closed interpreter for non-custom behaviors (static JSON, echo, expression, filesystem read/write, refusal). |
| `clap-noun-verb-boundary-pack` | `src/generated_boundaries.rs` — sandboxed filesystem adapters (atomic write, symlink refusal, BLAKE3 receipts) for behaviors that touch disk. |
| `clap-noun-verb-verification-pack` | Real compiled-binary tests + `command-reference.md`, generated from the same graph as production routes — no mocks. |

`clap-noun-verb-pack` (no suffix) is the deprecated predecessor of all six —
don't point new work at it.

## Behavior kinds — the vocabulary is closed on purpose

A `cnv:Command` has exactly one `cnv:Behavior`:

- `cnv:StaticJsonBehavior` — returns a fixed `cnv:jsonValue`.
- `cnv:EchoBehavior` — returns the command's typed arguments as JSON.
- `cnv:ExpressionBehavior` — one arithmetic/string op (`add`/`subtract`/`multiply`/`divide`/`concat`) over two named arguments.
- `cnv:FilesystemWriteBehavior` / `cnv:FilesystemListBehavior` — atomic JSON persistence/read through a `cnv:FilesystemBoundary`.
- `cnv:RefusalBehavior` — fail closed with a declared code/message.
- `cnv:CustomBehavior` — **the escape hatch**. Routes to
  `crate::custom_handlers::<noun>_<verb>(inputs: Map<String, Value>) -> Result<Value>`,
  a real hand-written function. This is the *only* seam the compiler emits;
  `generated_cli.rs`'s own test suite asserts no other `handlers::` seam
  exists and that every custom command calls its own (not a neighbor's)
  handler.

If the CLI you're replacing has real logic (subprocess calls, network I/O,
parsing an external tool's output, anything beyond "shuffle these arguments
into JSON") — that logic becomes one `cnv:CustomBehavior` command, and its
body is what you port into `custom_handlers.rs` essentially unchanged.

## Worked shape — converting an ad hoc CLI

Say you have a `fn main()` binary with subcommands `foo status` and
`foo run --target X`, where `status` is a trivial fixed response and `run`
shells out to a real external tool (the actual domain logic worth keeping).

1. **Write the individual graph** (e.g. `ontology/foo-cli.ttl` in the consumer repo):

```turtle
@prefix cnv: <https://clap-noun-verb.dev/ontology#> .

cnv:FooCli a cnv:Cli ;
    cnv:crateName "foo-cli" ; cnv:binaryName "foo" ;
    cnv:version "0.1.0" ; cnv:edition "2024" ; cnv:rustVersion "1.85" ;
    cnv:about "Foo CLI, generated." ;
    cnv:hasNoun cnv:FooNoun .

cnv:FooNoun a cnv:Noun ; cnv:name "foo" ; cnv:about "Foo operations." ;
    cnv:hasCommand cnv:FooStatus, cnv:FooRun .

cnv:FooStatus a cnv:Command ; cnv:name "status" ; cnv:about "Report status." ;
    cnv:belongsToNoun cnv:FooNoun ; cnv:hasBehavior cnv:FooStatusBehavior .
cnv:FooStatusBehavior a cnv:StaticJsonBehavior ;
    cnv:jsonValue "{\"status\":\"ok\"}" .

cnv:FooRun a cnv:Command ; cnv:name "run" ; cnv:about "Run the real tool." ;
    cnv:belongsToNoun cnv:FooNoun ; cnv:hasBehavior cnv:FooRunBehavior ;
    cnv:hasArgument cnv:FooRunTarget .
cnv:FooRunTarget a cnv:Argument ; cnv:name "target" ; cnv:about "Target to run against." ;
    cnv:fieldName "target" ; cnv:valueKind "string" ; cnv:required true ; cnv:position 0 ;
    cnv:longFlag "target" ; cnv:testValue "example" .
cnv:FooRunBehavior a cnv:CustomBehavior .   # <- this is the real logic
```

2. **Wire the consumer `ggen.toml`**:

```toml
[project]
name = "foo-cli"

[ontology]
source = "ontology/foo-cli.ttl"

[packs]
clap-noun-verb-schema-pack       = { path = "../ggen-marketplace/packs/clap-noun-verb-schema-pack" }
clap-noun-verb-crate-pack        = { path = "../ggen-marketplace/packs/clap-noun-verb-crate-pack" }
clap-noun-verb-routing-pack      = { path = "../ggen-marketplace/packs/clap-noun-verb-routing-pack" }
clap-noun-verb-behavior-pack     = { path = "../ggen-marketplace/packs/clap-noun-verb-behavior-pack" }
clap-noun-verb-boundary-pack     = { path = "../ggen-marketplace/packs/clap-noun-verb-boundary-pack" }
clap-noun-verb-verification-pack = { path = "../ggen-marketplace/packs/clap-noun-verb-verification-pack" }
```

3. **Run `ggen sync run`.** It manufactures `Cargo.toml`, `src/main.rs`,
   `src/lib.rs`, `src/generated_cli.rs`, `src/generated_behavior.rs`,
   `src/generated_boundaries.rs`, tests, and — because `FooRunBehavior` is
   `cnv:CustomBehavior` — a **scaffolded, one-time**
   `src/custom_handlers.rs` containing:

   ```rust
   /// `foo run` -- Run the real tool.
   pub fn foo_run(inputs: Map<String, Value>) -> Result<Value> {
       let _ = inputs;
       todo!("implement foo run")
   }
   ```

4. **Port the real domain logic** into that `todo!()` body — pull `target`
   out of `inputs`, call the same subprocess/library code the original
   `fn main()` called, return the result as `serde_json::Value`. This file is
   never regenerated once it exists, so hand edits are permanent.

5. **Re-run `ggen sync run`** to confirm the projection is stable (idempotent
   — re-running with no graph changes must produce a byte-identical diff,
   except `custom_handlers.rs` which is left untouched either way).

6. Run the consumer's real test suite — `clap-noun-verb-verification-pack`
   generated real compiled-binary tests (success, refusal, missing-required-arg,
   unknown-command) from the same graph, no mocks.

## Where to look for ground truth (don't trust this summary blindly — re-derive if the pack has moved on)

- `~/ggen-marketplace/packs/clap-noun-verb-schema-pack/ontology.ttl` — full property list (positional args, env vars, aliases, groups, `requires`/`conflictsWith`, etc.).
- `~/ggen-marketplace/packs/clap-noun-verb-schema-pack/gates/*.rq` — what actually fails admission (read these before assuming a graph shape is legal).
- `~/ggen-marketplace/packs/clap-noun-verb-crate-pack/qualification/consumer.ttl` and `clap-noun-verb-specimen-pack/ontology.ttl` — small positive specimens to copy from.
- `~/ggen-marketplace/packs/clap-noun-verb-routing-pack/templates/generated_cli.rs.tmpl` — exact dispatch shape, including the `custom_handlers::` call site and its own generated tests.
- `~/ggen-marketplace/docs/tutorials/consume-a-pack.md` — the generic "any pack" consumption recipe this skill specializes.
- `~/ggen-marketplace/docs/jira/v26.8.19/01-TICKET-retire-clap-noun-verb-legacy.md` — confirms the six-pack split is current and `clap-noun-verb-pack` (no suffix) is deprecated.

## When NOT to reach for this

- A CLI with no real domain logic at all (pure argument-shuffling, static
  responses) is a good zero-code candidate end to end — no `CustomBehavior`
  needed.
- A CLI whose "domain logic" is actually most of the program (e.g. it's a
  thin wrapper around one big function) may not be worth the RDF-graph
  overhead — plain `clap-noun-verb` with hand-written `#[verb]` functions
  (see chicago-tdd-tools' `playground/src/cli/*.rs` for that simpler pattern)
  is the better fit when there's no zero-code surface worth generating.
