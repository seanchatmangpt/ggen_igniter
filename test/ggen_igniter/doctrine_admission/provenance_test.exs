defmodule GgenIgniter.DoctrineAdmission.ProvenanceTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Provenance

  test "provenance preserves the canonical doctrine source identity" do
    assert {:ok, admitted} =
             Provenance.admit(%{
               "subject" => "doctrine:provenance",
               "source_repository" => "seanchatmangpt/ggen-marketplace",
               "source_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"
             })

    assert admitted["boundary"] == "provenance"
    assert admitted["source_repository"] == "seanchatmangpt/ggen-marketplace"
    assert admitted["source_sha"] == "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"
    assert admitted["authority"] == "NONE"

    assert {:error, {:refused_doctrine, :source_identity, :invalid_exact_subject}} =
             Provenance.admit(%{})
  end
end
