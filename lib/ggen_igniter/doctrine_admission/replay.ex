defmodule GgenIgniter.DoctrineAdmission.Replay do
  @moduledoc "Replays a receipt only against the exact canonical source-bound work subject."
  alias GgenIgniter.DoctrineAdmission.Determinism

  @identity_fields ~w(identity subject_sha source_repository source_artifact_sha source_path)

  def verify(receipt, work) when is_map(receipt) and is_map(work) do
    with true <- same_identity?(receipt, work),
         true <- is_binary(receipt["receipt_digest"]) do
      expected =
        receipt
        |> Map.delete("receipt_digest")
        |> Determinism.digest()

      if receipt["receipt_digest"] == expected do
        :ok
      else
        {:error, {:refused_doctrine, :replay, :digest_mismatch}}
      end
    else
      _value ->
        {:error, {:refused_doctrine, :replay, :subject_mismatch}}
    end
  end

  def verify(_receipt, _work) do
    {:error, {:refused_doctrine, :replay, :subject_mismatch}}
  end

  defp same_identity?(receipt, work) do
    Enum.all?(@identity_fields, fn field ->
      is_binary(receipt[field]) and receipt[field] == work[field]
    end)
  end
end
