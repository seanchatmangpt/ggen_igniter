defmodule GgenIgniter.DoctrineAdmission.ReceiptTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Receipt

  test "receipt binds identity and subject SHA without conferring standing" do
    work = %{"identity" => "doctrine:s1:o1", "subject_sha" => String.duplicate("b", 40)}
    assert {:ok, receipt} = Receipt.issue(work, %{"check" => "local"})
    assert receipt["identity"] == work["identity"]
    assert receipt["standing"] == "UNKNOWN"
    assert receipt["authority"] == "NONE"
    assert byte_size(receipt["receipt_digest"]) == 64
  end
end
