defmodule GgenIgniter.DoctrineAdmission.EvidenceGuardTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.EvidenceGuard

  test "admits bounded evidence and refuses literal standing" do
    assert {:ok, _} =
             EvidenceGuard.admit(%{
               "standing" => "UNKNOWN",
               "authority_requirement" => "NONE",
               "evidence_ceiling" => "CONSTRUCT"
             })

    assert {:error, {:refused_doctrine, :evidence, {:literal_standing, "ALIVE"}}} =
             EvidenceGuard.admit(%{"standing" => "ALIVE"})
  end

  test "refuses actuation-shaped evidence ceilings" do
    assert {:error, {:refused_doctrine, :evidence, {:ceiling, "DEPLOY"}}} =
             EvidenceGuard.admit(%{"evidence_ceiling" => "DEPLOY"})
  end
end
