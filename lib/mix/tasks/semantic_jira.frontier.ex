defmodule Mix.Tasks.SemanticJira.Frontier do
  @shortdoc "Print the Semantic Jira frontier projected from the standing ledger"

  @moduledoc """
  Projects standing from the ledger and prints the next frontier.

      mix semantic_jira.frontier --work-orders PATH --ledger PATH

  Prints one JSON object: `eligible`, `blocked`, `standings` (identity ->
  projected standing), `events`, `ledger_tail`. Exit `0` on success, `1` when
  the ledger or work orders are refused (a tampered ledger is refused, never
  silently projected), `2` for an invalid invocation.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [work_orders: :string, ledger: :string])

    {code, result} = GgenIgniter.SemanticJira.Cli.frontier(opts)
    Mix.shell().info(Jason.encode!(result))
    if code != 0, do: exit({:shutdown, code})
  end
end
