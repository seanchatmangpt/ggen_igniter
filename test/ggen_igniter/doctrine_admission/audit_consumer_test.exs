defmodule GgenIgniter.DoctrineAdmission.AuditConsumerTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.AuditConsumer

  test "audit projection carries receipt and subject identity without authority" do
    receipt = %{
      "identity" => "doctrine:s1:o1",
      "receipt_digest" => String.duplicate("a", 64),
      "subject_sha" => String.duplicate("f", 40)
    }

    assert {:ok, projection} = AuditConsumer.project(receipt)
    assert projection.kind == :audit_record
    assert projection.digest == receipt["receipt_digest"]
    assert projection.authority == :none
  end
end
