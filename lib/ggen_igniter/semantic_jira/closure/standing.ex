defmodule GgenIgniter.SemanticJira.Closure.Standing do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:standing) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_standing,"standing must be explicit and cannot be inferred from generation"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_standing,"standing must be explicit and cannot be inferred from generation"}
end
