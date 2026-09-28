defmodule GgenIgniter.DoctrineAdmission.RecoveryTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Recovery

  test "routes replay failure to exact-subject rebind" do
    assert {:repair, :rebind_exact_subject} = Recovery.route(%{status: :refused, boundary: :replay})
  end

  test "unknown non-refusal does not manufacture a bypass" do
    assert {:stop, :not_a_refusal} = Recovery.route(%{status: :ok})
  end
end
