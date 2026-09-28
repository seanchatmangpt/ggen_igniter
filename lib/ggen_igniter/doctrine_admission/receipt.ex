defmodule GgenIgniter.DoctrineAdmission.Receipt do
  @moduledoc "Creates a replayable receipt without conferring standing or authority."
  alias GgenIgniter.DoctrineAdmission.Determinism

  def issue(%{"identity" => identity, "subject_sha" => sha}, evidence)
      when is_binary(identity) and is_binary(sha) and is_map(evidence) do
    payload = %{"identity" => identity, "subject_sha" => sha, "evidence" => evidence, "authority" => "NONE", "standing" => "UNKNOWN"}
    {:ok, Map.put(payload, "receipt_digest", Determinism.digest(payload))}
  end

  def issue(_, _), do: {:error, {:refused_doctrine, :receipt, :invalid_subject}}
end
