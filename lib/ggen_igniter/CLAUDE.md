# `lib/ggen_igniter/` — core library modules

## Moduledoc style (match this exactly, don't shorten)

Every module here carries a dense `@moduledoc` that:
- States what the module does in one sentence, then enumerates real distinct
  code paths/functions as a bulleted list (see `actuate.ex`'s three real
  actuation paths) — never a vague "handles X" paragraph.
- Cites the exact function/module names involved in cross-module behavior
  (e.g. "`Mix.Tasks.GgenIgniter.Sync`'s private `match_spec_to_marker!/2`"),
  not "the caller" or "elsewhere."
- Names disclosed, not-yet-implemented follow-on work explicitly in the
  moduledoc itself when relevant (e.g. Actuate's AST-patch note), rather than
  only in `docs/status.md` — a reader of the module alone should know the
  real scope boundary.
- References the real Rust `ggen` source file being ported/mirrored when one
  exists (e.g. "modeled on `ggen-engine/src/write.rs`'s decision table").

Every public function gets a `@spec` and a one-line `@doc` unless the
moduledoc's function list already fully explains it.

## Structural conventions

- One `defmodule GgenIgniter.<Name>` per file; file name is the snake_case of
  the last segment (`actuate.ex` -> `GgenIgniter.Actuate`).
- Subdirectories (`query/`, `render/`, `reactors/`, `telemetry/`) hold
  implementations of a behaviour/role defined by the sibling top-level file
  (`query.ex` defines the `GgenIgniter.Engine` behaviour; `query/oxigraph.ex`
  and `query/qlever.ex` implement it). When adding a new engine/renderer/
  reactor step, follow this same top-level-behaviour + subdirectory-impl
  split — don't flatten a new implementation into the top-level file.
- Two pipelines live in this tree side by side on purpose
  (`reconcile.ex` = bounded/direct path, `reactors/reconcile_reactor.ex` =
  opt-in coordinated path). Don't merge them or assume one calls the other —
  see the root `CLAUDE.md`'s "Two parallel pipelines" section before editing
  either.
- Real Rust interop goes through `native/` at the repo root (a sibling of
  `lib/`, not nested under here) — a stray `native/` directory under
  `lib/ggen_igniter/` in `ls` output is a build artifact symlink, not source;
  never hand-edit anything found there.

## Before adding a new module here

Check `docs/glossary.md` for whether the concept you're naming already has a
canonical term (e.g. "admission", "actuation", "compensation") — reuse it in
the moduledoc and function names rather than inventing a synonym.
