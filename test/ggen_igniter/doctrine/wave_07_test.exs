defmodule GgenIgniter.Doctrine.Wave07Test do
  use ExUnit.Case, async: true
  test "wave 7 binds Primitive to exact subject" do
    c=%{"subject"=>"urn:doctrine:wave:7","source_digest"=>String.duplicate("7",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Primitive.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
  end
end
