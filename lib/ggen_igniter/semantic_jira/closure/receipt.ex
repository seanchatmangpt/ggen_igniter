defmodule GgenIgniter.SemanticJira.Closure.Receipt do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:receipt) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_receipt,"receipt must bind subject source and admitted work order"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_receipt,"receipt must bind subject source and admitted work order"}
end
