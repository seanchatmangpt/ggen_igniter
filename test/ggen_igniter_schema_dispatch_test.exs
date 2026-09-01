defmodule GgenIgniterSchemaDispatchTest do
  @moduledoc """
  Chicago-style: every test here reads a real fixture `ggen.toml` file off
  disk via `Toml.decode/1` (the real collaborator) through
  `GgenIgniter.SchemaDispatch.load_raw/1`, and asserts on the real returned
  classification/struct -- no `Mock`/`mock(`/`patch(`/`monkeypatch` of any
  kind. Fixtures live under `test/fixtures/schema_dispatch/`.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SchemaDispatch
  alias GgenIgniter.{ProjectConfig, PackRef, FrontmatterConfig}

  @fixtures_dir Path.join([__DIR__, "fixtures", "schema_dispatch"])

  defp read_fixture!(name) do
    File.read!(Path.join(@fixtures_dir, name))
  end

  describe "beam4pm's real ggen.toml (frontmatter schema)" do
    test "classifies as :frontmatter with all 5 real pack entries and correct paths" do
      raw = read_fixture!("beam4pm_ggen.toml")

      assert {:frontmatter, %FrontmatterConfig{} = config} = SchemaDispatch.load_raw(raw)

      assert config.project.name == "beam4pm"
      assert config.ontology.source == "ontology.ttl"
      assert config.templates.dir == "templates"

      assert Map.keys(config.packs) |> Enum.sort() == [
               "beam4pm-ai-contracts",
               "beam4pm-pro-entitlement",
               "beam4pm-pro-infra",
               "beam4pm-process-model",
               "github-actions-pack"
             ]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-process-model-pack"}} =
               config.packs["beam4pm-process-model"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-pro-infra-pack"}} =
               config.packs["beam4pm-pro-infra"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/github-actions-pack"}} =
               config.packs["github-actions-pack"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-ai-contracts-pack"}} =
               config.packs["beam4pm-ai-contracts"]

      assert {:path, %{path: "vendor/ggen-marketplace/packs/beam4pm-pro-entitlement-pack"}} =
               config.packs["beam4pm-pro-entitlement"]
    end

    test "GgenIgniter.SchemaDispatch.load/1 reads the same fixture from an explicit project_dir argument" do
      tmp = Path.join(System.tmp_dir!(), "schema_dispatch_load_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      File.write!(Path.join(tmp, "ggen.toml"), read_fixture!("beam4pm_ggen.toml"))
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:frontmatter, %FrontmatterConfig{} = config} = SchemaDispatch.load(tmp)
      assert config.project.name == "beam4pm"
    end
  end

  describe "a DeclarativeRules-shaped fixture" do
    test "classifies as :declarative_rules with flat PackRef entries" do
      raw = read_fixture!("declarative_rules.toml")

      assert {:declarative_rules, %ProjectConfig{} = config} = SchemaDispatch.load_raw(raw)

      assert config.project.name == "fixture-project"
      assert config.project.version == "1.0.0"
      assert config.ontology.source == "ontology.ttl"

      assert [
               %PackRef{
                 name: "rust-cli-core",
                 registry: "local",
                 path: "vendor/ggen-marketplace/packs/rust-cli-core",
                 version: "1.2.3"
               },
               %PackRef{
                 name: "github-actions-pack",
                 registry: "default",
                 path: nil,
                 version: "0.4.0"
               }
             ] = config.packs
    end
  end

  describe "a genuinely ambiguous fixture" do
    test "returns a typed :ambiguous refusal, never a crash or a silent wrong-schema guess" do
      raw = read_fixture!("ambiguous.toml")

      assert {:refused, {:ambiguous, matched: matched}} = SchemaDispatch.load_raw(raw)
      assert "declarative:project_version_present" in matched
      assert "frontmatter:satisfies_minimum_shape" in matched
    end
  end

  describe "malformed TOML" do
    test "returns a typed :malformed refusal, not an exception" do
      assert {:refused, {:malformed, diagnostic: diagnostic}} =
               SchemaDispatch.load_raw("not [ valid toml")

      assert is_binary(diagnostic)
    end
  end

  describe "unsupported document (matches neither schema)" do
    test "returns a typed :unsupported refusal naming the observed top-level tables" do
      raw = "[some_other_tool]\nkey = \"value\"\n"

      assert {:refused, {:unsupported, observed_markers: observed}} = SchemaDispatch.load_raw(raw)
      assert "unknown_top_level_table:some_other_tool" in observed
    end
  end

  describe "FrontmatterPackRef :git variant (beam4pm's real ggen.toml has no Git-shaped entries)" do
    test "a synthetic {git = ..., version = ...} pack entry decodes to the :git tagged tuple" do
      raw = """
      [project]
      name = "x"

      [ontology]
      source = "o.ttl"

      [templates]
      dir = "t"

      [packs.remote-pack]
      git = "https://example.org/remote-pack.git"
      version = "2.0.0"
      """

      assert {:frontmatter, %FrontmatterConfig{} = config} = SchemaDispatch.load_raw(raw)

      assert {:git, %{git: "https://example.org/remote-pack.git", version: "2.0.0"}} =
               config.packs["remote-pack"]
    end
  end

  describe "classify_table/1 pure classifier" do
    test "a document with law.shapes present classifies as :frontmatter" do
      {:ok, table} =
        Toml.decode("""
        [project]
        name = "x"

        [ontology]
        source = "o.ttl"

        [templates]
        dir = "t"

        [law]
        shapes = ["shapes.ttl"]
        """)

      assert SchemaDispatch.classify_table(table) == :frontmatter
    end

    test "load/1 falls through to a typed refusal for a missing ggen.toml" do
      tmp = Path.join(System.tmp_dir!(), "schema_dispatch_missing_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:refused, {:malformed, diagnostic: diagnostic}} = SchemaDispatch.load(tmp)
      assert is_binary(diagnostic)
    end
  end
end
