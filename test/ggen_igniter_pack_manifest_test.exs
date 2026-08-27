defmodule GgenIgniter.PackManifestTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.PackManifest.PackDependency
  alias GgenIgniter.PackRef

  describe "PackDependency.from_map/1" do
    test "reads pack_id (not name) from a real string-keyed map" do
      dep = PackDependency.from_map(%{"pack_id" => "rust-cli-core", "version" => "1.2.3"})

      assert dep.pack_id == "rust-cli-core"
      assert dep.version == "1.2.3"
    end

    test "defaults optional to false when absent" do
      dep = PackDependency.from_map(%{"pack_id" => "rust-cli-core", "version" => "1.2.3"})

      assert dep.optional == false
    end

    test "reads a present optional field instead of defaulting" do
      dep =
        PackDependency.from_map(%{
          "pack_id" => "rust-cli-core",
          "version" => "1.2.3",
          "optional" => true
        })

      assert dep.optional == true
    end
  end

  describe "PackRef default registry" do
    test ~s(defaults to "local", not "default", when constructed without an explicit registry) do
      ref = %PackRef{name: "rust-cli-core", version: "1.2.3"}

      assert ref.registry == "local"
      refute ref.registry == "default"
    end
  end
end
