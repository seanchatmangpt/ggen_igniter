defmodule GgenIgniter.SemanticJira.Closure.Refusal do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:refusal) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_refusal,"refusal vocabulary must be explicit and typed"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_refusal,"refusal vocabulary must be explicit and typed"}
end
