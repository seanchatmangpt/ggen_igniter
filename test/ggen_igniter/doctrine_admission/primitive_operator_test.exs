defmodule GgenIgniter.DoctrineAdmission.PrimitiveOperatorTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.PrimitiveOperator
  @sha "009807a9226e001acbb5c686ea1dd002d0d1ef72"
  test "exact-subject admission and refusal" do
    assert {:ok,a}=PrimitiveOperator.admit(%{"subject"=>"doctrine:primitive_operator","source_sha"=>@sha})
    assert a["authority"]=="NONE" and a["ceiling"]=="CONSTRUCT"
    assert {:error,{:refused_doctrine,:primitive_operator,:invalid_exact_subject}}=PrimitiveOperator.admit(%{})
  end
end
