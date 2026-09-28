defmodule GgenIgniter.Doctrine.Wave10Test do
  use ExUnit.Case, async: true
  test "wave 10 binds Falsifier to exact subject" do
    c=%{"subject"=>"urn:doctrine:wave:10","source_digest"=>String.duplicate("0",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Falsifier.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
  end
end
