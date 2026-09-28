defmodule GgenIgniter.Doctrine.Wave04Test do
  use ExUnit.Case, async: true
  test "wave 4 preserves exact source and refuses authority escalation" do
    c=%{"subject"=>"urn:doctrine:wave:4","source_digest"=>String.duplicate("4",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.AuthorityCeiling.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
    assert {:error,_}=GgenIgniter.Doctrine.AuthorityCeiling.admit(%{})
  end
end
