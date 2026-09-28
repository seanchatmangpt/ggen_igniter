defmodule GgenIgniter.Doctrine.FOND do
  @moduledoc "Doctrine fond boundary; SELECT/CONSTRUCT only."
  def project(candidate) when is_map(candidate) do
    keys = ~w(subject repository base_sha source_digest)
    if Enum.all?(keys, &(is_binary(candidate[&1]) and candidate[&1] != "")), do: {:ok, candidate |> Map.take(keys) |> Map.put("authority", "NONE")}, else: {:error, {:refused_doctrine, :incomplete_identity}}
  end
  def project(_), do: {:error, {:refused_doctrine, :expected_map}}
end
