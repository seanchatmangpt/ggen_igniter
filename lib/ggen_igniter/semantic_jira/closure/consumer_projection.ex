defmodule GgenIgniter.SemanticJira.Closure.ConsumerProjection do
 @moduledoc false
 def project(wo), do: %{id: wo.id,subject: wo.subject,source: wo.source,consumer: wo.consumer,derived: true}
end
