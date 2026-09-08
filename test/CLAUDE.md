# `test/` — Chicago-style only

This overrides nothing in the root `CLAUDE.md`'s testing-discipline section —
it adds the concrete per-file conventions.

## Required shape for every test file

- `@moduledoc "Chicago-style: ..."` stating the real collaborators used (tmp
  dir, real subprocess, real oxigraph NIF, etc.) — see `actuate_test.exs` for
  the canonical one-liner. A test file with no such moduledoc is missing a
  required disclosure, not just missing polish.
- `use ExUnit.Case, async: true` unless the test genuinely can't be async
  (shared global state, a real subprocess binding a fixed port) — state why
  inline as a comment when `async: false` is used.
- `doctest GgenIgniter.<Module>` at the top when the module under test has
  runnable doctests in its `@doc`/`@moduledoc`.
- Real tmp-dir setup/teardown pattern: unique dir under `System.tmp_dir!()`
  suffixed with `System.unique_integer([:positive])`, `File.rm_rf!` both
  before creating and in `on_exit` — copy `actuate_test.exs`'s `setup` block
  verbatim as the template for any test needing real files on disk.
- `describe "function_name/arity (context)"` blocks group tests per function
  under test, arity included in the string.

## Naming and placement

- Flat `test/*.exs` files for unit/integration tests of one module
  (`ggen_igniter_<area>_test.exs` or `<module>_test.exs` — both patterns
  exist; match whichever an adjacent file for the same module already uses).
- `test/fixtures/` holds real `.ttl` ontologies, `.rq` queries, `.eex`
  templates, and fixture packs (`ash-lifecycle-pack/`, `broken-pack/`) used
  by multiple tests — add a fixture here rather than inlining a heredoc
  ontology/query/template string when more than one test would reuse it.
- `test/e2e/` is the real network-requiring, multi-minute lifecycle suite
  (`mix e2e`, not part of `mix test`) — new e2e stages go in
  `test/e2e/lifecycle_test.ex`; new e2e-only helpers go in
  `test/e2e/support/e2e_case.ex`. Don't add a slow/network-requiring test to
  a flat `test/*.exs` file — it belongs in `test/e2e/` or should be
  reconsidered.

## Non-negotiable: no test doubles for in-repo or locally-runnable collaborators

Real oxigraph NIF, real `sparql` hex engine, real file I/O, real subprocess
calls (`mix archive.install`, `mix igniter.new` in `test/e2e/`) are all used
directly — this repo has never needed the one-legitimate-exception carve-out
from `~/.claude/rules/testing-chicago-style.md` and a new test shouldn't be
the first to need it without a stated, reviewed reason.

### The check to run

This must exit 1 with no output before you call a test change done:

```bash
grep -rn --include='*.ex' --include='*.exs' --include='*.rs' --include='*.py' \
  --exclude-dir=_build --exclude-dir=deps \
  -E '(use|import) +(Mox|Mimic|Patch)\b|(Mox|Mimic|Patch)\.|:meck\.|mockall|MagicMock|Mock\(' \
  test lib native
```

**Do not use the older `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test`.**
It returns roughly 20 hits on a clean tree and not one of them is a
violation, so it cannot tell a real mock from either of the two things it
actually finds:

- `patch(` matches `Igniter.Test`'s `assert_has_patch/3`, which is a real
  state-based assertion on a real `%Igniter{}` diff — the exact opposite of
  a mock. See `ggen_igniter_ash_install_alignment_test.exs` for real uses.
- The moduledoc disclosure this file requires above quotes the banned tokens
  verbatim, so every well-formed test file is a hit against itself.

The replacement matches only `use`/`import`/module-qualified call positions,
which is why prose and `assert_has_patch` fall out, and it scans source
extensions only so a fixture's `_build/` or `deps/` tree cannot redden it.
It still catches `use Mox`, `Mox.expect`, `:meck.new`, `use Patch`, `import
Mimic`, `Mimic.copy`, `use mockall::`, `Mock()` and `MagicMock` — verified
against a probe tree containing all of them on 2026-09-08.
