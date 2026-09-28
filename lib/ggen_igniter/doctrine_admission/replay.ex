defmodule GgenIgniter.DoctrineAdmission.Replay do
  @moduledoc "Replays a receipt only against the exact work-order subject."
  alias GgenIgniter.DoctrineAdmission.Determinism

  def verify(%{"identity" => id, "subject_sha" => sha} = receipt,
             %{"identity" => id, "subject_sha" => sha}) do
    expected = receipt |> Map.delete("receipt_digest") |> Determinism.digest()
    if receipt["receipt_digest"] == expected, do: :ok, else: {:error, {:refused_doctrine, :replay, :digest_mismatch}}
  end

  def verify(_, _), do: {:error, {:refused_doctrine, :replay, :subject_mismatch}}
end
