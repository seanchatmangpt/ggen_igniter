defmodule GgenIgniter.DoctrineAdmission.Determinism do
  @moduledoc "Stable digest for doctrine artifacts using recursively sorted canonical terms."

  def digest(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  def canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical()
  def canonical(other), do: other
end
