defmodule GgenIgniter.SemanticJira.Closure.SourceIdentityTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.SourceIdentity
 test "source provenance admits witness and refuses minimal falsifier" do
  assert :ok = SourceIdentity.validate(%{source: "source_identity:witness"})
  assert {:refused,_,_} = SourceIdentity.validate(%{source: ""})
  assert {:refused,_,_} = SourceIdentity.validate(%{})
 end
end
