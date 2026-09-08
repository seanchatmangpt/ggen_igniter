# Tool Usage Rules — Claude Code

Core principles for using tools effectively in code-heavy sessions.

## LSP-First Navigation (Rust, TypeScript, Python; Java currently inactive)

### Rust (praxis-graphlaw, O*, other Rust projects)

**Prefer LSP over grep/text search for:**
- Finding function definitions: use `goToDefinition` (LSP) not `grep "fn foo("`
- Finding call sites: use `findReferences` (LSP) not `grep "foo("`
- Finding type definitions: use `goToDefinition` (LSP) for struct/enum names
- Understanding hover info: use `hover` (LSP) for doc comments and inferred types
- Searching symbols across workspace: use `workspaceSymbol` (LSP) not `grep -r`

**When grep is appropriate:**
- Finding anti-patterns: `grep -rn "\.unwrap()" crates/praxis-graphlaw/src/` (find all unwraps to audit)
- Finding debug code: `grep -rn "println!\|eprintln!\|TODO\|FIXME\|XXX" crates/`
- Finding string literals in error messages (LSP symbols don't index strings)

**LSP commands (via LSP tool):**
```
LSP goToDefinition crates/praxis-graphlaw/src/hooks.rs 100 10  # Jump to definition at line 100, char 10
LSP findReferences crates/praxis-graphlaw/src/lib.rs 50 5      # Find all references to symbol at line 50, char 5
LSP hover crates/praxis-graphlaw/src/rule.rs 80 1              # Get type info and docs at line 80, char 1
LSP workspaceSymbol "CompiledRule"                             # Find all CompiledRule definitions/references
```

### Java — jdtls-lsp currently DISABLED on this machine

`jdtls-lsp@claude-plugins-official` is disabled in `~/.claude/settings.json`, so the
guidance below has no LSP server backing it right now — grep/text search is the actual
fallback for Java until this plugin is re-enabled:

- Use `goToDefinition` for method/class navigation
- Use `findReferences` to find method call sites
- Use `workspaceSymbol` to search across modules
- Avoid text search for types; prefer LSP

### TypeScript/JavaScript

- Use `goToDefinition` for imports and type references
- Use `findReferences` for function/component usage
- Use `hover` to see inferred types

### Python — pyright-lsp enabled

`pyright-lsp@claude-plugins-official` is enabled. Note: `~/CLAUDE.md` already directs
Python (and all languages) code *discovery* to `mcp__lumen__semantic_search` first —
that preference stands for locating code/definitions/usages across a project. Once a
specific symbol is found, prefer LSP over further grep for precision navigation:

- Use `goToDefinition` for imports, function/class definitions
- Use `findReferences` for call-site and usage discovery
- Use `hover` for inferred types and docstrings
- Use `workspaceSymbol` to search symbols across modules
- `grep` remains appropriate for string literals, config values, and anti-pattern
  sweeps (e.g. banned mock imports per `testing-chicago-style.md`) that LSP symbol
  search won't index

---

## Git Commit Messages: Always Use `-F <file>`, Never Inline `-m` for Multi-Line Text

Never pass a multi-line or code-quoting-heavy commit message as an inline `-m
'...'` string. The shell tokenizes and interprets that string before `git` ever
sees it, and multi-line prose with backticks, parentheses, or other shell
metacharacters is a real, recurring source of silent corruption or outright
parse failure — not a hypothetical:

- **Backticks inside a double-quoted `-m` string trigger command substitution.**
  A message containing `` `wpm plan` `` (to typeset a command name) silently ran
  `wpm plan` as a shell command, which failed with "command not found: wpm", and
  the backtick-quoted text was swallowed from the resulting commit message
  entirely — the commit's code content was unaffected, only the message text was
  silently wrong until caught by reading the actual landed message back.
- **A separate incident**, this time in a single-quoted `-m` string containing a
  Python-style function call like `_verify_replanning():`, produced a zsh parse
  error ("defining function based on alias `-'") that aborted the commit before
  it ran at all — a loud failure this time, not a silent one, but still lost
  time diagnosing a shell-tokenization problem that has nothing to do with git.

**The fix, every time:** write the message to a file with `Write`, then
`git commit -F <path>`. This sidesteps shell interpretation of the message
content entirely — no backtick, parenthesis, quote, or other metacharacter in
the message text can affect how the shell parses the command, because the
message never touches the command line. Verify the landed message afterward
with `git log -1 --format="%B"` before assuming it's correct, the same
verify-don't-assume discipline as everything else in this file.

---

## Markdown Document Standards (for praxis-graphlaw and other core projects)

### Structure Requirements

Every significant `.md` file must have:

1. **Title (H1)** at the top, matching the filename semantically
2. **Quick Reference or Table of Contents** if > 100 lines
3. **Sections (H2)** for major topics, never more than 40 lines between headers
4. **Inline code blocks** for examples (bounded by \`\`\`)
5. **Links to related docs** at the end in a "References" or "See Also" section

### Content Standards

#### What to Include

- **Executive summary (first paragraph)**: What is this document about? Who is it for?
- **Links to related docs**: Every doc should cite 2-5 related docs it depends on or complements
- **Examples for every significant rule or concept**: Bad rule: "Use deterministic ordering". Good rule: "Use deterministic ordering (e.g., sort by (s_id, p_id, o_id) before hashing)"
- **Complexity or performance notes**: If documenting an algorithm, include O() bounds
- **Version/milestone marker**: "v26.7.8" at the top; obsolete docs marked "DEPRECATED: See X instead"

#### What NOT to Include

- Redundant table-of-contents (markdown renderers auto-generate these)
- Text that repeats the heading (heading is the topic; body explains it)
- Broken links (prefer an inline phrase "See the Standing Policy in docs/standing/" over "[Standing Policy](broken/link)")
- Subjective adjectives without grounding ("clean code", "best practices", "elegant solution") — use measurable criteria instead
- Outdated information; prefer deletion + link to current version

### Cross-Document Consistency

- **Terminology**: If a term has a specific meaning (e.g., "Refusal", "Standing", "Invariant"), use it consistently and define it on first use
- **Linking**: Link to the most authoritative version (e.g., code comments > tickets > docs; if a concept is already in the code, link to it rather than duplicating)
- **Filenames**: Use kebab-case (CORE_TEAM_DISCIPLINE.md, not core-team-discipline.md or coreteamdiscipline.md)
- **Directory**: Core project docs go in `docs/` at the root; milestone-specific docs go in `docs/jira/v26.7.8/`; standing/infrastructure docs go in `docs/standing/`

### Markdown-Specific Rules

1. **Line length**: No line longer than 100 characters (wrap at sentence boundaries)
2. **Code blocks**: Always specify language (` ```rust `, ` ```markdown `, etc.)
3. **Lists**: Use ordered lists (1. 2. 3.) for sequences and priorities; unordered (- or *) for sets
4. **Tables**: Use only for tabular data (matrix of properties); not for prose
5. **Links**: Prefer relative paths (`docs/CORE_TEAM_DISCIPLINE.md`) over absolute (`/Users/sac/praxis/docs/...`)
6. **Emphasis**: Use `**bold**` for strong emphasis, `*italic*` for mild emphasis, `` `code` `` for inline code. Never use ALL_CAPS for emphasis.
7. **Headings**: H1 only once per file (the title); use H2 for major sections, H3 for subsections. No H4 or deeper.

### Document Age and Maintenance

- Add a "Last Updated" timestamp or version tag if the document has temporal content (e.g., "Updated 2026-07-08")
- If a doc is superseded by a newer doc, add a deprecation notice at the top: "⚠️ DEPRECATED: This document is superseded by [New Docs](). See that link for current information."
- Dead docs (unused, obsolete) should be moved to `docs/archive/` with a note on why they were superseded

### Review Checklist for Documentation PRs

Before submitting a PR that touches `.md` files:

- [ ] Title (H1) is present and matches the filename
- [ ] No broken links (check relative paths exist)
- [ ] Examples are runnable or clearly illustrative (no pseudocode without context)
- [ ] Every code block specifies a language
- [ ] No lines > 100 characters
- [ ] Cross-references to related docs are present
- [ ] If this doc supersedes an older doc, old doc is marked deprecated
- [ ] Terminology is used consistently with other docs in the project
- [ ] If this doc describes a rule/invariant, cite its source (code, ticket, or RFC)

---

## References

- `/Users/sac/praxis/docs/CORE_TEAM_DISCIPLINE.md` — Full engineering standards, including documentation requirements
- LSP (Language Server Protocol) documentation: https://microsoft.github.io/language-server-protocol/
- Markdown guide: https://www.markdownguide.org/
