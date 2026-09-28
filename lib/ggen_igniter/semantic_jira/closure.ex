defmodule GgenIgniter.SemanticJira.Closure do
 @moduledoc false
 @courts [GgenIgniter.SemanticJira.Closure.ExactSubject,GgenIgniter.SemanticJira.Closure.SourceIdentity,GgenIgniter.SemanticJira.Closure.AuthorityCeiling,GgenIgniter.SemanticJira.Closure.Standing,GgenIgniter.SemanticJira.Closure.Evidence,GgenIgniter.SemanticJira.Closure.Falsifier,GgenIgniter.SemanticJira.Closure.Scope,GgenIgniter.SemanticJira.Closure.Receipt,GgenIgniter.SemanticJira.Closure.Replay,GgenIgniter.SemanticJira.Closure.Consumer,GgenIgniter.SemanticJira.Closure.Projection,GgenIgniter.SemanticJira.Closure.Checkpoint,GgenIgniter.SemanticJira.Closure.Refusal,GgenIgniter.SemanticJira.Closure.Postcondition]
 def courts, do: @courts
 def admit(work_order), do: Enum.reduce_while(@courts,:ok,fn court,:ok -> case court.validate(work_order) do :ok->{:cont,:ok}; {:refused,_,_}=r->{:halt,r} end end)
end
