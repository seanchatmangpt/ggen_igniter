# AST Mutation & Code Injection

## Overview

In code generation systems, modifying existing source files can follow one of two paradigms:
1. **Structural AST Rewriting**: Parsing the file into an Abstract Syntax Tree (AST), navigating via zippers (`Sourceror.Zipper`), inserting or transforming nodes, and formatting the output back to source.
2. **Anchor-Based Text Splice**: Locating a unique text marker or line index in the source file and splicing new lines directly before or after that anchor.

This document details the observed implementation in `ggen_igniter` (`GgenIgniter.Actuate.inject_content!/5`), its fail-closed safety gates, and how it compares to full AST rewriting with `Sourceror`/`Igniter`.

---

## 1. Observed Implementation: `Actuate.inject_content!/5`

`GgenIgniter.Actuate.inject_content!/5` (`lib/ggen_igniter/actuate.ex:115-220`) implements line-oriented code injection into existing files. It mirrors Rust `ggen`'s `inject_into` semantics (`ggen-engine/src/write.rs`):

```elixir
Actuate.inject_content!(path, marker, content, insert_mode, opts \\ [])
```

### Injection Modes (`insert_mode`)
- `:before`: Inserts `content` as new line(s) immediately before the matched marker line.
- `:after`: Inserts `content` as new line(s) immediately after the matched marker line.
- `:at_line`: Inserts `content` at an explicit 1-based line number (`opts[:line]`). `marker` is ignored.

---

## 2. Anchor Specification (`MatchSpec` & `MatchRule`)

Template frontmatter specifies injection targets using `inject: true` paired with `before:`, `after:`, or `at_line:`.

`GgenIgniter.Frontmatter` parses these into `GgenIgniter.Frontmatter.MatchSpec`:
- **Literal Matcher**: `{:literal, "pattern"}` -> Direct substring / line match.
- **Structured Matcher**: `{:structured, %MatchRule{}}` -> Configurable matching rule.

### `MatchRule` Fields & Support Matrix

| Field | Values | Behavior & Support in `ggen_igniter` |
|---|---|---|
| `pattern` | `String.t()` | Required search pattern. |
| `matcher` | `:contains` \| `:exact` \| `:regex` | `:contains` (substring/string match), `:exact` (`^...$` anchored), `:regex` (compiled Elixir `Regex`). |
| `case_sensitive` | `boolean()` | Default `true`. If `false`, adds `i` flag to compiled regex. |
| `trim` | `boolean()` | Only supported when `matcher: :exact` (matches `^\s*pattern\s*$`). |
| `scope` | `:auto` \| `:line` \| `:file` | `:line` and `:auto` supported. **`:file` raises `ArgumentError`** (multi-line full-file matching is not supported by the line engine). |
| `occurrence` | `:first` \| `:last` \| `:unique` \| `:nth` | Only `:first` (the default) is supported. **Other occurrences raise `ArgumentError`** because `unique_marker_line!/3` strictly requires exactly one match. |

```elixir
# lib/mix/tasks/ggen_igniter.sync.ex:983-1018
defp match_spec_to_marker!({:literal, s}, _label), do: s
defp match_spec_to_marker!({:structured, %MatchRule{} = rule}, label) do
  if rule.scope == :file, do: unsupported_match_rule!(label, "scope: :file", ...)
  if rule.occurrence != :first, do: unsupported_match_rule!(label, "occurrence: ...", ...)
  if rule.trim and rule.matcher != :exact, do: unsupported_match_rule!(label, "trim: true ...", ...)
  build_regex_marker(rule)
end
```

---

## 3. Fail-Closed Safety Gates

`inject_content!/5` executes three mandatory fail-closed validation gates before mutating the file (mirroring `FM-WRITE-003` and `FM-WRITE-004` from Rust `ggen`):

1. **Target File Must Exist (`FM-WRITE-003`)**:
   - Injection is designed for existing codebases. It is never a substitute for file creation.
   - If `File.exists?(path)` is `false`, raises `ArgumentError`.
2. **Anchor Uniqueness Gate (`FM-WRITE-004`)**:
   - The marker must match **exactly one line** in the target file.
   - Zero matches -> Raises `ArgumentError` (missing anchor slot).
   - Multiple matches -> Raises `ArgumentError` (ambiguous anchor; generator will never guess).
3. **Line Range Validation**:
   - For `:at_line` mode, the line number must be within `1..(line_count + 1)`. Out-of-bounds line numbers raise `ArgumentError`.

---

## 4. Idempotency Guarantees

Repeatedly running `mix ggen_igniter.sync` must not duplicate injected code blocks. `Actuate.inject_content!/5` performs a pre-insertion idempotency check:

```elixir
# lib/ggen_igniter/actuate.ex:347-357
# For :before mode: checks if body_lines already exist immediately preceding the marker line
defp already_present_at?(lines, body_lines, insert_at, :before) do
  lines
  |> Enum.slice(insert_at - length(body_lines), length(body_lines))
  |> Kernel.==(body_lines)
end

# For :after and :at_line: checks if body_lines already exist at insert_at
defp already_present_at?(lines, body_lines, insert_at, _mode) do
  lines
  |> Enum.slice(insert_at, length(body_lines))
  |> Kernel.==(body_lines)
end
```

If the lines are already present at the target position, the injection is skipped as a no-op, returning `{:ok, :unchanged}`.

---

## 5. Structural AST Mutation: Planned Capability

### Comparison

| Dimension | Line-Anchored Splice (`inject_content!/5`) | Structural AST Rewriting (`Sourceror`/`Igniter`) |
|---|---|---|
| **Representation** | Raw lines of text (`String.split/2`) | Parsed Elixir AST (`Sourceror.Zipper`) |
| **Formatting Resilience** | Fails if anchor comments or whitespace change | Resilient to comments, formatting, and AST layout |
| **Target Precision** | Line-based marker or index | Structural node (e.g., inside `defmodule`, inside pipeline) |
| **Implementation Status** | **LIVE & TESTED** | **PLANNED / FUTURE WORK** |

As stated in `lib/ggen_igniter/actuate.ex:24-28`:
> Igniter AST-patch actuation (a real `Sourceror`/`Igniter.Code`-based structural patch, as opposed to this module's line-anchored text splice) for incremental changes to an EXISTING file remains an explicit, disclosed follow-on -- not implemented this pass.
