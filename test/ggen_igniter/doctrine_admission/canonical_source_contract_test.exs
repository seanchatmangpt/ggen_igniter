defmodule GgenIgniter.DoctrineAdmission.CanonicalSourceContractTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.DoctrineAdmission.SourceIdentity

  test "source contract pins the merged marketplace pack" do
    assert %{
             "source_repository" => "seanchatmangpt/ggen-marketplace",
             "source_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa",
             "source_artifact_sha" => "225e3eff18f0570817646ebf7c210117ee1a82b5",
             "source_path" => "packs/strategic-doctrine-pack",
             "authority" => "NONE",
             "ceiling" => "CONSTRUCT"
           } = SourceIdentity.contract()
  end
end
