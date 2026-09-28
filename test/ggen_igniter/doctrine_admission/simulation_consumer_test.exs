defmodule GgenIgniter.DoctrineAdmission.SimulationConsumerTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.SimulationConsumer

  test "simulation projection is replay-bound and authority-free" do
    work = %{"identity" => "doctrine:s1:o1", "objective" => "o1", "replay_identity" => "doctrine:s1:o1:sha"}
    assert {:ok, projection} = SimulationConsumer.project(work)
    assert projection.kind == :simulation_case
    assert projection.replay_identity == work["replay_identity"]
    assert projection.authority == :none
  end
end
