defmodule GgenIgniter.Doctrine.Wave14Test do
  use ExUnit.Case, async: true
  test "wave 14 keeps WorkOrder non-authoritative" do
    c=%{"subject"=>"urn:doctrine:wave:14","source_digest"=>String.duplicate("4",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.WorkOrder.admit(c)
    assert a["authority"]=="NONE"
    assert a["standing"]=="UNKNOWN"
  end
end
