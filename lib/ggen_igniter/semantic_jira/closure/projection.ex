defmodule GgenIgniter.SemanticJira.Closure.Projection do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:projection) do
   v when is_binary(v) and byte_size(v)>0 -> if v=="derived", do: :ok, else: {:refused,:semantic_jira_projection,"projection is not an edit root"}
   _ -> {:refused,:semantic_jira_projection,"projection must be marked derived"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_projection,"projection must be marked derived"}
end
