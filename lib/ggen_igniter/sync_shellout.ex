defmodule GgenIgniter.SyncShellout do
  @moduledoc """
  GGEN-1805 (`docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md`): a real
  `System.cmd/3` shellout to an external `ggen sync run` binary, modeled on
  the three existing subprocess-check patterns in
  `lib/mix/tasks/ggen_igniter.doctor.ex` (`check_git_status/0`,
  `check_nif_compiles/0`, `check_hex_publish_readiness/0`) -- an explicit
  `cd:` argument (never implicit `File.cwd!()`, per `check_nif_compiles/0`'s
  `ggen_igniter_root/0` precedent), `stderr_to_stdout: true`, a typed
  `{:ok, output} | {:error, {exit_code, output}}` return (never a bare raise
  or boolean), and a `rescue` clause converting a raised `ErlangError`
  (binary not on `PATH`, the same failure mode `check_git_status/0` already
  handles for `git`) into the same error shape with a distinguishable
  `:enoent` sentinel exit code, rather than crashing the caller.

  ## Chained-failure gating

  `run/2`'s `upstream_ok?` argument is a hard precondition, per the ticket:
  this function must not shell out at all if the preceding `ggen.toml`
  serialize-back step (GGEN-1804, upstream in the bundle-installer pipeline
  and out of scope here) failed. Passing `upstream_ok?: false` returns
  `{:error, :upstream_failed}` before `System.cmd/3` is ever invoked -- proven
  in the test suite via a real, observable absence signal (no generated
  output file appears), not a mocked call-count assertion.
  """

  @doc """
  Shells out to `ggen sync run` with `cd: project_dir` (the consumer
  project's root, passed in explicitly by the caller). `opts`:

    * `upstream_ok?` -- defaults to `true`. When `false`, refuses without
      invoking the subprocess at all, returning `{:error, :upstream_failed}`.

  Returns:

    * `{:ok, output}` on a real exit code `0`.
    * `{:error, {exit_code, output}}` on a real nonzero exit code.
    * `{:error, {:enoent, message}}` when the `ggen` binary itself is not on
      `PATH` (an `ErlangError` raised by `System.cmd/3`, converted rather than
      left to crash the caller).
    * `{:error, :upstream_failed}` when `upstream_ok?: false` was passed.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, String.t()}
          | {:error, {integer() | :enoent, String.t()}}
          | {:error, :upstream_failed}
  def run(project_dir, opts \\ []) when is_binary(project_dir) and is_list(opts) do
    if Keyword.get(opts, :upstream_ok?, true) do
      do_run(project_dir)
    else
      {:error, :upstream_failed}
    end
  end

  defp do_run(project_dir) do
    case System.cmd("ggen", ["sync", "run"], cd: project_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {code, output}}
    end
  rescue
    error in ErlangError ->
      {:error, {:enoent, "ggen not found on PATH: #{Exception.message(error)}"}}
  end
end
