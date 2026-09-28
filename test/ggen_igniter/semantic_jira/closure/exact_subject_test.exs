defmodule GgenIgniter.SemanticJira.Closure.ExactSubjectTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.ExactSubject
 test "exact subject identity admits witness and refuses minimal falsifier" do
  assert :ok = ExactSubject.validate(%{subject: "exact_subject:witness"})
  assert {:refused,_,_} = ExactSubject.validate(%{subject: ""})
  assert {:refused,_,_} = ExactSubject.validate(%{})
 end
end
