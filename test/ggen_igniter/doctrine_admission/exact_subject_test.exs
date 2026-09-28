defmodule GgenIgniter.DoctrineAdmission.ExactSubjectTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.ExactSubject

  test "exact-subject admission is bound to canonical marketplace doctrine" do
    assert {:ok, admitted} =
             ExactSubject.admit(%{
               "subject" => "doctrine:exact_subject",
               "source_repository" => "seanchatmangpt/ggen-marketplace",
               "source_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"
             })

    assert admitted["authority"] == "NONE"
    assert admitted["ceiling"] == "CONSTRUCT"

    assert {:error, {:refused_doctrine, :source_identity, :invalid_exact_subject}} =
             ExactSubject.admit(%{})
  end
end
