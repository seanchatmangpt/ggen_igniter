defmodule GgenIgniter.SemanticJira.Closure.Falsifier do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:falsifier) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_falsifier,"falsifier must be explicit before admission"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_falsifier,"falsifier must be explicit before admission"}
end
