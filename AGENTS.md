# AGENTS.md

Single invariant: **if Ash already knows how to manufacture the thing, the agent is not
allowed to reinvent it.** Ash and Igniter ship generators that own semantic mutations
spanning several files at once. An agent that hand-writes the one file it can see
performs a fraction of that mutation and leaves the project in a state that compiles and
is still wrong.

This file is doctrine for agent behavior on Ash surfaces. Repo architecture, pipeline
internals, gate/verification discipline, and worktree protocol live in `CLAUDE.md` — read
it too; this file does not restate it.

## The failure this prevents

In the Next Read / xaas attempt an agent concluded it knew Ash syntax and wrote
`lib/xaas/library/book.ex` (and its domain module) directly with an editor tool.

What looked right: the file had `use Ash.Resource`, an `attributes do` block with typed
`attribute` calls, `actions do defaults [:read, :create, :update, :destroy] end`, a
`postgres do table ... repo ... end` block. It was syntactically valid Elixir and it
matched every Ash example the agent had ever seen.

What was actually wrong — each item is a mutation owned by a generator that never ran:

- **`ash_domains` registration.** `mix ash.gen.domain` writes the domain module *and*
  appends it to `config :app, ash_domains: [...]` in `config/config.exs`. Hand-writing the
  module leaves the domain unregistered; Ash cannot discover it and `mix ash.codegen`
  sees no resources.
- **create/update accept-list derivation.** `mix ash.gen.resource` derives the `accept`
  lists on `:create`/`:update` from the attributes marked public. Hand-written `defaults`
  produce actions whose accepted-attribute set silently diverges from the public-attribute
  set the ontology declares.
- **`base_resources` config.** `mix ash.gen.base_resource` writes the base module and the
  `config :app, :base_resources` entry that `--base` later depends on being *loaded*. A
  hand-written `use Ash.Resource` header is not the base resource and no config exists.
- **Repo wiring.** `mix ash_postgres.install` wires `Repo`, `AshPostgres.DataLayer`
  config, supervision tree entry, and dev/test repo config. None of that is in the
  resource file, so none of it happens.
- **Migration snapshot.** `mix ash.codegen` diffs against
  `priv/resource_snapshots/`. A resource that never went through the generator flow has
  no snapshot baseline, so the first codegen run emits a wrong or empty diff.

Five real defects, zero compile errors, one plausible-looking file.

## The admitted path

```text
ontology fact  ->  ggen_igniter  ->  upstream Ash/Igniter generators  ->  generated
                                                                          projection
```

1. **Ontology fact.** The semantic element (resource, attribute, relationship, action) is
   a triple in the pack's `ontology.ttl` — see
   `test/fixtures/ash_manufacture_pack/ontology.ttl`. The ontology also carries a
   `GeneratorCapability` envelope per generator (standing / admitted / phase / evidence).
2. **ggen_igniter.** SPARQL gates read those facts and render exactly one composed
   `Igniter.Mix.Task` at `lib/mix/tasks/<app>.manufacture.ex`. No ggen_igniter template
   renders Ash resource source.
3. **Upstream generators.** That task calls the real generators via
   `Igniter.compose_task/4` — never by shelling out. Composition is the reason
   `--ignore-if-exists` is tolerated at all: the CLI path validates switches strictly
   (`igniter/lib/igniter/util/info.ex:354-368`), the compose path does not
   (`igniter/lib/mix/task.ex:237`), and Ash itself relies on that
   (`ash.gen.resource.ex:185`).
4. **Generated projection.** The resources, domain, config, and migrations are outputs of
   that run, not inputs an agent authors.
5. **Handwritten residue** exists only for what no admitted generator can express, and
   only after an explicit `UNSUPPORTED(generator capability)` row in the ontology names
   the exact semantic element. See "When the generator cannot express it".

Manufacture is two mix invocations, not one, because `ash.gen.resource --base` requires
`base_resources` config to already be **loaded**. The retrofit leg of
`ash.gen.base_resource` (`ash.gen.base_resource.ex:59`) cannot be relied on instead: it
short-circuits on the `included_all_elixir_files?` assign
(`igniter.ex:1112-1123`), which any `find_module` full scan sets as a side effect
(`igniter/project/module.ex:475`), so in a composed run it silently does nothing.

## What is structurally refused

`.claude/hooks/refuse-handwritten-ash.sh` is wired as a `PreToolUse` hook on `Edit|Write`
in `.claude/settings.json`. It reads the tool call as JSON on **stdin** — the real hook
protocol — and exits 2 (blocking the call, stderr shown to the agent) when the body
contains either:

- `use Ash.Resource` or `use Ash.Domain`, or
- a base-resource header: `otp_app: :atom` **and** `domain: SomeModule` together.

Environment variables (`CLAUDE_FILE_PATH` / `CLAUDE_TOOL_INPUT`) are a fallback for
clients that expose the call that way. An earlier revision read only those, which meant it
saw an empty string under the real protocol and exited 0 — it **failed open**, while its
qualification cases passed against a code path that never runs. That is why the harness
now drives it through real JSON: testing the wrong interface is worse than not testing,
because it manufactures a standing.

An unparseable payload does **not** fail open. The guard falls back to scanning the raw
bytes, because a malformed tool call is exactly when it is least entitled to assume
innocence. The same fallback fires for a payload that parses but yields neither a path nor
a body, so a tool call shaped unlike the protocol is refused rather than skipped.

Three extraction rules, each of which closes a measured bypass rather than a supposed one:

- **Body: recursive walk, not key lookup.** Every string leaf under `tool_input` is joined,
  except the path keys and `old_string`/`old_str`. Reading four fixed keys
  (`content`, `new_string`, `new_str`, `replace_all_string`) let a MultiEdit-shaped call
  carry a resource under `edits[].new_string` and exit 0 — a non-empty path plus an empty
  body fell past the raw-payload fallback. Excluding the pre-edit side is deliberate: an
  Edit that **deletes** a resource header must not be refused.
- **Path: normalised before matching.** The allowlist glob-matches the path, so
  `/x/lib/mix/tasks/../app/book.ex` matched the mix-tasks row and resolved to an ordinary
  `lib/` resource. Paths are `normpath`-ed first; a `..` that survives normalisation
  forfeits the allowlist entirely rather than matching by luck.
- **Body: flattened before matching.** `grep` is line-oriented, so `use Ash.` + newline +
  `Resource` — one valid alias continuation — was two records and never matched. Newlines
  and tabs collapse to spaces first, and `use` is allowed to be followed by `(` so the
  parenthesised macro call `use(Ash.Resource, domain: X)` is caught too.

Allowlisted paths, which exit 0 before the detector runs:

| Pattern | Why it is allowed |
|---|---|
| `*/priv/ggen/*/templates/*`, `*/test/fixtures/*/templates/*` | packs model the constructs |
| `*/lib/mix/tasks/*` | the composed manufacture task composes the generators |
| `*/test/fixtures/ash-lifecycle-pack/*` | ggen_igniter's own rendering fixtures |
| `*/deps/*`, `*/_build/*` | not source surfaces |
| `*/config/*.exs`, `*/test/*.exs` | these name resources without declaring them |

The templates row is anchored to the two real pack roots. An unanchored `*/templates/*`
allowed a resource in any directory named `templates` anywhere, including `lib/`.

Only `.ex` and `.exs` paths are inspected. A call with **no** `file_path` is still
inspected rather than skipped, so a client that omits the path cannot smuggle a resource
past the guard.

The table previously also listed `*.eex`, `*.ttl`, `*.rq`, `*.md`. Those rows were
**unreachable**, not policy: the extension gate above exits 0 for every path that is not
`.ex`/`.exs`, several branches earlier, and a file named `foo.ex.eex` ends in `.eex` and
takes that arm. They have been deleted so the table states a decision the code actually
makes.

## The sibling destructive-command guard

`.claude/settings.json` also carries a `PreToolUse` hook on the `Bash` matcher that refuses
`rm -rf`, `git reset --hard`, and `git push … --force`. It read only `$CLAUDE_TOOL_INPUT` —
the identical defect recorded above as found and fixed in the Ash guard — so under the real
protocol it saw an empty string and exited 0 for `rm -rf`. It now reads stdin first,
extracts `tool_input.command`, and falls back to scanning the raw payload and then the
environment variable. Verified by `test/ggen_igniter_agent_guard_test.exs`, which runs the
exact command string read out of `settings.json` rather than a restatement of it, so an
edit reintroducing the env-only read fails a test instead of passing one.

To see it fire, drive it the way the hook runner does:

```bash
python3 -c 'import json;print(json.dumps({"tool_name":"Write","tool_input":{
  "file_path":"/tmp/book.ex","content":"defmodule B do\n  use Ash.Resource\nend"}}))' \
  | .claude/hooks/refuse-handwritten-ash.sh ; echo "exit=$?"   # exit=2
```

**This is a guard, not a proof.** It pattern-matches file content with `grep -E`, so its
residue is everything that names `Ash.Resource` without spelling it. Known-open, each
measured against the current hook rather than supposed:

- **`alias Ash.Resource, as: AR` then `use AR`** — exit 0, measured. The refused token
  never appears in the body. Not closable by pattern matching: it needs a parser that
  resolves aliases, which is a compiler, not a hook.
- **A resource assembled by macro or `Module.concat/1`** — exit 0, measured. Same reason:
  the declaration only exists after expansion.
- **A `cat > lib/app/book.ex <<'EOF'` heredoc** — exit 0, measured. This is routed to the
  `Bash` matcher, whose guard refuses destructive commands, not Ash writes. Adding an
  `Ash.Resource` pattern to that regex would also block `grep`-ing for the string, which
  is how this guard is itself verified, so it is left open deliberately.
- **An allowlisted path used for something it was not allowlisted for** — exit 0, by
  design. `*/lib/mix/tasks/*` must stay open for the composed manufacture task.
- **A resource written by a tool outside the `Edit`/`Write`/`Bash` matchers** — UNKNOWN,
  not exercised.

The first two are not closable by pattern matching at all: the invariant is enforced by
doctrine, and the hook only makes the most likely violation expensive. Listing the residue
is the point — a guard whose limits are unstated gets read as a proof.

`test/ggen_igniter_agent_guard_test.exs` is the ExUnit falsifier: 25 real-subprocess cases
over the real stdin protocol, covering each closed bypass, each allowlist row, the
fail-closed paths, and the sibling `Bash` guard. Before it existed the hook was exercised
only by four `qualify.sh` cases, all `tool_name` `Write` with a `content` key — one payload
shape, which is how four bypasses survived a green qualification.

## Worked example

Adding an `isbn` attribute to `Book`.

1. Add the fact to the pack ontology (`ontology.ttl`) — nothing else:

```turtle
amp:BookIsbnAttribute a amp:Attribute ;
    amp:attributeOf amp:BookResource ;
    amp:attributeName "isbn" ;
    amp:attributeType "string" ;
    amp:isPublic true .
```

2. Re-render the composed manufacture task from the fact:

```bash
mix ggen_igniter.sync --pack-dir test/fixtures/ash_manufacture_pack
```

3. Run the real upstream generators through it, both phases:

```bash
mix book_library.manufacture --phase base --yes
mix book_library.manufacture --phase core --yes
```

4. Assert idempotency with Igniter's own `--check`, which `System.halt()`s on any change,
   warning, issue, queued task, move, or rm (`igniter.ex:1293-1330`). Exit code alone is
   not an oracle — `do_or_dry_run` returns `:issues` without halting
   (`igniter.ex:1279-1281`), which is why `--check` is the assertion:

```bash
mix book_library.manufacture --phase base --check   # must exit 0
mix book_library.manufacture --phase core --check   # must exit 0
```

Note `mix ash.codegen --yes` is broken at ash 3.33.1 / ash_postgres 2.13.1:
`ash.codegen` is a plain `Mix.Task` that forwards argv verbatim (`ash.codegen.ex:36`) to
`ash_postgres.generate_migrations`, an Igniter task with no `yes` switch, so strict
validation rejects `--yes : Unknown option`. Use `mix ash.codegen --name <name>`.

## When the generator cannot express it

A generator that cannot express the semantic element is a **real result to record**, not a
license to hand-write silently. Protocol:

1. Add or update the `GeneratorCapability` row in the ontology for that generator with
   `standing` set to the honest status from the vocabulary
   (`UNKNOWN` | `PARTIAL_ALIVE` | `ALIVE` | `BLOCKED` | `BUILD_BROKEN` | `UNSUPPORTED`),
   `admitted false`, and an `evidence` value citing the exact `file:line` that establishes it.
2. Name the exact semantic element the row covers — not "custom expressions are broken"
   but the specific generator and the specific construct it fails to emit.
3. The composed task emits a typed refusal for that step, surfaced as a
   `capability_refused` OCEL event, so the refusal is in the process log rather than in a
   commit message.
4. Only then may irreducible residue be written by hand, scoped to exactly what the row
   names.

Real worked case — `mix ash.gen.custom_expression`, standing `BUILD_BROKEN`, admitted
false. The generator emits `args: [...]` (`ash.gen.custom_expression.ex:46`), while
`Ash.CustomExpression.__using__/1` raises `ArgumentError` with "You must provide arguments
for the custom expression" when `opts[:arguments]` is nil
(`ash/lib/ash/custom_expression.ex:113-115`). The generated module cannot compile. It was
not patched and it was not hand-written around: the capability row carries the refusal and
the step emits `capability_refused`.

## See Also

- `CLAUDE.md` — repo architecture, pipeline internals, verification gate, commit and
  worktree protocol. This file does not duplicate it.
- `docs/jira/v26.9.8/` — the manufacture case study: `01-BOOK-CASE-STUDY-FIXTURE.md`,
  `02-ASH-TASK-VALIDATION-MATRIX.md`, `04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md`,
  `06-OCEL-BEAM4PM-PROJECTION.md`, `REVIEW-ASH-MAINTAINER-LENS.md`.
- `test/fixtures/ash_manufacture_pack/` — the pack: ontology, SPARQL gates, and the
  template that renders the composed manufacture task.
- `test/fixtures/book_library/` — the manufactured fixture, with qualification evidence
  under `test/fixtures/.qualification/book_library/`.
- `.claude/hooks/refuse-handwritten-ash.sh` — the guard described above.
- `test/ggen_igniter_agent_guard_test.exs` — its ExUnit falsifier: real subprocess, real
  stdin JSON, real exit codes, for both this guard and the sibling `Bash` guard.
