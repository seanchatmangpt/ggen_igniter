defmodule GgenIgniter.SemanticJira.Closure.EvidenceTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Evidence
 test "evidence binding admits witness and refuses minimal falsifier" do
  assert :ok = Evidence.validate(%{evidence: "evidence:witness"})
  assert {:refused,_,_} = Evidence.validate(%{evidence: ""})
  assert {:refused,_,_} = Evidence.validate(%{})
 end
end
