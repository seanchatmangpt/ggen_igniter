defmodule GgenIgniter.DoctrineAdmission.Migration do
  @moduledoc "Migrates legacy doctrine candidates while preserving exact source identity."

  def to_v1(%{"subject" => subject, "source_sha" => sha} = legacy)
      when is_binary(subject) and is_binary(sha) and byte_size(sha) == 40 do
    {:ok,
     legacy
     |> Map.put_new("schema_version", "doctrine-admission/v1")
     |> Map.put_new("standing", "UNKNOWN")
     |> Map.put_new("authority_requirement", "NONE")
     |> Map.put_new("evidence_ceiling", "CONSTRUCT")}
  end

  def to_v1(_), do: {:error, {:refused_doctrine, :migration, :missing_exact_subject}}
end
