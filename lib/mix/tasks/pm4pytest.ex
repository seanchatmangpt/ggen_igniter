defmodule Mix.Tasks.Pm4pytest do
  @shortdoc "Runs the pm4pytest CLI with passthrough args (PATH or PM4PYTEST_BIN)"

  @moduledoc """
  Thin wrapper around the standalone `pm4pytest` binary
  (packages/pm4pytest in ggen-marketplace: IEEE OCEL v2 conformance,
  OCPQ, temporal SLA; TAP v13 / JUnit XML / JSON out).

  Binary resolution order:

    1. `PM4PYTEST_BIN` env var (must exist on disk if set)
    2. `pm4pytest` on PATH (`System.find_executable/1`)

  If neither resolves to an existing executable, the task refuses with
  `REFUSED:PM4PYTEST_BINARY_NOT_FOUND` and exit code 2 (matching the
  pm4pytest CLI's own "configuration error" code). Otherwise it execs the
  binary with all passthrough args via a real subprocess, streaming stdout
  to this process's stdout, and exits with the binary's exit code.

  ## Example

      mix pm4pytest check-conformance --log log.sqlite --fsm a,b,c

  Python CLI flags (see `packages/pm4pytest/src/pm4pytest/cli.py`):
  `check-conformance --log/-l --fsm/-f --min-fitness/-m --format --junitxml`.
  """

  use Mix.Task

  @env_var "PM4PYTEST_BIN"
  @refusal "REFUSED:PM4PYTEST_BINARY_NOT_FOUND"

  @impl Mix.Task
  def run(args) do
    case locate() do
      {:ok, path} ->
        exec(path, args)

      :not_found ->
        Mix.shell().error(
          "#{@refusal}: set #{@env_var} to the pm4pytest executable or put `pm4pytest` on PATH " <>
            "(pip install packages/pm4pytest from ggen-marketplace)"
        )

        exit({:shutdown, 2})
    end
  end

  defp locate do
    case System.get_env(@env_var) do
      nil ->
        if path = System.find_executable("pm4pytest"), do: {:ok, path}, else: :not_found

      "" ->
        :not_found

      path ->
        if File.exists?(path), do: {:ok, path}, else: :not_found
    end
  end

  defp exec(path, args) do
    {_, code} =
      System.cmd(path, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    exit({:shutdown, code})
  end
end
