defmodule GgenIgniter.Doctrine.Receipt do
  @moduledoc "Doctrine receipt composition surface."
  def bind(candidate) when is_map(candidate), do: {:ok, candidate |> Map.put("authority", "NONE") |> Map.put("standing", "UNKNOWN")}
  def bind(_), do: {:error, :expected_map}
end
