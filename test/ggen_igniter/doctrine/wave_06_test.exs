defmodule GgenIgniter.Doctrine.Wave06Test do
  use ExUnit.Case, async: true
  test "wave 6 binds Provenance to exact subject" do
    c=%{"subject"=>"urn:doctrine:wave:6","source_digest"=>String.duplicate("6",64)}
    assert {:ok,a}=GgenIgniter.Doctrine.Provenance.admit(c)
    assert a["subject"]==c["subject"]
    assert a["authority"]=="NONE"
  end
end
