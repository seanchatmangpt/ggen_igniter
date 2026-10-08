# Upstream Igniter Issue Drafts

v26.9.28. DRAFT texts for `ash-project/igniter`. NOT posted; no network write was performed.
Igniter under test: 0.8.3 (`mix.lock`), sources at `deps/igniter/lib/`.

All reproductions were run in-process against `deps/igniter` with
`MIX_ENV=test MIX_BUILD_ROOT=_build-lane8 mix run <scratch>.exs`, using
`Igniter.Test.test_project/1`. Status per reproduction: EXECUTED = run, output observed;
UNVERIFIED = reasoned from source only.

| # | defect | repro status |
|---|---|---|
| 1 | `Rename.rename_function/4` skips guarded def heads | EXECUTED |
| 2 | `Rename.rename_function/4` crashes on parenless zero-arity def | EXECUTED |
| 3 | `Deps.get_dep/2` returns `nil`; `add_dep/2` raises `CaseClauseError` | EXECUTED |
| 4 | `Application.add_new_child/3` needs a `children =` binding | EXECUTED |
| 5a | `--help`-only interception, no `-h` | EXECUTED |
| 5b | unknown flag raises `OptionParser.ParseError` from `run/1` | EXECUTED |
| 5c | `add_issue/2` without `--check` does not halt / exit non-zero | PARTIAL: return value EXECUTED, process exit status UNVERIFIED |
| 5d | "No proposed content changes!" footer corrupts `--json` | EXECUTED (footer text); corruption of a real `--json` stream is proven by `test/ggen_igniter_cli_tasks_quirks_test.exs` |

---

## 1. `Igniter.Refactors.Rename.rename_function/4` silently skips guarded defs

**Status: EXECUTED**

### Reproduction

```elixir
g = """
defmodule M.G do
  def foo(x) when x > 0, do: x
  def caller(x), do: foo(x)
end
"""

igniter = Igniter.Test.test_project(files: %{"lib/g.ex" => g})

igniter
|> Igniter.Refactors.Rename.rename_function({M.G, :foo}, {M.G, :bar}, arity: 1)
|> Map.get(:rewrite)
|> Rewrite.source!("lib/g.ex")
|> Rewrite.Source.get(:content)
```

### Actual

```elixir
defmodule M.G do
  def foo(x) when x > 0, do: x      # NOT renamed
  def caller(x), do: bar(x)         # call site renamed -> broken program
end
```

### Expected

`def bar(x) when x > 0, do: x`. No warning is emitted either.

### Cause and fix sketch

A guarded head is `{:when, _, [{:foo, _, args}, guard]}`. The matchers at
`lib/igniter/refactors/rename.ex:168-169` (`remap_function_definition`, body migration) and
`rename.ex:325-326` (`update_refs`) match `{^old_function, _, args}` directly, so the guarded
head falls into `_other -> false`. Fix: unwrap the guard before matching, e.g. a helper

```elixir
defp def_head({:when, _, [head, _guard]}), do: head
defp def_head(head), do: head
```

applied to the head element in both sites, and rename the atom inside the unwrapped head.
Also decide the cross-module migration behaviour for guarded clauses (they must move together
with unguarded clauses of the same name/arity).

### In this repo

- Proof: `test/ggen_igniter_upstream_rename_blocker_test.exs` ("defect 1", tag
  `:known_upstream_bug`).
- Workaround: `lib/ggen_igniter/refactors/safe_rename.ex` `rename_remaining_guarded_defs/4`
  (post-pass); disclosed limitation: guarded def is not migrated across modules.
  Proof of wrapper: `test/ggen_igniter_safe_rename_test.exs`.

---

## 2. `rename_function/4` crashes with `length(nil)` on a parenless zero-arity def

**Status: EXECUTED**

### Reproduction

```elixir
z = """
defmodule M.Z do
  def foo do
    :ok
  end
end
"""

Igniter.Test.test_project(files: %{"lib/z.ex" => z})
|> Igniter.Refactors.Rename.rename_function({M.Z, :foo}, {M.Z, :bar}, arity: 0)
```

### Actual

`ArgumentError: errors were found at the given arguments: * 1st argument: not a list`
(`length(nil)`).

### Expected

`def bar do ... end`; `def foo do` and `def foo() do` are the same Elixir.

### Cause and fix sketch

A parenless zero-arity def has `args = nil` in its AST. `rename.ex:169`
(`length(args) in List.wrap(arity)`) and `rename.ex:326` (`length(args) == arity`) call
`length/1` on it. Fix: normalise once, `args = args || []` (or `List.wrap(args)`), in a shared
head-matching helper used by both sites (same helper as issue 1).

### In this repo

- Proof: `test/ggen_igniter_upstream_rename_blocker_test.exs` ("defect 2").
- Workaround: `lib/ggen_igniter/refactors/safe_rename.ex` `normalize_parenless_defs/3`
  (rewrites `def foo do` to `def foo() do` before delegating).

---

## 3. `Igniter.Project.Deps.get_dep/2` returns `nil`; `add_dep/2` raises `CaseClauseError`

**Status: EXECUTED**

### Reproduction

```elixir
mix = """
defmodule Sample.MixProject do
  use Mix.Project
  def project, do: [app: :sample, version: "0.1.0", deps: [{:jason, "~> 1.0"}]]
end
"""

igniter = Igniter.Test.test_project(files: %{"mix.exs" => mix})
Igniter.Project.Deps.get_dep(igniter, :jason)
#=> nil
Igniter.Project.Deps.add_dep(igniter, {:ash, "~> 3.0"})
#=> ** (CaseClauseError) no case clause matching: nil
```

### Actual

`get_dep/2` returns bare `nil`; `add_dep/2` raises `CaseClauseError`, crashing the whole task.

### Expected

Either support inline `deps: [...]` in `project/0`, or return a typed result: `get_dep/2`'s
own `@spec` is `{:ok, nil | String.t()} | {:error, String.t()}`, so `nil` violates it, and
`add_dependency/4` should surface `Igniter.add_issue`/`add_warning` (as it already does for
its `{:error, _}` clause) with remediation text.

### Cause and fix sketch

`lib/igniter/project/deps.ex:258-261` (`get_dep/2`):
`else _ -> nil` when `move_to_defp(zipper, :deps, 0)` is `:error`. The caller
`deps.ex:60` (`add_dependency/4`, reached from `add_dep/2` at `deps.ex:26-`) has clauses
only for `{:ok, nil}`, `{:error, _}`, `{:ok, current}`. Minimal fix: replace `_ -> nil` with
`_ -> {:error, "Could not find a `defp deps` ... refactor mix.exs or add the dependency manually"}`.
Better: also fall back to `move_to_function_call_in_current_scope`-style lookup of the
`deps:` key in `project/0`. The same `nil` also flows through `get_dependency_declaration/2`
(`deps.ex:188`, which tolerates it) and any other `case get_dep` caller.

### In this repo

- Proof: `test/ggen_igniter_igniter_idempotence_test.exs` ("inline deps: [...] in project/0
  is refused fail-closed").
- Workaround: `lib/mix/tasks/ggen_igniter.install.ex` `deps_probe/1` (pre-probe with the
  identical `move_to_module_using` + `move_to_defp(:deps, 0)` chain) and the
  `Igniter.add_issue/2` in `install_ash_domain/1` (`:error ->` branch). Documented in that
  file's moduledoc.

---

## 4. `Igniter.Project.Application.add_new_child/3` requires a `children =` binding

**Status: EXECUTED**

### Reproduction

```elixir
app = """
defmodule Sample.Application do
  use Application
  def start(_t, _a) do
    Supervisor.start_link([], strategy: :one_for_one, name: Sample.Sup)
  end
end
"""
# mix.exs with `use Mix.Project`, `deps: deps()`, `mod: {Sample.Application, []}`
igniter = Igniter.Test.test_project(files: %{"mix.exs" => mix, "lib/sample/application.ex" => app})
i = Igniter.Project.Application.add_new_child(igniter, Sample.Child)
i.warnings
#=> ["Could not find a `children = [...]` assignment in the `start` function of the
#=>   `Sample.Application` module. Please ensure that Sample.Child is added ... manually."]
Rewrite.source!(i.rewrite, "lib/sample/application.ex") |> Rewrite.Source.updated?()
#=> false
```

### Actual

Warning only; nothing inserted.

### Expected

The child is added. `Supervisor.start_link([...], opts)` with an inline literal list, and
`Supervisor.start_link(children, opts)` with a `children` binding built elsewhere, are both
ordinary OTP idioms.

### Cause and fix sketch

`lib/igniter/project/application.ex:292-345` (`do_add_child/4`) only recognises
`children = [..]` / `children = [..] ++ _` (lines 297-305, 316-330). Fix sketch: add a third
`with` branch that finds `Supervisor.start_link(<list literal>, _)` via
`Igniter.Code.Function.move_to_function_call/3` (`{Supervisor, :start_link}`, arities `[2, 3]`)
and calls `add_child_to_list/4` on argument 0.

### In this repo

- Proof: `test/ggen_igniter_igniter_idempotence_test.exs` ("inline Supervisor.start_link([])
  is rewritten once, then stable").
- Workaround: `lib/mix/tasks/ggen_igniter.install.ex` `ensure_children_binding/1` /
  `rewrite_children_binding/1` (hoists the literal list into `children =` first).

---

## 5. `Igniter.Mix.Task` runner: `--help` handling, validation errors, `add_issue`, footer

### 5a. Only the literal `--help` is intercepted; `-h` is not, and `--help` prints the raw moduledoc

**Status: EXECUTED**

```elixir
Igniter.Mix.Task.help_requested?(["--help"]) #=> true
Igniter.Mix.Task.help_requested?(["-h"])     #=> false
```

Actual: `lib/mix/task.ex:333` is `def help_requested?(argv), do: "--help" in argv`, called at
`task.ex:80` before `igniter/1`; a match runs `Mix.Task.run("help", [task])` (raw `@moduledoc`
dump). A task that declares `aliases: [h: :help]` in `info/2` still gets `-h` handled
differently from `--help`. Expected: honour the aliases in `info/2` (`-h` and `--help` behave
alike) and let a task override the help renderer without overriding `run/1`.
Suggested fix: `help_requested?/1` -> also match `"-h"`, or resolve through the task's alias
map; or expose a `help/1` callback that `run/1` calls.

- Proof: `test/ggen_igniter_cli_tasks_quirks_test.exs` ("--help vs -h parity").
- Workaround: `lib/ggen_igniter/task_shell.ex` `run_with_help/4`, used by each task's `run/1`.

### 5b. Unknown flag: `run/1` raises `OptionParser.ParseError` (exit 1), not a usage error

**Status: EXECUTED**

```elixir
Igniter.Util.Info.validate!(["--bogus"], %Igniter.Mix.Task.Info{schema: [a: :boolean]}, "x.y")
#=> ** (OptionParser.ParseError) 1 error found!  --bogus : Unknown option ...
```

`task.ex:88-96` calls `Igniter.Util.Info.validate!/3` (`lib/igniter/util/info.ex:345-369`,
`OptionParser.parse!`) unguarded, so Mix reports "Could not invoke task" with exit code 1,
indistinguishable from a diagnostic failure. (The comment at
`lib/mix/tasks/ggen_igniter.doctor.ex:200-215` names `Mix.Error`; the raised struct is
`OptionParser.ParseError`, verified here.) Expected: `validate!/3` rescues to a stable,
documented usage exit code (POSIX convention 2) or exposes a non-raising `validate/3`.

- Workaround: pre-validation in `lib/mix/tasks/ggen_igniter.doctor.ex` before `super/1`.

### 5c. `Igniter.add_issue/2` does not halt or set a non-zero exit without `--check`

**Status: PARTIAL. Return value EXECUTED; process exit status UNVERIFIED (not run as a
subprocess).**

```elixir
i = Igniter.new() |> Igniter.add_issue("boom")
Igniter.do_or_dry_run(i, [])   # prints "Issues: * boom"
#=> :issues       (no System.halt, no raise)
```

`lib/igniter.ex:1153-1279`: with `issues != []` the `igniter ->` fallback clause
(around `igniter.ex:1276`) prints and returns `:issues`; only `halt_if_fails_check!/3`
(`igniter.ex:1293-`, halts 2/3) exits non-zero, and only when `--check` is set. The generated
`run/1` (`task.ex:88-104`) discards the return value, so the task returns normally
(expected exit 0, UNVERIFIED as a subprocess). A CI script therefore sees success although
the installer refused. Expected: `run/1` exits non-zero (or raises `Mix.Error`) when
`do_or_dry_run/2` returns `:issues`, regardless of `--check`.

- Proof: `test/ggen_igniter_igniter_idempotence_test.exs` (`assert_refused`) asserts the issue
  is recorded and nothing is written; it does not assert an exit code.
- Workaround: tasks that need a real exit code call `System.halt/1` directly, e.g.
  `lib/mix/tasks/ggen_igniter.doctor.ex` (`System.halt(1)` on failures).

### 5d. "No proposed content changes!" footer corrupts `--json`

**Status: EXECUTED (footer emitted); stream corruption proven in repo test.**

```elixir
ExUnit.CaptureIO.capture_io(fn -> Igniter.do_or_dry_run(Igniter.new(), []) end)
#=> "\nIgniter:\n\n    No proposed content changes!\n\n"
```

`igniter.ex:1181-1184` prints it via `Mix.shell().info` to stdout unless `:quiet_on_no_changes?`
(opt or `igniter.assigns[:quiet_on_no_changes?]`) or `:yes` is set. A task that already wrote a
JSON document to stdout ends up with trailing non-JSON bytes. Expected: an option that
suppresses all runner chatter (or the runner should write status to stderr), and
`--json`-style machine output should be a first-class case. Note `quiet_on_no_changes?`
exists but is undocumented in the task-author path; documenting it plus defaulting it to
stderr routing would resolve this.

- Proof: `test/ggen_igniter_cli_tasks_quirks_test.exs` (`@json_capable_tasks`).
- Workaround: `System.halt(0)` in the `--json` branch of
  `lib/mix/tasks/ggen_igniter.doctor.ex` (and `ggen_igniter.plan`).

---

## See Also

- `lib/mix/tasks/CLAUDE.md` "Known `Igniter.Mix.Task` base-class quirks"
- `docs/jira/v26.9.28/_LANES.md`
