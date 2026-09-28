defmodule GgenIgniter.DoctrineAdmission.BerthierProjection do
  @moduledoc """
  Projects canonical strategic doctrine into the RFC-native Berthier campaign input.

  This module is a consumer bridge only. It preserves the marketplace source
  identity and Berthier's CONSTRUCT ceiling; it cannot authorize actuation.
  """

  alias GgenIgniter.DoctrineAdmission.{Determinism, SourceIdentity}

  @schema "https://chatman.dev/root-crown/berthier-campaign/v1"
  @consumer_repository "seanchatmangpt/chatman-ecosystem"
  @consumer_sha "92cb17cda899a8d85abdaa04db10a3d2334e116d"
  @allowed_actions ~w(OBSERVE SELECT DECOMPOSE ROUTE CONSTRUCT VERIFY)

  def project(%{
        "subject" => subject,
        "source_repository" => _,
        "source_sha" => _,
        "strategy_id" => strategy_id,
        "strategy" => strategy,
        "premise_digests" => premise_digests,
        "invariants" => invariants,
        "local_premise_digests" => local_premise_digests,
        "falsifier" => falsifier,
        "objectives" => objectives
      } = input)
      when is_binary(strategy_id) and is_binary(strategy) and is_map(premise_digests) and
             is_list(invariants) and is_map(local_premise_digests) and is_binary(falsifier) and
             is_map(objectives) do
    actions = Map.get(input, "actions", ["SELECT", "DECOMPOSE", "ROUTE", "CONSTRUCT"])
    capabilities = Map.get(input, "required_capabilities", ["HDDL", "FOND", "SEMANTIC_JIRA"])
    constraints = Map.get(input, "local_constraints", [])

    with {:ok, source} <- SourceIdentity.admit(input),
         :ok <- admit_actions(actions),
         :ok <- admit_objectives(objectives),
         true <- strategy_id != "" and strategy != "" and falsifier != "",
         true <- map_size(premise_digests) > 0 and map_size(local_premise_digests) > 0,
         true <- invariants != [] do
      artifact = %{
        "schema" => @schema,
        "source" => %{
          "repository" => source["source_repository"],
          "sha" => source["source_sha"],
          "artifact_sha" => source["source_artifact_sha"],
          "path" => source["source_path"]
        },
        "consumer" => %{
          "repository" => @consumer_repository,
          "sha" => @consumer_sha
        },
        "doctrine" => %{
          "subject" => subject,
          "premise_digests" => premise_digests,
          "invariants" => Enum.sort(Enum.uniq(invariants)),
          "required_capabilities" => Enum.sort(Enum.uniq(capabilities)),
          "authority_ceiling" => "CONSTRUCT"
        },
        "partition" => %{
          "strategy_id" => strategy_id,
          "strategy" => strategy,
          "local_premise_digests" => local_premise_digests,
          "local_constraints" => Enum.sort(Enum.uniq(constraints))
        },
        "candidate" => %{
          "candidate_id" => Map.get(input, "candidate_id", "candidate:" <> strategy_id),
          "actions" => actions,
          "falsifier" => falsifier,
          "objectives" => objectives,
          "authority_ceiling" => "CONSTRUCT"
        },
        "authority" => "NONE",
        "actuation" => "NONE",
        "successor_boundary" => "SA2A/XaaS -> BRCE -> DO"
      }

      {:ok, Map.put(artifact, "projection_digest", Determinism.digest(artifact))}
    else
      false -> {:error, {:refused_doctrine, :berthier_projection, :unbounded_candidate}}
      {:error, _} = error -> error
    end
  end

  def project(_),
    do: {:error, {:refused_doctrine, :berthier_projection, :invalid_shape}}

  defp admit_actions(actions) when is_list(actions) do
    illegal = Enum.reject(actions, &(&1 in @allowed_actions))

    if illegal == [],
      do: :ok,
      else: {:error, {:refused_doctrine, :berthier_projection, {:illegal_actions, illegal}}}
  end

  defp admit_actions(_),
    do: {:error, {:refused_doctrine, :berthier_projection, :invalid_actions}}

  defp admit_objectives(objectives) do
    if Enum.all?(objectives, fn {name, value} ->
         is_binary(name) and name != "" and is_number(value)
       end),
      do: :ok,
      else: {:error, {:refused_doctrine, :berthier_projection, :invalid_objectives}}
  end
end
