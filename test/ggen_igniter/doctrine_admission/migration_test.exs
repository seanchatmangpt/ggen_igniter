defmodule GgenIgniter.DoctrineAdmission.MigrationTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Migration

  test "migration preserves exact subject and bounds authority" do
    legacy = %{"subject" => "strategy-11", "source_sha" => String.duplicate("e", 40)}
    assert {:ok, migrated} = Migration.to_v1(legacy)
    assert migrated["subject"] == legacy["subject"]
    assert migrated["source_sha"] == legacy["source_sha"]
    assert migrated["authority_requirement"] == "NONE"
    assert migrated["standing"] == "UNKNOWN"
  end

  test "migration fails closed without a source SHA" do
    assert {:error, {:refused_doctrine, :migration, :missing_exact_subject}} =
             Migration.to_v1(%{"subject" => "strategy-11"})
  end
end
