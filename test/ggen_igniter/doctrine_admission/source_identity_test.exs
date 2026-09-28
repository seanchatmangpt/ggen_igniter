defmodule GgenIgniter.DoctrineAdmission.SourceIdentityTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.SourceIdentity
  @sha "009807a9226e001acbb5c686ea1dd002d0d1ef72"
  test "admits exact subject and refuses an unbound candidate" do
    assert {:ok, admitted} = SourceIdentity.admit(%{"subject"=>"doctrine:source_identity","source_sha"=>@sha})
    assert admitted["authority"] == "NONE"
    assert admitted["ceiling"] == "CONSTRUCT"
    assert {:error, {:refused_doctrine, :source_identity, :invalid_exact_subject}} = SourceIdentity.admit(%{})
  end
end
