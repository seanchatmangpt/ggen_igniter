defmodule GgenIgniter.Doctrine.Wave11Test do
  use ExUnit.Case, async: true
  test "wave 11 keeps Step non-authoritative" do
    c=%{"subject"=>"urn:doctrine:wave:11","source_digest"=>String.duplicate("1",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Step.admit(c)
    assert a["authority"]=="NONE"
    assert a["standing"]=="UNKNOWN"
  end
end
