defmodule GgenIgniter.SemanticJira.Closure.ReceiptTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Receipt
 test "receipt identity admits witness and refuses minimal falsifier" do
  assert :ok = Receipt.validate(%{receipt: "receipt:witness"})
  assert {:refused,_,_} = Receipt.validate(%{receipt: ""})
  assert {:refused,_,_} = Receipt.validate(%{})
 end
end
