defmodule GgenIgniter.SemanticJira.Closure.ExactSubject do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:subject) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_exact_subject,"subject must be a non-empty repository-relative IRI"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_exact_subject,"subject must be a non-empty repository-relative IRI"}
end
