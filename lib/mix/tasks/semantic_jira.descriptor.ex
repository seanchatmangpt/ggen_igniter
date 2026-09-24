defmodule Mix.Tasks.SemanticJira.Descriptor do
  @shortdoc "Project one Semantic Jira frontier candidate into a XaaS execution descriptor"

  @moduledoc """
  Builds the descriptor `Xaas.Ultracode.SemanticWork.admit/1` consumes for ONE
  work order that is on the current frontier.

      mix semantic_jira.descriptor --work-orders PATH --ledger PATH --identity ID \\
        --alias owner/repo=alias --verifier-suite NAME [--provider NAME] \\
        [--court-map PATH] [--out PATH]

  `--alias` (repeatable) maps a WorkOrder's `repository` to the XaaS
  `execution_repo_alias`; `--verifier-suite` names the registered XaaS suite.
  `--provider` names the XaaS construction provider bound into the descriptor
  (default `recipe`, the deterministic XaaS RecipeWorker; an LLM provider such
  as `zcode` is bound only when passed explicitly, e.g. `--provider zcode`).
  `--court-map` is the minted court map JSON (`mix semantic_jira.court_map`)
  binding the work order's acceptance/falsifier IRIs to witnessing tests; the
  fabric uses it at close time to witness IRI-keyed verdicts. Nothing is
  defaulted except `--provider`. The JSON object printed on stdout is the
  descriptor plus a `"bridge"` key that XaaS must echo back in its receipt.

  Exit `0` on success; `1` with typed refusal JSON on stderr (identity not on
  the frontier, tampered ledger, missing alias, ...); `2` for invalid invocation.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Cli

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          work_orders: :string,
          ledger: :string,
          identity: :string,
          alias: :keep,
          verifier_suite: :string,
          provider: :string,
          court_map: :string,
          out: :string
        ]
      )

    opts |> Cli.descriptor() |> Cli.emit(opts)
  end
end
