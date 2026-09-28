defmodule GgenIgniter.SemanticJira.Closure.Evidence do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:evidence) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_evidence,"evidence must be a non-empty exact-subject witness"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_evidence,"evidence must be a non-empty exact-subject witness"}
end
