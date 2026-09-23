defmodule Mix.Tasks.SemanticJira.Observe do
  @shortdoc "Observe a fleet of git repositories as SHA-bound PROV-O Turtle"

  @moduledoc """
  Fleet observation edge (GGEN_IGNITER-26922-15).

      mix semantic_jira.observe --fleet REGISTRY.ttl --out OBS.ttl

  `--fleet` is a registry graph of `sj:ObservedRepository` nodes with
  `sj:repositoryPath`; `--out` receives one PROV-O `sj:RepositoryObservation`
  per repository (refs with ahead/behind, ls-remote delta, worktrees with
  dirty state, stashes, open PRs with checks, CI conclusion at the
  default-branch SHA), every entity bound to the SHA it observed. See
  `GgenIgniter.SemanticJira.FleetObservation`.

  Only `--fleet` mode exists at this subject. The historical `--finding`
  observation edge (commit 92cd993) is not on this line; invoking the task
  without `--fleet` raises the typed refusal
  `REFUSED:SEMANTIC_JIRA_OBSERVE_MODE_UNSUPPORTED` instead of guessing.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.FleetObservation

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: [fleet: :string, out: :string])

    fleet = Keyword.get(opts, :fleet)
    out = Keyword.get(opts, :out)

    cond do
      invalid != [] ->
        Mix.raise("REFUSED:SEMANTIC_JIRA_OBSERVE_INVALID: unknown options #{inspect(invalid)}")

      is_nil(fleet) ->
        Mix.raise(
          "REFUSED:SEMANTIC_JIRA_OBSERVE_MODE_UNSUPPORTED: only --fleet REGISTRY.ttl " <>
            "--out OBS.ttl is available at this subject"
        )

      is_nil(out) ->
        Mix.raise("REFUSED:SEMANTIC_JIRA_OBSERVE_INVALID: --fleet requires --out OBS.ttl")

      not File.regular?(fleet) ->
        Mix.raise("REFUSED:SEMANTIC_JIRA_OBSERVE_INVALID: fleet registry #{fleet} is not a file")

      true ->
        {:ok, _} = Application.ensure_all_started(:rdf)
        {:ok, _} = Application.ensure_all_started(:sparql)
        %{repositories: count} = FleetObservation.write!(fleet, out)
        Mix.shell().info("observed #{count} repositories from #{fleet} -> #{out}")
    end
  end
end
