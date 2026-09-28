defmodule GgenIgniter.DoctrineAdmission.Receipt do
  @moduledoc "Creates a replayable receipt bound to the exact canonical doctrine source."
  alias GgenIgniter.DoctrineAdmission.Determinism

  @required ~w(identity subject_sha source_repository source_artifact_sha source_path)

  def issue(work, evidence) when is_map(work) and is_map(evidence) do
    if Enum.all?(@required, &is_binary(work[&1])) do
      payload = %{
        "identity" => work["identity"],
        "subject_sha" => work["subject_sha"],
        "source_repository" => work["source_repository"],
        "source_artifact_sha" => work["source_artifact_sha"],
        "source_path" => work["source_path"],
        "evidence" => evidence,
        "authority" => "NONE",
        "standing" => "UNKNOWN"
      }

      {:ok, Map.put(payload, "receipt_digest", Determinism.digest(payload))}
    else
      {:error, {:refused_doctrine, :receipt, :invalid_subject}}
    end
  end

  def issue(_, _), do: {:error, {:refused_doctrine, :receipt, :invalid_subject}}
end
