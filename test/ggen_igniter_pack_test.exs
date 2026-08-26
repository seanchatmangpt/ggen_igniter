defmodule GgenIgniter.PackTest do
  @moduledoc """
  Chicago-style tests for `GgenIgniter.Pack` against real files on disk
  (`test/fixtures/sample-pack/` and `test/fixtures/broken-pack/`) -- no mocked
  `File`/`Path` calls.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Pack

  @sample_pack_dir "test/fixtures/sample-pack"
  @broken_pack_dir "test/fixtures/broken-pack"

  describe "resolve_dir!/1" do
    test "uses --pack-dir directly when given" do
      assert Pack.resolve_dir!(pack_dir: @sample_pack_dir) == @sample_pack_dir
    end

    test "resolves --pack NAME under priv/ggen/<name>" do
      assert Pack.resolve_dir!(pack: "audit-trail-pack") == Path.join(["priv", "ggen", "audit-trail-pack"])
    end

    test "--pack-dir wins over --pack when both given" do
      assert Pack.resolve_dir!(pack: "audit-trail-pack", pack_dir: @sample_pack_dir) == @sample_pack_dir
    end

    test "raises when neither --pack nor --pack-dir is given" do
      assert_raise ArgumentError, ~r/--pack NAME or --pack-dir DIR/, fn ->
        Pack.resolve_dir!([])
      end
    end
  end

  describe "default_ontology/1" do
    test "points at <pack_dir>/ontology.ttl" do
      assert Pack.default_ontology(@sample_pack_dir) == Path.join(@sample_pack_dir, "ontology.ttl")
    end
  end

  describe "discover_queries/1" do
    test "finds every gates/*.rq file in the real sample pack, sorted, digit-prefix stripped" do
      queries = Pack.discover_queries(@sample_pack_dir)

      assert {"spec", Path.join([@sample_pack_dir, "gates", "010_spec.rq"])} in queries
      assert {"sections", Path.join([@sample_pack_dir, "gates", "020_sections.rq"])} in queries
      assert {"entities", Path.join([@sample_pack_dir, "gates", "030_entities.rq"])} in queries
      assert {"fields", Path.join([@sample_pack_dir, "gates", "040_fields.rq"])} in queries
      assert length(queries) == 4

      # Lexical sort of the real filenames == numeric-prefix order here.
      assert Enum.map(queries, fn {name, _path} -> name end) == ["spec", "sections", "entities", "fields"]
    end

    test "returns an empty list when no gates/ dir or *.rq files exist" do
      tmp_dir = Path.join(System.tmp_dir!(), "ggen_igniter_pack_test_empty_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      assert Pack.discover_queries(tmp_dir) == []
    end

    test "discovers even a syntactically invalid gate query file (parse-validity is checked elsewhere)" do
      assert Pack.discover_queries("test/fixtures/broken-pack") ==
               [{"bad", Path.join(["test", "fixtures", "broken-pack", "gates", "010_bad.rq"])}]
    end

    test "strips only a leading digit-prefix, leaving an unprefixed name unchanged" do
      # entities.rq (no prefix) in the flat, unpacked fixtures dir has a query
      # named 1:1 with its filename already -- verify the stem, unprefixed, is
      # preserved verbatim when there is no leading NNN_ to strip.
      tmp_dir = Path.join(System.tmp_dir!(), "ggen_igniter_pack_test_#{System.unique_integer([:positive])}")
      gates_dir = Path.join(tmp_dir, "gates")
      File.mkdir_p!(gates_dir)
      File.write!(Path.join(gates_dir, "entities.rq"), "SELECT * WHERE { ?s ?p ?o }")

      assert Pack.discover_queries(tmp_dir) == [{"entities", Path.join(gates_dir, "entities.rq")}]
    end
  end

  describe "discover_template/1" do
    test "returns {:ok, path} when exactly one *.eex file exists" do
      assert Pack.discover_template(@sample_pack_dir) ==
               {:ok, Path.join([@sample_pack_dir, "templates", "extension.ex.eex"])}
    end

    test "returns {:error, :none} when templates/ has no matching files" do
      assert Pack.discover_template(@broken_pack_dir) == {:error, :none}
    end

    test "returns {:error, {:ambiguous, paths}} when more than one template exists" do
      tmp_dir = Path.join(System.tmp_dir!(), "ggen_igniter_pack_test_#{System.unique_integer([:positive])}")
      templates_dir = Path.join(tmp_dir, "templates")
      File.mkdir_p!(templates_dir)
      File.write!(Path.join(templates_dir, "a.eex"), "a")
      File.write!(Path.join(templates_dir, "b.eex"), "b")

      assert {:error, {:ambiguous, paths}} = Pack.discover_template(tmp_dir)
      assert length(paths) == 2
    end
  end
end
