defmodule GgenIgniter.SemanticJira.Closure.Replay do
 @moduledoc false
 def validate(wo) when is_map(wo) do
  case Map.get(wo,:replay_key) do
   v when is_binary(v) and byte_size(v)>0 -> :ok
   _ -> {:refused,:semantic_jira_replay,"replay_key must be stable and non-empty"}
  end
 end
 def validate(_), do: {:refused,:semantic_jira_replay,"replay_key must be stable and non-empty"}
end
