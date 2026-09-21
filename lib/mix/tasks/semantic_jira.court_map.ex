defmodule Mix.Tasks.SemanticJira.CourtMap do
  @shortdoc "Project a work order's court map from the pack ontology's witness facts"

  @moduledoc """
  Upstream minting step of the fabric court-receipt contract.

      mix semantic_jira.court_map --ontology PATH --identity ID [--out PATH]

  Reads the pack ontology and emits the court map for ONE work order: each
  acceptance/falsifier IRI bound to its `sj:witnessedBy` test, plus the
  `sj:requiresCourt` IRIs. The output feeds `Descriptor.build/4`'s
  `:court_map` option (`mix semantic_jira.descriptor --court-map`), which the
  fabric persists on the Run and consumes at close time
  (`Xaas.Ultracode.CourtReceipt`). Refuses when the work order is missing,
  has no court facts, or any acceptance/falsifier IRI is unwitnessed.

  Exit `0` on success; `1` with typed refusal JSON on stderr; `2` for invalid
  invocation.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Cli
  alias GgenIgniter.SemanticJira.CourtMap

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [ontology: :string, identity: :string, out: :string])

    opts |> court_map() |> Cli.emit(opts)
  end

  defp court_map(opts) do
    with {:ok, ontology_path} <- required(opts, :ontology),
         {:ok, identity} <- required(opts, :identity),
         {:ok, ttl} <- read(ontology_path),
         {:ok, court_map} <- CourtMap.from_ontology(ttl, identity) do
      {0, court_map}
    else
      {:error, reason} -> {1, %{"status" => "refused", "reason" => reason}}
      {:invalid, reason} -> {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, ttl} -> {:ok, ttl}
      {:error, reason} -> {:error, {:ontology_unreadable, path, inspect(reason)}}
    end
  end

  defp required(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:invalid, "missing --#{key |> to_string() |> String.replace("_", "-")}"}
    end
  end
end
