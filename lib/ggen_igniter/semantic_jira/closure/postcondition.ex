defmodule GgenIgniter.SemanticJira.Closure.Postcondition do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:postcondition) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_postcondition,"postcondition must be independently observable"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_postcondition,"postcondition must be independently observable"}
end
