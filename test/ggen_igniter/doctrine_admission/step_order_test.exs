defmodule GgenIgniter.DoctrineAdmission.StepOrderTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.StepOrder
  @sha "009807a9226e001acbb5c686ea1dd002d0d1ef72"
  test "exact-subject admission and refusal" do
    assert {:ok,a}=StepOrder.admit(%{"subject"=>"doctrine:step_order","source_sha"=>@sha})
    assert a["authority"]=="NONE" and a["ceiling"]=="CONSTRUCT"
    assert {:error,{:refused_doctrine,:step_order,:invalid_exact_subject}}=StepOrder.admit(%{})
  end
end
