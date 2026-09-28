defmodule GgenIgniter.DoctrineAdmission.Contingency do
  @moduledoc "Compiles a falsifier into a bounded FOND contingency."
  @comparators ~w(lt lte gt gte eq)

  def build(%{"strategy" => strategy, "falsifier" => falsifier}) when is_binary(strategy) and is_map(falsifier) do
    with property when is_binary(property) <- falsifier["property"],
         comparator when comparator in @comparators <- falsifier["comparator"],
         threshold when is_number(threshold) <- falsifier["threshold"] do
      {:ok, %{"strategy" => strategy, "observe" => %{"property" => property, "comparator" => comparator, "threshold" => threshold}, "outcomes" => ["held", "refuted"], "authority" => "NONE"}}
    else
      _ -> {:error, {:refused_doctrine, :contingency, :invalid_falsifier}}
    end
  end

  def build(_), do: {:error, {:refused_doctrine, :contingency, :invalid_shape}}
end
