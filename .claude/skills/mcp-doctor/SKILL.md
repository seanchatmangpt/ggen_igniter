---
name: mcp-doctor
description: Health-check every MCP server and plugin configured in ~/.claude/settings.json — checks whether each mcpServers binary actually exists and runs, and whether each enabled plugin's cache is populated and matches its marketplace source. Use when asked to check MCP server health, diagnose a plugin that isn't working, or audit settings.json's mcpServers/enabledPlugins for drift.
---

# mcp-doctor

Generalizes the discover→verify→classify pattern already used for the bundled
Lumen backend (`lumen:doctor`) to every MCP server and plugin configured globally.
Extracted 2026-08-21 after the same check had been run ad hoc by hand at least
twice (`~/.claude/audit-loop/06-settings-audit.md`, `08-plugin-version-drift.md`,
`09-mcp-server-map.md`; `~/.claude/errc-loop/errc-tracker.md` cycles 3-4).

## Steps

### 1. Check every `mcpServers` entry

For each entry in `~/.claude/settings.json`'s `mcpServers` object:

```bash
python3 -c "import json; d=json.load(open('/Users/sac/.claude/settings.json')); [print(k, v.get('command','')) for k,v in d.get('mcpServers',{}).items()]"
```

For each `(name, command)` pair:
- If `command` is an absolute path: `test -e "$command"` — if missing, that server
  is **BROKEN (binary missing)**.
- If it exists, try invoking it briefly (e.g. with a short timeout) to confirm it
  doesn't crash immediately — MCP servers typically block on stdio waiting for a
  handshake, so "hangs without crashing" within a couple seconds is the expected
  healthy signal, not a failure.
- If broken, find the binary's source repo (usually a sibling directory matching
  the command path's project name) and run `cargo metadata --no-deps --format-version 1`
  (Rust) or equivalent to check whether the intended binary target actually exists
  anywhere in that workspace:
  - Target exists but unbuilt → **FIXABLE (run the build)**
  - Target doesn't exist anywhere in the workspace → **NEVER IMPLEMENTED** (don't
    guess whether it was meant to exist — report this distinction clearly, since
    "unbuilt" and "never written" call for different fixes)
  - Path points at a real repo but the wrong binary/subpath → **PATH DRIFT**, find
    the correct current location if possible

### 2. Check every enabled plugin's cache

```bash
python3 -c "import json; d=json.load(open('/Users/sac/.claude/settings.json')); [print(k) for k,v in d.get('enabledPlugins',{}).items() if v]"
```

For each enabled plugin sourced from `claude-plugins-official` (or another
marketplace with a local cache), diff the installed cache against the marketplace
source:

```bash
# find the cache dir (versioned subdir) and the marketplace dir for a given plugin name
diff -rq ~/.claude/plugins/cache/claude-plugins-official/<plugin>/<version-or-unknown-dir> \
         ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/<plugin> \
  2>/dev/null | grep -v ".in_use\|__pycache__\|LICENSE\|README"
```

- No diff → **CURRENT**
- Cache missing files present in marketplace source (commands, skills, plugin.json)
  → **STALE** (needs a cache refresh — copy the missing marketplace content into the
  cache dir, or trigger whatever the real plugin-update mechanism is)
- Plugin sourced from a local-directory marketplace (`extraKnownMarketplaces`,
  `source: "directory"`) or with no `claude-plugins-official` cache path → **NOT
  DIFFABLE this way**, note it separately rather than silently skipping

### 3. Report

One table: name | kind (mcpServer/plugin) | status | one-line detail | proposed fix
(if any). Classify each finding using the same status vocabulary as the rest of
this config tree's rules (`~/.claude/rules/no-overclaiming-rust.md`): don't call
something FIXED unless you've actually run the fix and re-verified; a found-but-
unfixed issue is reported as found, not silently left implicit.

## Do NOT

- Don't silently "fix" a broken MCP server binary by running its build yourself
  without saying so — building changes local state (compiled artifacts) even
  though it doesn't touch source; report what you'd do and let the calling context
  decide, unless already instructed to execute fixes (e.g. within the ERRC loop's
  own auto-execute-if-safe discipline).
- Don't guess at "never implemented" vs. "unbuilt" — always check via the actual
  build tool's metadata command, not by assuming from the binary's absence alone
  (this exact distinction mattered for `bcinr-mcp`, see
  `~/.claude/errc-loop/pending-decisions.md`).

## See Also
- `~/.claude/errc-loop/errc-tracker.md` — cycles 3-4 did this by hand; this skill
  generalizes that
- `~/.claude/errc-loop/pending-decisions.md` — items this skill would re-surface
  (bcinr-mcp, anti-llm-cheat-lsp/wasm4pm-lsp) until the user resolves them
