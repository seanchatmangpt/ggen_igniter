defmodule GgenIgniter.SemanticJira.Closure.Checkpoint do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:checkpoint) do
   v when is_binary(v) and byte_size(v)>0 -> if byte_size(v)==40, do: :ok, else: {:refused,:semantic_jira_checkpoint,"checkpoint must be exact SHA"}
   _ -> {:refused,:semantic_jira_checkpoint,"checkpoint must bind the exact base SHA"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_checkpoint,"checkpoint must bind the exact base SHA"}
end
