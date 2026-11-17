# Lane 04: Actuate write safety, inject modes, path handling

Standing: UNVERIFIED

Read-only static exploration of `lib/ggen_igniter/actuate.ex` (504 lines),
`lib/ggen_igniter/injection.ex` (169 lines) and their call sites. No Elixir
toolchain exists in this sandbox (`which mix elixir erl` printed nothing), so
no test or experiment was run; every finding below is a source reading and is
UNVERIFIED as runtime behavior. `Actuate` itself performs no path validation.
Containment is enforced only by callers: the Reactor admit step and the
`semantic_jira` projection guard. Other callers write wherever the rendered
path points. `inject_content!/5` is a non-atomic direct write, and several edge
behaviors (CRLF, mode bits, symlinks) have no test in the four actuate-focused
test files inspected.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| A01 | write_file!/3 has no path containment | UNVERIFIED | actuate.ex:134-160 |
| A02 | Reconcile writes rendered :out with no escape guard | UNVERIFIED | reconcile.ex:157-165 |
| A03 | pack_frontmatter expands rel vs out_dir, no root check | UNVERIFIED | pack_fm/sync.ex:212 |
| A04 | Reactor admit uses ArtifactIdentity.within_root?/2 | UNVERIFIED | reactor.ex:2035 |
| A05 | projection guard is prefix-only, no symlink resolve | UNVERIFIED | projection.ex:303-316 |
| A06 | inject_content!/5 is direct File.write!, not atomic | UNVERIFIED | actuate.ex:316 |
| A07 | rename drops mode bits; symlink at path is replaced | UNVERIFIED | actuate.ex:168-180 |
| A08 | split on LF only; CRLF keeps \r, mixed endings | UNVERIFIED | actuate.ex:295-297,336 |
| A09 | nil marker on :before/:after: FunctionClauseError | UNVERIFIED | actuate.ex:342-346,444 |
| A10 | at_line: missing :line KeyError, non-integer crashes | UNVERIFIED | actuate.ex:303,449 |
| A11 | literal marker is substring match (# slot ~ # slot2) | UNVERIFIED | actuate.ex:446-447 |
| A12 | partial multi-line body not detected, re-spliced | UNVERIFIED | actuate.ex:479-503 |
| A13 | empty body inserts one blank line | UNVERIFIED | injection.ex:156-168 |
| A14 | unsupported MatchRule combos raise named errors | UNVERIFIED | injection.ex:78-105 |
| A15 | invalid regex marker raises raw Regex.CompileError | UNVERIFIED | injection.ex:137-143 |
| A16 | whole target read first; dir target raises File.Error | UNVERIFIED | actuate.ex:139-140 |
| A17 | skip_if non binary/Regex raises FunctionClauseError | UNVERIFIED | actuate.ex:202-203 |
| A18 | eval_code! rescues compile errors only; runtime raw | UNVERIFIED | actuate.ex:437-441 |
| A19 | hard kill leaves stray .ggen_igniter.tmp.N sibling | UNVERIFIED | actuate.ex:168-180 |
| A20 | tests exist: decision order, atomic, inject | UNVERIFIED | grep describe, 3 test files |
| A21 | no test hits: CRLF, symlink, EISDIR, mode bits | UNVERIFIED | grep -ln, 4 test files |

Evidence is source reading only; no command was run against these paths.

## Next

1. Install Elixir/Erlang (or run in CI) and execute `mix test test/actuate_test.exs
   test/actuate_inject_test.exs` to establish a real baseline for A20.
2. Write failing-first tests for A07 (mode bits, symlink target), A08 (CRLF), A09,
   A10, A12, A16, A17, then decide per item: fix, document, or BY-DESIGN.
3. Decide whether containment (A01-A03, A05) belongs in `Actuate` or stays a
   caller duty; if callers, add a containment test per caller path (reconcile,
   pack_frontmatter, projection) using `ArtifactIdentity.within_root?/2`.
4. Reconcile moduledoc caveats (`actuate.ex:56-86`) with A07 and A19.
5. Document literal-marker substring semantics (A11) in
   `docs/reference/cli/` alongside the `inject:` frontmatter fields.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `lib/ggen_igniter/actuate.ex`, `lib/ggen_igniter/injection.ex`
- `lib/ggen_igniter/artifact_identity.ex`
- `test/CLAUDE.md`
