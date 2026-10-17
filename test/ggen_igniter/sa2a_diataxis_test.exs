defmodule GgenIgniter.SA2ADiataxisTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SA2ADiataxis

  @manifest %{
    "schema" => "sa2a-diataxis/v1",
    "repository" => "seanchatmangpt/example",
    "role" => "runtime",
    "authority" => ["engineering-standards/semantic/sa2a-diataxis"],
    "generator" => "ggen-marketplace/packs/sa2a-diataxis-pack",
    "capabilities" => ["observe", "construct"]
  }

  test "projects only machine navigation artifacts" do
    assert {:ok, files} = SA2ADiataxis.project(@manifest)
    assert Map.keys(files) |> Enum.sort() ==
             [".sa2a/bootstrap", ".sa2a/diataxis.ttl", ".sa2a/manifest.json"]

    refute Enum.any?(Map.keys(files), &String.ends_with?(&1, ".md"))
    assert files[".sa2a/diataxis.ttl"] =~ "urn:sa2a:capability:observe"
    assert files[".sa2a/diataxis.ttl"] =~ "urn:sa2a:capability:construct"
  end

  test "refuses unknown role instead of inventing semantics" do
    assert {:error, {:unsupported_role, "mystery"}} =
             SA2ADiataxis.validate_manifest(%{@manifest | "role" => "mystery"})
  end

  test "refuses empty capability set" do
    assert {:error, :capabilities_required} =
             SA2ADiataxis.validate_manifest(%{@manifest | "capabilities" => []})
  end
end
