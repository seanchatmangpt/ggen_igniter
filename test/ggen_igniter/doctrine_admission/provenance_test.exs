defmodule GgenIgniter.DoctrineAdmission.ProvenanceTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Provenance
  @sha "009807a9226e001acbb5c686ea1dd002d0d1ef72"
  test "admits exact subject and refuses an unbound candidate" do
    assert {:ok, admitted} = Provenance.admit(%{"subject"=>"doctrine:provenance","source_sha"=>@sha})
    assert admitted["authority"] == "NONE"
    assert admitted["ceiling"] == "CONSTRUCT"
    assert {:error, {:refused_doctrine, :provenance, :invalid_exact_subject}} = Provenance.admit(%{})
  end
end
