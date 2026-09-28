defmodule GgenIgniter.DoctrineAdmission.FondProjection do
  @moduledoc "Projects doctrine falsifiers into a bounded nondeterministic policy IR."
  alias GgenIgniter.DoctrineAdmission.Contingency

  def project(candidate) do
    with {:ok, contingency} <- Contingency.build(candidate) do
      {:ok,
       %{
         "action" => "observe:" <> contingency["strategy"],
         "effect" => {:oneof, contingency["outcomes"]},
         "observation" => contingency["observe"],
         "authority" => "NONE"
       }}
    end
  end
end
