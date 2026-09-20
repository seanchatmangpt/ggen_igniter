defmodule Mix.Tasks.SemanticJira.XaasReceipt do
  @shortdoc "Map a sealed XaaS receipt onto the receipt the Semantic Jira reconciler consumes"

  @moduledoc """
  Return edge of the frontier -> XaaS -> reconciler loop.

      mix semantic_jira.xaas_receipt --bridge PATH --xaas-receipt PATH [--out PATH]

  `--bridge` is the `"bridge"` object of the descriptor that was executed (or
  the whole descriptor JSON); `--xaas-receipt` is the sealed XaaS receipt export
  (contract in `GgenIgniter.SemanticJira.Descriptor`). The receipt is refused
  unless its digest recomputes, it echoes the bridge verbatim, its head is a
  40-hex sha, and an `alive` outcome carries a verified head and a passing
  fabric verifier. Pipe the output to `mix semantic_jira.reconcile --receipt`.

  Exit `0` on success; `1` with typed refusal JSON on stderr; `2` for invalid
  invocation.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Cli

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [bridge: :string, xaas_receipt: :string, out: :string])

    opts |> Cli.xaas_receipt() |> Cli.emit(opts)
  end
end
