defmodule GgenIgniter.DoctrineAdmission.PrimaryConsumerTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.PrimaryConsumer

  test "projects only identity, objective and exact subject to planning" do
    work = %{"identity" => "doctrine:s1:o1", "objective" => "o1", "subject_sha" => String.duplicate("f", 40)}
    assert {:ok, projection} = PrimaryConsumer.project(work)
    assert projection.kind == :planning_candidate
    assert projection.authority == :none
    assert projection.subject_sha == work["subject_sha"]
  end
end
