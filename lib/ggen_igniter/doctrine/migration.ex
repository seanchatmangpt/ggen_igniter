defmodule GgenIgniter.Doctrine.Migration do
  @moduledoc "Doctrine migration exact-source boundary."
  def bind(candidate) when is_map(candidate) do
    required = ~w(subject repository base_sha source_digest)
    if Enum.all?(required, &is_binary(candidate[&1])), do: {:ok, Map.put(candidate,"authority","NONE")}, else: {:error,:incomplete_identity}
  end
  def bind(_), do: {:error,:expected_map}
end
