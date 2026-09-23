defmodule Mix.Tasks.SemanticJira.Reconcile do
  @shortdoc "Reconcile one receipt into the Semantic Jira standing ledger"

  @moduledoc """
  Turns a verified receipt into an append-only standing transition.

      mix semantic_jira.reconcile --work-orders PATH --ledger PATH --receipt PATH

  `--work-orders` is a JSON array of WorkOrders (or `{"work_orders": [...]}`),
  `--receipt` a JSON receipt (see `GgenIgniter.SemanticJira.Reconciler.reconcile/3`),
  `--ledger` the ndjson ledger (created on first append).

  Prints one JSON object. Exit `0` for `applied`/`already_applied`, `1` for a
  typed refusal (`{"status": "refused", "reason": [...]}`), `2` for an invalid
  invocation.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [work_orders: :string, ledger: :string, receipt: :string])

    {code, result} = GgenIgniter.SemanticJira.Cli.reconcile(opts)
    Mix.shell().info(Jason.encode!(result))
    if code != 0, do: exit({:shutdown, code})
  end
end
