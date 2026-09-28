defmodule GgenIgniter.DoctrineAdmission.ReceiptTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Receipt

  test "receipt binds full canonical source identity without conferring standing" do
    work = %{
      "identity" => "doctrine:s1:o1",
      "subject_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa",
      "source_repository" => "seanchatmangpt/ggen-marketplace",
      "source_artifact_sha" => "225e3eff18f0570817646ebf7c210117ee1a82b5",
      "source_path" => "packs/strategic-doctrine-pack"
    }

    assert {:ok, receipt} = Receipt.issue(work, %{"check" => "local"})
    assert receipt["identity"] == work["identity"]
    assert receipt["source_repository"] == work["source_repository"]
    assert receipt["source_artifact_sha"] == work["source_artifact_sha"]
    assert receipt["source_path"] == work["source_path"]
    assert receipt["standing"] == "UNKNOWN"
    assert receipt["authority"] == "NONE"
    assert byte_size(receipt["receipt_digest"]) == 64
  end

  test "refuses a receipt missing canonical source identity" do
    assert {:error, {:refused_doctrine, :receipt, :invalid_subject}} =
             Receipt.issue(%{"identity" => "x", "subject_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"}, %{})
  end
end
