defmodule GgenIgniter.Doctrine.Wave12Test do
  use ExUnit.Case, async: true
  test "wave 12 keeps Method non-authoritative" do
    c=%{"subject"=>"urn:doctrine:wave:12","source_digest"=>String.duplicate("2",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Method.admit(c)
    assert a["authority"]=="NONE"
    assert a["standing"]=="UNKNOWN"
  end
end
