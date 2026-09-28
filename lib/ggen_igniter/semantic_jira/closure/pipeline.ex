defmodule GgenIgniter.SemanticJira.Closure.Pipeline do
 @moduledoc false
 alias GgenIgniter.SemanticJira.Closure
 def manufacture(work_order,projector) when is_function(projector,1) do
  with :ok <- Closure.admit(work_order) do {:ok,%{artifact: projector.(work_order),subject: work_order.subject,receipt: work_order.receipt,authority:"CONSTRUCT"}} end
 end
end
