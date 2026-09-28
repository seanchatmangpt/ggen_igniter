defmodule GgenIgniter.DoctrineAdmission.Replay do
  @moduledoc "Replays a receipt only against the exact canonical source-bound work subject."
  alias GgenIgniter.DoctrineAdmission.Determinism

  @identity_fields ~w(identity subject_sha source_repository source_artifact_sha source_path)

  def verify(receipt, work) when is_map(receipt) and is_map(work) do
    with true <- Enum.all?(@identity_fields, &(is_binary(receipt[&1]) and receipt[&1] == work[&1])),
         true <- is_binary(receipt["receipt_digest"]) do
      expected = receipt |> Map.delete("receipt_digest") |> Determinism.digest()

      if receipt["receipt_digest"] == expected,
        do: :ok,
        else: {:error, {:refused_doctrine, :replay, :digest_mismatch}}
    else
      _ -> {:error, {:refused_doctrine, :replay, :subject_mismatch}}
    end
  end

  def verify(_, _), do: {:error, {:refused_doctrine, :replay, :subject_mismatch}}
end
