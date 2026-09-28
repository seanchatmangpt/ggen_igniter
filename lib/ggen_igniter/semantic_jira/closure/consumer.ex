defmodule GgenIgniter.SemanticJira.Closure.Consumer do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:consumer) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_consumer,"consumer must be named before projection"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_consumer,"consumer must be named before projection"}
end
