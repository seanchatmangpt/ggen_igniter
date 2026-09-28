defmodule GgenIgniter.SemanticJira.Closure.ConsumerTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Consumer
 test "consumer binding admits witness and refuses minimal falsifier" do
  assert :ok = Consumer.validate(%{consumer: "consumer:witness"})
  assert {:refused,_,_} = Consumer.validate(%{consumer: ""})
  assert {:refused,_,_} = Consumer.validate(%{})
 end
end
