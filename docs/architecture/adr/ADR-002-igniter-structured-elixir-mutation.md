# ADR-002: Igniter & Structured Elixir Mutation Boundaries

## Status
Accepted (`PARTIAL_ALIVE` / `PLANNED`)

## Context
Modifying Elixir source projects requires safe mechanisms for file creation, text injection, and AST structural updates.

## Decision
1. Implement file creation and line/regex text splicing via `GgenIgniter.Actuate` (`write_file!/3`, `inject_content!/5`).
2. Integrate with `Igniter.Mix.Task` for CLI task plumbing.
3. Defer deep AST zipper manipulation (`Igniter.Code` / `Sourceror`) to a planned follow-on pass.

## Rationale
Whole-file generation and anchored text injection cover 95%+ of code generation requirements without taking on the complexity of full AST parsing on every invocation.

## Consequences
- **Positive:** Fast, deterministic file generation with idempotent checks.
- **Trade-off:** Fine-grained AST patch transformations inside existing modules are currently performed via marker anchors rather than syntax-tree zippers.
