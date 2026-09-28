defmodule GgenIgniter.Doctrine.Identity do
  def admit(candidate) when is_map(candidate), do: {:ok, candidate}
end
