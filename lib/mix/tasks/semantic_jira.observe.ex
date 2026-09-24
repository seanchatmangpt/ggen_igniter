defmodule Mix.Tasks.SemanticJira.Observe do
  @shortdoc "Admit an observed process finding as a candidate Semantic Jira WorkOrder"

  @moduledoc """
  Observation edge: a finding becomes a candidate WorkOrder that is admitted by
  the kernel and the SHACL court, or refused with a typed reason.

      mix semantic_jira.observe --finding PATH --base-work-order PATH \\
        [--ontology PATH] [--repair PATH] [--identity ID] [--out PATH]

  `--finding` holds the `process_finding/1` attrs; `--base-work-order` is the
  WorkOrder whose typed courts, evidence, projections, ceilings and path scope
  the candidate reuses; `--ontology` is the canonical graph SHACL runs over
  (default: the pack ontology); `--repair` optionally holds
  `repair_work_order/2` attrs. Prints the admitted work order, its Turtle and
  the SHACL report. Nothing is written to the canonical graph.

  Exit `0` on success; `1` with typed refusal JSON on stderr; `2` for invalid
  invocation.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Cli

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          finding: :string,
          base_work_order: :string,
          ontology: :string,
          repair: :string,
          identity: :string,
          out: :string
        ]
      )

    {:ok, _} = Application.ensure_all_started(:rdf)
    {:ok, _} = Application.ensure_all_started(:sparql)
    opts |> Cli.observe() |> Cli.emit(opts)
  end
end
