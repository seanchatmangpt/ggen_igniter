defmodule GgenIgniter.SemanticJira.Closure.AuthorityCeiling do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:authority) do
   v when is_binary(v) and byte_size(v)>0 -> if v in ["OBSERVE","SELECT","CONSTRUCT"], do: :ok, else: {:refused,:semantic_jira_authority_ceiling,"DO authority is outside manufacture"}
   _ -> {:refused,:semantic_jira_authority_ceiling,"authority must be CONSTRUCT or lower"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_authority_ceiling,"authority must be CONSTRUCT or lower"}
end
