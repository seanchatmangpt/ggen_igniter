defmodule GgenIgniter.SemanticJira.Closure.SourceIdentity do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:source) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_source_identity,"source must identify the canonical semantic source"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_source_identity,"source must identify the canonical semantic source"}
end
