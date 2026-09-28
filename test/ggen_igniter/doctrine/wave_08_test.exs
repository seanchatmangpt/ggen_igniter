defmodule GgenIgniter.Doctrine.Wave08Test do
  use ExUnit.Case, async: true
  test "wave 8 binds Objective to exact subject" do
    c=%{"subject"=>"urn:doctrine:wave:8","source_digest"=>String.duplicate("8",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Objective.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
  end
end
