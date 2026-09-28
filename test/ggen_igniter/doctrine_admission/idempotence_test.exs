defmodule GgenIgniter.DoctrineAdmission.IdempotenceTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Idempotence

  test "same identity and receipt digest is a no-op duplicate" do
    a = %{"identity" => "x", "receipt_digest" => "abc"}
    assert Idempotence.same?(a, a)
    assert {:ok, :duplicate_noop} = Idempotence.classify(a, a)
  end

  test "different digest remains a distinct artifact" do
    refute Idempotence.same?(%{"identity" => "x", "receipt_digest" => "a"}, %{
             "identity" => "x",
             "receipt_digest" => "b"
           })
  end
end
