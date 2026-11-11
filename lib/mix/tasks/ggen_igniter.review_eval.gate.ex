defmodule Mix.Tasks.GgenIgniter.ReviewEval.Gate do
  @moduledoc """
  Seal or adjudicate against the incident-eval baseline.

      mix ggen_igniter.review_eval.gate --seal --run-id run-...-abc1234
      mix ggen_igniter.review_eval.gate --run-receipt <path/to/receipt.json>

  Exits 0 on admit, 1 on refuse, 2 on invocation/config error (missing
  baseline, missing run receipt, digest mismatch, non-ancestor head).
  """
  use Mix.Task

  alias GgenIgniter.ReviewEval.Gate

  @shortdoc "Seal or gate the reviewer incident-eval baseline"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} =
      OptionParser.parse!(args,
        strict: [seal: :boolean, run_id: :string, run_receipt: :string, surface_tolerance: :integer]
      )

    cond do
      opts[:seal] && opts[:run_id] ->
        case Gate.seal(repo_root: ".", run_id: opts[:run_id]) do
          {:ok, baseline} ->
            Mix.shell().info("baseline sealed: #{Jason.encode!(baseline)}")
            exit_with(0)

          {:error, reason} ->
            Mix.shell().error("seal refused: #{inspect(reason)}")
            exit_with(2)
        end

      opts[:run_receipt] ->
        case File.exists?(opts[:run_receipt]) do
          false ->
            Mix.shell().error("run receipt not found: #{opts[:run_receipt]}")
            exit_with(2)

          true ->
            receipt = Jason.decode!(File.read!(opts[:run_receipt]))

            case Gate.admit(
                   repo_root: ".",
                   run_receipt: receipt,
                   surface_tolerance: Keyword.get(opts, :surface_tolerance, 1)
                 ) do
              {:ok, :admitted, details} ->
                Mix.shell().info("ADMITTED #{inspect(details)}")
                exit_with(0)

              {:refuse, reason, _} ->
                Mix.shell().error("REFUSED #{inspect(reason)}")
                exit_with(1)

              {:error, reason} ->
                Mix.shell().error("ERROR #{inspect(reason)}")
                exit_with(2)
            end
        end

      true ->
        Mix.shell().error("usage: --seal --run-id <id> | --run-receipt <path>")
        exit_with(2)
    end
  end

  defp exit_with(code), do: System.halt(code)
end
