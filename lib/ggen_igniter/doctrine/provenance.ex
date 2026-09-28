defmodule GgenIgniter.Doctrine.Provenance do
  @moduledoc "Bounded doctrine provenance projection."
  def admit(candidate) when is_map(candidate) do
    if is_binary(candidate["subject"]) and is_binary(candidate["source_digest"]), do: {:ok, Map.put(candidate, "authority", "NONE")}, else: {:error, :missing_exact_subject}
  end
  def admit(_), do: {:error, :expected_map}
end
