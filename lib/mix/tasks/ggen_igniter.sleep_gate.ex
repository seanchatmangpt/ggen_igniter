defmodule Mix.Tasks.GgenIgniter.SleepGate do
  @shortdoc "Fail-closed no-sleep gate over lib/ and test/"

  @moduledoc """
  Runs `GgenIgniter.SleepGate.scan/1` against the current directory, prints one
  `file:line kind` row per violation, and exits 1 when any exist (0 when clean).

      mix ggen_igniter.sleep_gate
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    case GgenIgniter.SleepGate.scan(File.cwd!()) do
      [] ->
        Mix.shell().info("sleep-gate: clean")

      violations ->
        Enum.each(violations, fn v ->
          Mix.shell().error("#{v.file}:#{v.line} #{v.kind}")
        end)

        System.halt(1)
    end
  end
end
