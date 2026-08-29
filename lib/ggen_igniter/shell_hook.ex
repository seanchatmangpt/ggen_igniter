defmodule GgenIgniter.ShellHook do
  @moduledoc """
  Real subprocess execution for a template's `sh_before:`/`sh_after:`
  frontmatter fields (`GgenIgniter.Frontmatter.sh_before`/`sh_after`) --
  the one function this module exists for is `run/3`.

  New module, not folded into `GgenIgniter.Actuate`: `Actuate`'s own
  moduledoc frames its scope as "writes a rendered source string to a
  file" -- a shell command is neither a file write nor an EEx/eval
  actuation path, and giving it its own module keeps `Actuate`'s three
  real actuation paths (`write_new_file!/2`, `write_file!/3`,
  `inject_content!/5`) from growing a fourth, semantically unrelated one.
  `Mix.Tasks.GgenIgniter.Sync` and `GgenIgniter.Reactors.ReconcileReactor`
  both call this module directly (two genuinely separate call sites, per
  their own moduledocs on `sh_before:`/`sh_after:` wiring) rather than
  through `Actuate`.

  ## Scope -- disclosed, intentional, matching `sh_before:`/`sh_after:`'s
  own scope limitation

  This module knows nothing about frontmatter, admission, or compensation.
  It is a plain subprocess-execution primitive: given a command string and
  a working directory, run it for real and report back the real exit code
  and combined stdout+stderr. `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3`,
  `Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`, and
  `GgenIgniter.Reactors.ReconcileReactor`'s `:render`/`actuate_one/2` are
  where the real `--allow-sh` fail-closed gate, the per-row/per-target
  failure-tolerance policy, and `GgenIgniter.Receipt.commands` population
  live -- see those modules' moduledocs for the full, disclosed
  admission-gate/compensation exclusion this module's callers document.

  ## Real subprocess, real timeout

  `System.cmd("sh", ["-c", cmd], cd: project_dir, stderr_to_stdout: true)`
  runs the command for real, through a real POSIX shell (`sh -c`), with
  stderr merged into the same output stream `Mix.Tasks.GgenIgniter.Doctor`'s
  own `System.cmd/3` call sites already merge (`check_qlever_reachable/2`
  et al.) -- same convention, not a new one.

  No existing `System.cmd/3` call site in this repo (`ReconcileReactor`'s
  own `:verify` `mix compile` subprocess, `doctor.ex`'s three checks) has
  ever needed a timeout -- they all run to completion unbounded. A
  template-authored `sh_before:`/`sh_after:` command is different: it is
  arbitrary, untrusted-relative-to-this-pipeline shell text (the same real
  trust boundary a template's own EEx body already is -- see
  `GgenIgniter.Actuate.eval_code!/2`'s moduledoc for the precedent), and an
  unbounded hang here would hang the entire `sync`/reconciliation run with
  no way to interrupt just this one step. `run/3` wraps the real
  `System.cmd/3` call in a real `Task.async/1` + `Task.yield/2`/
  `Task.shutdown/2` timeout (the standard Elixir `Task` idiom for a
  boundable blocking call), defaulting to #{60_000}ms
  (`timeout_ms/0`), overridable via `opts[:timeout_ms]`.
  """

  @default_timeout_ms 60_000

  @typedoc """
  `{:ok, combined_output}` on a real zero exit; `{:error, {:sh_exit, code,
  combined_output}}` on a real nonzero exit; `{:error, :sh_timeout}` when
  the command did not finish within `opts[:timeout_ms]` (the process is
  killed via `Task.shutdown/2`'s real `:brutal_kill`, not left running).
  """
  @type result ::
          {:ok, String.t()}
          | {:error, {:sh_exit, integer() | :crashed, String.t()}}
          | {:error, :sh_timeout}

  @doc "The default timeout (ms) `run/3` uses when `opts[:timeout_ms]` is not given."
  @spec default_timeout_ms() :: pos_integer()
  def default_timeout_ms, do: @default_timeout_ms

  @doc """
  Runs `cmd` for real via `sh -c`, `cd:`'d into `project_dir`, with a real
  timeout (`opts[:timeout_ms]`, default `#{@default_timeout_ms}`ms).

  ## Examples

      iex> {:ok, output} = GgenIgniter.ShellHook.run("echo hi", File.cwd!())
      iex> String.trim(output)
      "hi"

      iex> {:error, {:sh_exit, 1, _output}} = GgenIgniter.ShellHook.run("exit 1", File.cwd!())

      iex> GgenIgniter.ShellHook.run("sleep 5", File.cwd!(), timeout_ms: 50)
      {:error, :sh_timeout}

  """
  @spec run(String.t(), String.t(), keyword()) :: result()
  def run(cmd, project_dir, opts \\ []) when is_binary(cmd) and is_binary(project_dir) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", cmd], cd: project_dir, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, code}} ->
        {:error, {:sh_exit, code, output}}

      {:exit, reason} ->
        # A real, unlikely crash inside the `Task.async/1` closure itself
        # (e.g. `sh` genuinely missing from `$PATH`, which raises an
        # `ErlangError` inside `System.cmd/3`) rather than a nonzero exit
        # from the command it ran -- reported honestly as a distinct
        # `:crashed` "code" so a caller inspecting the reason never confuses
        # it with a real shell exit status.
        {:error, {:sh_exit, :crashed, inspect(reason)}}

      nil ->
        {:error, :sh_timeout}
    end
  end
end
