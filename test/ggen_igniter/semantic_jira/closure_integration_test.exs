defmodule GgenIgniter.SemanticJira.ClosureIntegrationTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Pipeline
 alias GgenIgniter.SemanticJira.Closure.ConsumerProjection
 @valid %{id:"SJ-CLOSURE",subject:"repo:ggen_igniter",source:"semantic-jira-pack",authority:"CONSTRUCT",standing:"candidate",evidence:"evidence:1",falsifier:"falsifier:1",scope:"repo",receipt:"receipt:1",replay_key:"replay:1",consumer:"consumer:ash_a2a",projection:"derived",checkpoint:"0123456789abcdef0123456789abcdef01234567",refusal:"REFUSED:SEMANTIC_JIRA",postcondition:"observable"}
 test "source admission manufacture consumer chain stays CONSTRUCT-only" do
  assert {:ok,r}=Pipeline.manufacture(@valid,&ConsumerProjection.project/1); assert r.authority=="CONSTRUCT"; assert r.artifact.derived
 end
 test "missing falsifier refuses before consumer projection" do
  assert {:refused,_,_}=Pipeline.manufacture(Map.delete(@valid,:falsifier),&ConsumerProjection.project/1)
 end
end
