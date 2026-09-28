defmodule GgenIgniter.Doctrine.Wave13Test do
  use ExUnit.Case, async: true
  test "wave 13 keeps Contingency non-authoritative" do
    c=%{"subject"=>"urn:doctrine:wave:13","source_digest"=>String.duplicate("3",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Contingency.admit(c)
    assert a["authority"]=="NONE"
    assert a["standing"]=="UNKNOWN"
  end
end
