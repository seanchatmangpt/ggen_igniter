defmodule GgenIgniter.DoctrineAdmission.PrimaryConsumer do
  @moduledoc "Projects an admitted work order for the primary execution-planning consumer."

  def project(%{"identity" => id, "objective" => objective, "subject_sha" => sha})
      when is_binary(id) and is_binary(objective) and is_binary(sha) do
    {:ok, %{kind: :planning_candidate, identity: id, objective: objective, subject_sha: sha, authority: :none}}
  end

  def project(_), do: {:error, {:refused_doctrine, :consumer, :invalid_primary_input}}
end
