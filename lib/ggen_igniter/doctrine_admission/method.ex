defmodule GgenIgniter.DoctrineAdmission.Method do
  @moduledoc "Builds an ordered doctrine method from admitted primitive steps."

  def build(%{"strategy" => strategy, "steps" => steps})
      when is_binary(strategy) and is_list(steps) do
    ordered = Enum.sort_by(steps, &Map.get(&1, "order"))

    cond do
      ordered == [] ->
        {:error, {:refused_doctrine, :method, :empty_steps}}

      Enum.any?(ordered, &(not is_integer(&1["order"]) or not is_binary(&1["operator"]))) ->
        {:error, {:refused_doctrine, :method, :invalid_step}}

      Enum.map(ordered, & &1["order"]) != Enum.to_list(1..length(ordered)) ->
        {:error, {:refused_doctrine, :method, :non_total_order}}

      true ->
        {:ok,
         %{
           "strategy" => strategy,
           "steps" => ordered,
           "authority" => "NONE",
           "ceiling" => "CONSTRUCT"
         }}
    end
  end

  def build(_), do: {:error, {:refused_doctrine, :method, :invalid_shape}}
end
