defmodule Mix.Tasks.SemanticJira.Prov do
  @shortdoc "Export the Semantic Jira standing ledger as PROV-O Turtle"

  @moduledoc """
  Serializes the standing transition ledger as PROV-O (`prov:Activity` /
  `prov:Entity` / `prov:wasDerivedFrom`), validated by the SHACL court.

      mix semantic_jira.prov --ledger PATH [--out PATH]

  With `--out` the Turtle is written to that path and one JSON status line is
  printed; without it the JSON carries the Turtle in `"turtle"`. Exit `0` on
  success, `1` when the ledger is refused (tampered/undecodable) or the
  serialization fails SHACL, `2` for an invalid invocation.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Cli

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [ledger: :string, out: :string])
    # `--out` names the Turtle file, so it is not forwarded to `emit/2`
    # (which would overwrite it with the JSON status).
    opts |> Cli.prov() |> Cli.emit([])
  end
end
