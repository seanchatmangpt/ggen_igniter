defmodule GgenIgniter.SemanticJira.Closure.Scope do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:scope) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_scope,"scope must be explicit and bounded"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_scope,"scope must be explicit and bounded"}
end
