defmodule GgenIgniter.OntologyImportsTest do
  @moduledoc """
  Chicago-style: real fixture `.ttl` files under `test/fixtures/schema_dispatch/imports/`,
  real `RDF.Turtle` parsing, real `SchemaDispatch`/`GgenToml.IO` round trips over TOML text.
  No doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, SchemaDispatch}
  alias GgenIgniter.GgenToml.IO, as: TomlIO

  @dir Path.expand("fixtures/schema_dispatch/imports", __DIR__)

  @frontmatter """
  [project]
  name = "demo"

  [ontology]
  source = "main.ttl"
  imports = ["extra.ttl", "more.ttl"]

  [templates]
  dir = "templates"
  """

  @declarative """
  [project]
  name = "demo"
  version = "0.1.0"

  [ontology]
  source = "main.ttl"
  imports = ["extra.ttl"]

  [[generation.rules]]
  name = "r"
  query = { inline = "SELECT * WHERE { ?s ?p ?o }" }
  template = { inline = "x" }
  output_file = "out.txt"
  """

  describe "imports carried through SchemaDispatch" do
    test "frontmatter schema keeps imports; absent => []" do
      assert {:frontmatter, config} = SchemaDispatch.load_raw(@frontmatter)
      assert config.ontology.imports == ["extra.ttl", "more.ttl"]
      assert config.ontology.aggregate == nil

      bare = String.replace(@frontmatter, ~s|imports = ["extra.ttl", "more.ttl"]\n|, "")
      assert {:frontmatter, config} = SchemaDispatch.load_raw(bare)
      assert config.ontology.imports == []
    end

    test "declarative schema keeps imports" do
      assert {:declarative_rules, config} = SchemaDispatch.load_raw(@declarative)
      assert config.ontology.imports == ["extra.ttl"]
    end
  end

  describe "serialize!/1 round trip" do
    test "frontmatter imports survive serialize!(parse_raw!(x))" do
      config = TomlIO.parse_raw!(@frontmatter)
      assert TomlIO.parse_raw!(TomlIO.serialize!(config)) == config
      assert TomlIO.serialize!(config) =~ ~s|"extra.ttl"|
    end

    test "declarative imports survive the round trip" do
      config = TomlIO.parse_raw!(@declarative)
      assert TomlIO.parse_raw!(TomlIO.serialize!(config)).ontology.imports == ["extra.ttl"]
    end
  end

  describe "Ontology.load_with_imports!/3" do
    test "merges the source and imported triples" do
      graph = Ontology.load_with_imports!("main.ttl", ["extra.ttl"], @dir)
      assert RDF.Graph.triple_count(graph) == 2

      subjects = graph |> RDF.Graph.subjects() |> Enum.map(&to_string/1) |> Enum.sort()

      assert subjects == [
               "https://ggen-igniter.dev/fixture/imports#Extra",
               "https://ggen-igniter.dev/fixture/imports#Main"
             ]
    end

    test "no imports yields just the source graph" do
      assert Ontology.load_with_imports!(Path.join(@dir, "main.ttl"), [])
             |> RDF.Graph.triple_count() ==
               1
    end

    test "a missing import raises naming the path" do
      err =
        assert_raise ArgumentError, fn ->
          Ontology.load_with_imports!("main.ttl", ["nope.ttl"], @dir)
        end

      assert err.message =~ Path.join(@dir, "nope.ttl")
    end

    test "a Dataset import raises" do
      dir = Path.join(System.tmp_dir!(), "imports_ds_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      File.write!(
        Path.join(dir, "q.nq"),
        "<http://e/s> <http://e/p> <http://e/o> <http://e/g> .\n"
      )

      assert_raise ArgumentError, ~r/Dataset/, fn ->
        Ontology.load_with_imports!("main.ttl", [Path.join(dir, "q.nq")], @dir)
      end
    end
  end
end
