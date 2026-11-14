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
        strict: [
          seal: :boolean,
          run_id: :string,
          run_receipt: :string,
          surface_tolerance: :integer
        ]
      )

    dispatch(opts)
  end

  defp dispatch(opts) do
    cond do
      opts[:seal] && opts[:run_id] -> seal(opts[:run_id])
      opts[:run_receipt] -> gate(opts)
      true -> usage()
    end
  end

  defp usage do
    Mix.shell().error("usage: --seal --run-id <id> | --run-receipt <path>")
    exit_with(2)
  end

  defp seal(run_id) do
    case Gate.seal(repo_root: ".", run_id: run_id) do
      {:ok, baseline} ->
        Mix.shell().info("baseline sealed: #{Jason.encode!(baseline)}")
        exit_with(0)

      {:error, reason} ->
        Mix.shell().error("seal refused: #{inspect(reason)}")
        exit_with(2)
    end
  end

  defp gate(opts) do
    path = opts[:run_receipt]

    if File.exists?(path) do
      receipt = Jason.decode!(File.read!(path))

      result =
        Gate.admit(
          repo_root: ".",
          run_receipt: receipt,
          surface_tolerance: Keyword.get(opts, :surface_tolerance, 1)
        )

      report_admit(result)
    else
      Mix.shell().error("run receipt not found: #{path}")
      exit_with(2)
    end
  end

  defp report_admit({:ok, :admitted, details}) do
    Mix.shell().info("ADMITTED #{inspect(details)}")
    exit_with(0)
  end

  defp report_admit({:refuse, reason, _}) do
    Mix.shell().error("REFUSED #{inspect(reason)}")
    exit_with(1)
  end

  defp report_admit({:error, reason}) do
    Mix.shell().error("ERROR #{inspect(reason)}")
    exit_with(2)
  end

  defp exit_with(code), do: System.halt(code)
end
