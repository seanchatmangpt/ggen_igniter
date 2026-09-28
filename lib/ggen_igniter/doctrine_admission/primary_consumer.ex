defmodule GgenIgniter.DoctrineAdmission.PrimaryConsumer do
  @moduledoc "Projects an admitted doctrine work order to planning without losing exact-source provenance."

  @required ~w(identity objective subject_sha source_repository source_artifact_sha source_path)

  def project(work) when is_map(work) do
    if Enum.all?(@required, &is_binary(work[&1])) do
      {:ok,
       %{
         kind: :planning_candidate,
         identity: work["identity"],
         objective: work["objective"],
         subject_sha: work["subject_sha"],
         source_repository: work["source_repository"],
         source_artifact_sha: work["source_artifact_sha"],
         source_path: work["source_path"],
         authority: :none
       }}
    else
      {:error, {:refused_doctrine, :consumer, :invalid_primary_input}}
    end
  end

  def project(_), do: {:error, {:refused_doctrine, :consumer, :invalid_primary_input}}
end
