defmodule GgenIgniter.DoctrineAdmission.SemanticJiraProjection do
  @moduledoc "Manufactures a Semantic Jira work-order candidate from canonical strategic doctrine."
  alias GgenIgniter.DoctrineAdmission.{ExactSubject, OriginAuthority}

  def project(
        %{
          "subject" => _,
          "source_repository" => _,
          "source_sha" => _,
          "objective" => objective,
          "origin_authority" => origin
        } = input
      )
      when is_binary(objective) do
    with {:ok, bounded} <- ExactSubject.admit(input),
         :ok <- OriginAuthority.admit(origin) do
      identity = "doctrine:" <> bounded["subject"] <> ":" <> objective

      {:ok,
       %{
         "identity" => identity,
         "replay_identity" =>
           Enum.join(
             [
               identity,
               bounded["source_repository"],
               bounded["source_sha"],
               bounded["source_artifact_sha"]
             ],
             ":"
           ),
         "subject" => bounded["subject"],
         "subject_sha" => bounded["source_sha"],
         "source_repository" => bounded["source_repository"],
         "source_artifact_sha" => bounded["source_artifact_sha"],
         "source_path" => bounded["source_path"],
         "origin_authority" => origin,
         "objective" => objective,
         "standing" => "UNKNOWN",
         "authority_requirement" => "NONE",
         "evidence_ceiling" => "CONSTRUCT"
       }}
    end
  end

  def project(_),
    do: {:error, {:refused_doctrine, :semantic_jira_projection, :invalid_shape}}
end
