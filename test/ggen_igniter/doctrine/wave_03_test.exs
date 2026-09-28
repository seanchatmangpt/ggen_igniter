defmodule GgenIgniter.Doctrine.Wave03Test do
  use ExUnit.Case, async: true
  test "wave 3 preserves exact source and refuses authority escalation" do
    c=%{"subject"=>"urn:doctrine:wave:3","source_digest"=>String.duplicate("3",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.AuthorityCeiling.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
    assert {:error,_}=GgenIgniter.Doctrine.AuthorityCeiling.admit(%{})
  end
end
