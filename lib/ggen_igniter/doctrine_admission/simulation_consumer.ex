defmodule GgenIgniter.DoctrineAdmission.SimulationConsumer do
  @moduledoc "Projects doctrine into a simulation-only consumer with no actuation authority."

  def project(%{"identity" => id, "objective" => objective, "replay_identity" => replay})
      when is_binary(id) and is_binary(objective) and is_binary(replay) do
    {:ok, %{kind: :simulation_case, identity: id, objective: objective, replay_identity: replay, authority: :none}}
  end

  def project(_), do: {:error, {:refused_doctrine, :consumer, :invalid_simulation_input}}
end
