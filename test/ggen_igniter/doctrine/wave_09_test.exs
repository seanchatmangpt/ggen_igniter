defmodule GgenIgniter.Doctrine.Wave09Test do
  use ExUnit.Case, async: true
  test "wave 9 binds Condition to exact subject" do
    c=%{"subject"=>"urn:doctrine:wave:9","source_digest"=>String.duplicate("9",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Condition.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
  end
end
