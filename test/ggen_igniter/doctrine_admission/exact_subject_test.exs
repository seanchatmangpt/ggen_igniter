defmodule GgenIgniter.DoctrineAdmission.ExactSubjectTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.ExactSubject
  @sha "009807a9226e001acbb5c686ea1dd002d0d1ef72"
  test "exact-subject admission and refusal" do
    assert {:ok,a}=ExactSubject.admit(%{"subject"=>"doctrine:exact_subject","source_sha"=>@sha})
    assert a["authority"]=="NONE" and a["ceiling"]=="CONSTRUCT"
    assert {:error,{:refused_doctrine,:exact_subject,:invalid_exact_subject}}=ExactSubject.admit(%{})
  end
end
