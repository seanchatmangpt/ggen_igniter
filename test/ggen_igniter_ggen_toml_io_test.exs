defmodule GgenIgniter.GgenTomlIOTest do
  use ExUnit.Case, async: true

  # Chicago-school only: real File.read!/File.write! against real temp
  # files, real Toml.decode/1 (via GgenIgniter.SchemaDispatch) against
  # beam4pm's actual ggen.toml content. No Mock/mock(/patch(/monkeypatch
  # anywhere in this file.

  alias GgenIgniter.GgenToml.IO, as: GgenTomlIO
  alias GgenIgniter.FrontmatterConfig

  @fixture Path.join([__DIR__, "fixtures", "ggen_toml_io", "beam4pm_ggen.toml"])

  describe "parse!/1 (story a)" do
    test "classifies and parses beam4pm's real ggen.toml into the Frontmatter-shaped struct" do
      dir = tmp_dir_with_fixture!()

      result = GgenTomlIO.parse!(dir)

      assert %FrontmatterConfig{} = result

      assert result.project.name == "beam4pm"
      assert result.ontology.source == "ontology.ttl"
      assert result.templates.dir == "templates"

      assert map_size(result.packs) == 5
      assert %{"beam4pm-process-model" => process_model_ref} = result.packs

      assert process_model_ref ==
               {:path,
                %{
                  path: "vendor/ggen-marketplace/packs/beam4pm-process-model-pack",
                  extra_ontologies: [],
                  lock: nil
                }}

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack"}} =
               result.packs["beam4pm-pro-infra"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/github-actions-pack"}} =
               result.packs["github-actions-pack"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack"}} =
               result.packs["beam4pm-ai-contracts"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack"}} =
               result.packs["beam4pm-pro-entitlement"]
    end

    test "raises GgenIgniter.GgenToml.IO.Error when the file cannot be read" do
      assert_raise GgenTomlIO.Error, ~r/ggen.toml refused/, fn ->
        GgenTomlIO.parse!(
          System.tmp_dir!() <> "/does-not-exist-#{System.unique_integer([:positive])}"
        )
      end
    end
  end

  describe "serialize!/1 idempotency and byte-for-byte round-trip (story b + c)" do
    test "read-then-write-unchanged: parse!, serialize!, re-parse produces an equal struct" do
      dir = tmp_dir_with_fixture!()

      parsed = GgenTomlIO.parse!(dir)
      serialized = GgenTomlIO.serialize!(parsed)

      roundtrip_dir = tmp_project_dir!()
      File.write!(Path.join(roundtrip_dir, "ggen.toml"), serialized)

      reparsed = GgenTomlIO.parse!(roundtrip_dir)

      assert reparsed == parsed
    end

    test "byte-for-byte diff against the original file: comment block and disclosed limitation" do
      dir = tmp_dir_with_fixture!()
      original_path = Path.join(dir, "ggen.toml")
      content_before = File.read!(original_path)

      parsed = GgenTomlIO.parse!(dir)
      serialized = GgenTomlIO.serialize!(parsed)

      roundtrip_path = Path.join(tmp_project_dir!(), "ggen.toml")
      File.write!(roundtrip_path, serialized)
      content_after = File.read!(roundtrip_path)

      # The comment/decline-rationale block is real content the typed
      # struct has no field for -- confirmed present before, confirmed
      # absent after, per this ticket's story (c) accepted-limitation
      # disclosure (see GgenIgniter.GgenToml.IO's moduledoc).
      assert content_before =~ "gh-terraform-pack: investigated 2026-08-30"
      refute content_after =~ "gh-terraform-pack: investigated 2026-08-30"

      # Not byte-for-byte identical (the comment loss above is sufficient
      # proof), but semantically equal: the round-trip is NOT silently
      # lossy on the substantive data -- every pack entry and its path
      # survives, confirmed by re-parsing (previous test) rather than by
      # eyeballing this raw text.
      refute content_before == content_after
      assert content_after =~ "beam4pm-process-model"
      assert content_after =~ "vendor/ggen-marketplace/packs/beam4pm-process-model-pack"
    end
  end

  # -- helpers --------------------------------------------------------------

  defp tmp_project_dir! do
    dir =
      Path.join(System.tmp_dir!(), "ggen_toml_io_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp tmp_dir_with_fixture! do
    dir = tmp_project_dir!()
    File.cp!(@fixture, Path.join(dir, "ggen.toml"))
    dir
  end
end
