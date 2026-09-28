defmodule GgenIgniter.Doctrine.Contingency do
  @moduledoc "Bounded doctrine contingency projection with refusal-first exact-source admission."
  def admit(candidate) when is_map(candidate) do
    with subject when is_binary(subject) <- candidate["subject"], digest when is_binary(digest) <- candidate["source_digest"] do
      {:ok, candidate |> Map.put("authority", "NONE") |> Map.put("standing", "UNKNOWN")}
    else _ -> {:error, {:refused_doctrine, :missing_exact_subject}} end
  end
  def admit(_), do: {:error, {:refused_doctrine, :expected_map}}
end
