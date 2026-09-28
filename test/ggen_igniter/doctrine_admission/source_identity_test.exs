defmodule GgenIgniter.DoctrineAdmission.SourceIdentityTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.SourceIdentity

  @repo "seanchatmangpt/ggen-marketplace"
  @sha "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"

  test "admits only the merged canonical doctrine source" do
    assert {:ok, admitted} =
             SourceIdentity.admit(%{
               "subject" => "doctrine:source_identity",
               "source_repository" => @repo,
               "source_sha" => @sha
             })

    assert admitted["source_artifact_sha"] == "225e3eff18f0570817646ebf7c210117ee1a82b5"
    assert admitted["source_path"] == "packs/strategic-doctrine-pack"
    assert admitted["authority"] == "NONE"
    assert admitted["ceiling"] == "CONSTRUCT"
  end

  test "refuses source drift and missing identity" do
    assert {:error, {:refused_doctrine, :source_identity, {:source_mismatch, @repo, "drift"}}} =
             SourceIdentity.admit(%{
               "subject" => "doctrine:source_identity",
               "source_repository" => @repo,
               "source_sha" => "drift"
             })

    assert {:error, {:refused_doctrine, :source_identity, :invalid_exact_subject}} =
             SourceIdentity.admit(%{})
  end
end
