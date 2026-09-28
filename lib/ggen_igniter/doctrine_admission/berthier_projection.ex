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

  def project(input) when is_map(input) do
    actions = Map.get(input, "actions", ["SELECT", "DECOMPOSE", "ROUTE", "CONSTRUCT"])
    capabilities = Map.get(input, "required_capabilities", ["HDDL", "FOND", "SEMANTIC_JIRA"])
    constraints = Map.get(input, "local_constraints", [])

    with :ok <- admit_shape(input),
         {:ok, source} <- SourceIdentity.admit(input),
         :ok <- admit_actions(actions),
         :ok <- admit_objectives(input["objectives"]) do
      artifact =
        build_artifact(
          input,
          source,
          actions,
          capabilities,
          constraints
        )

      {:ok, Map.put(artifact, "projection_digest", Determinism.digest(artifact))}
    end
  end

  def project(_input) do
    {:error, {:refused_doctrine, :berthier_projection, :invalid_shape}}
  end

  defp admit_shape(input) do
    bounded? =
      nonempty?(input["strategy_id"]) and
        nonempty?(input["strategy"]) and
        nonempty?(input["falsifier"]) and
        is_map(input["premise_digests"]) and
        map_size(input["premise_digests"]) > 0 and
        is_map(input["local_premise_digests"]) and
        map_size(input["local_premise_digests"]) > 0 and
        is_list(input["invariants"]) and
        input["invariants"] != [] and
        is_map(input["objectives"])

    if bounded? do
      :ok
    else
      {:error, {:refused_doctrine, :berthier_projection, :invalid_shape}}
    end
  end

  defp build_artifact(input, source, actions, capabilities, constraints) do
    %{
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
        "subject" => input["subject"],
        "premise_digests" => input["premise_digests"],
        "invariants" => Enum.sort(Enum.uniq(input["invariants"])),
        "required_capabilities" => Enum.sort(Enum.uniq(capabilities)),
        "authority_ceiling" => "CONSTRUCT"
      },
      "partition" => %{
        "strategy_id" => input["strategy_id"],
        "strategy" => input["strategy"],
        "local_premise_digests" => input["local_premise_digests"],
        "local_constraints" => Enum.sort(Enum.uniq(constraints))
      },
      "candidate" => %{
        "candidate_id" => Map.get(input, "candidate_id", "candidate:" <> input["strategy_id"]),
        "actions" => actions,
        "falsifier" => input["falsifier"],
        "objectives" => input["objectives"],
        "authority_ceiling" => "CONSTRUCT"
      },
      "authority" => "NONE",
      "actuation" => "NONE",
      "successor_boundary" => "SA2A/XaaS -> BRCE -> DO"
    }
  end

  defp admit_actions(actions) when is_list(actions) do
    illegal = Enum.reject(actions, &(&1 in @allowed_actions))

    if illegal == [] do
      :ok
    else
      {:error, {:refused_doctrine, :berthier_projection, {:illegal_actions, illegal}}}
    end
  end

  defp admit_actions(_actions) do
    {:error, {:refused_doctrine, :berthier_projection, :invalid_actions}}
  end

  defp admit_objectives(objectives) when is_map(objectives) do
    valid? =
      Enum.all?(objectives, fn {name, value} ->
        nonempty?(name) and is_number(value)
      end)

    if valid? do
      :ok
    else
      {:error, {:refused_doctrine, :berthier_projection, :invalid_objectives}}
    end
  end

  defp admit_objectives(_objectives) do
    {:error, {:refused_doctrine, :berthier_projection, :invalid_objectives}}
  end

  defp nonempty?(value) do
    is_binary(value) and value != ""
  end
end
