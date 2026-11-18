defmodule GgenIgniter.OntologyAggregateTest do
  @moduledoc """
  Chicago-style: real files under ExUnit's `:tmp_dir`, real `Toml` decoding through
  `SchemaDispatch.load_raw/1`, assertions on final file bytes/mtimes and returned values.
  No doubles. Mtime non-writes are proven by back-dating a file and asserting the
  back-dated mtime survives the call.
  """
  use ExUnit.Case, async: true
  @moduletag :tmp_dir

  doctest GgenIgniter.ProjectConfig.OntologyAggregate

  alias GgenIgniter.{OntologyAggregate, Refusals, SchemaDispatch}
  alias GgenIgniter.ProjectConfig.OntologyAggregate, as: Agg

  @marker ".ggen-v2/aggregate-freshness"
  @old {{2020, 1, 1}, {0, 0, 0}}

  defp agg(overrides \\ []) do
    struct!(
      %Agg{output: "corpus.ttl", constituents: ["b.ttl", "a.ttl"], auto_regen: false},
      overrides
    )
  end

  defp seed(dir) do
    File.write!(Path.join(dir, "a.ttl"), "# a\n")
    File.write!(Path.join(dir, "b.ttl"), "# b")
  end

  # sorted by rel path: a then b; joined by "\n"; trailing "\n" appended.
  @expected "# a\n\n# b\n"

  defp frontmatter(extra) do
    """
    [project]
    name = "demo"

    [ontology]
    source = "corpus.ttl"
    #{extra}

    [templates]
    dir = "templates"
    """
  end

  describe "parse (SchemaDispatch)" do
    test "absent => aggregate nil" do
      assert {:frontmatter, c} = SchemaDispatch.load_raw(frontmatter(""))
      assert c.ontology.aggregate == nil
    end

    test "present => struct, auto_regen defaults false" do
      raw =
        frontmatter("""
        [ontology.aggregate]
        output = "corpus.ttl"
        constituents = ["a.ttl", "b.ttl"]
        """)

      assert {:frontmatter, c} = SchemaDispatch.load_raw(raw)

      assert c.ontology.aggregate == %Agg{
               output: "corpus.ttl",
               constituents: ["a.ttl", "b.ttl"],
               auto_regen: false
             }
    end

    test "auto_regen true is carried" do
      raw =
        frontmatter("""
        [ontology.aggregate]
        output = "corpus.ttl"
        constituents = ["a.ttl"]
        auto_regen = true
        """)

      assert {:frontmatter, c} = SchemaDispatch.load_raw(raw)
      assert c.ontology.aggregate.auto_regen
    end

    test "unknown key => malformed refusal" do
      raw =
        frontmatter("""
        [ontology.aggregate]
        output = "corpus.ttl"
        constituents = ["a.ttl"]
        bogus = 1
        """)

      assert {:refused, {:malformed, diagnostic: d}} = SchemaDispatch.load_raw(raw)
      assert d =~ "bogus"
    end

    test "missing output / bad constituents / bad auto_regen => malformed refusal" do
      for body <- [
            ~s|constituents = ["a.ttl"]|,
            ~s|output = "o.ttl"\nconstituents = "a.ttl"|,
            ~s|output = "o.ttl"\nconstituents = []\nauto_regen = "yes"|
          ] do
        raw = frontmatter("[ontology.aggregate]\n" <> body)
        assert {:refused, {:malformed, diagnostic: _}} = SchemaDispatch.load_raw(raw)
      end
    end

    test "aggregate survives serialize!/parse round trip" do
      raw =
        frontmatter("""
        [ontology.aggregate]
        output = "corpus.ttl"
        constituents = ["a.ttl", "b.ttl"]
        auto_regen = true
        """)

      config = GgenIgniter.GgenToml.IO.parse_raw!(raw)

      assert GgenIgniter.GgenToml.IO.parse_raw!(GgenIgniter.GgenToml.IO.serialize!(config)) ==
               config
    end
  end

  describe "enforce/3" do
    test "nil => {:ok, nil} and writes nothing", %{tmp_dir: dir} do
      assert {:ok, nil} = OntologyAggregate.enforce(dir, nil)
      assert File.ls!(dir) == []
    end

    test "empty constituents => AGG-002", %{tmp_dir: dir} do
      assert {:error, msg} = OntologyAggregate.enforce(dir, agg(constituents: []))
      assert msg =~ "[FM-ONTOLOGY-AGG-002]"
    end

    test "unreadable constituent => AGG-003", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "a.ttl"), "# a\n")
      assert {:error, msg} = OntologyAggregate.enforce(dir, agg())
      assert msg =~ "[FM-ONTOLOGY-AGG-003]"
      assert msg =~ "b.ttl"
    end

    test "stale by default refuses and writes nothing", %{tmp_dir: dir} do
      seed(dir)
      before = File.ls!(dir)
      assert {:error, msg} = OntologyAggregate.enforce(dir, agg())
      assert msg =~ "[FM-ONTOLOGY-AGG-001]"
      assert {:ok, {:ONTOLOGY_AGGREGATE_STALE, _}} = Refusals.parse(msg)
      assert msg =~ "REFUSED:ONTOLOGY_AGGREGATE_STALE"
      assert File.ls!(dir) == before
      refute File.exists?(Path.join(dir, "corpus.ttl"))
    end

    test "auto_regen writes sorted concat + marker; second call is fresh and writes nothing",
         %{tmp_dir: dir} do
      seed(dir)
      a = agg(auto_regen: true)
      assert {:ok, %{regenerated: true}} = OntologyAggregate.enforce(dir, a)
      out = Path.join(dir, "corpus.ttl")
      marker = Path.join(dir, @marker)
      assert File.read!(out) == @expected

      assert File.read!(marker) ==
               GgenIgniter.Digest.hex(
                 IO.iodata_to_binary(["a.ttl", 0, "# a\n", 0, "b.ttl", 0, "# b", 0])
               )

      File.touch!(out, @old)
      File.touch!(marker, @old)
      assert {:ok, %{regenerated: false}} = OntologyAggregate.enforce(dir, a)
      assert File.stat!(out).mtime == @old
      assert File.stat!(marker).mtime == @old
    end

    test "a fresh aggregate passes even with auto_regen false", %{tmp_dir: dir} do
      seed(dir)
      {:ok, _} = OntologyAggregate.enforce(dir, agg(auto_regen: true))
      assert {:ok, %{regenerated: false}} = OntologyAggregate.enforce(dir, agg())
    end

    test "constituent drift is stale: refuses, or regenerates under auto_regen", %{tmp_dir: dir} do
      seed(dir)
      {:ok, _} = OntologyAggregate.enforce(dir, agg(auto_regen: true))
      File.write!(Path.join(dir, "a.ttl"), "# a changed\n")

      assert {:error, msg} = OntologyAggregate.enforce(dir, agg())
      assert msg =~ "[FM-ONTOLOGY-AGG-001]"
      assert File.read!(Path.join(dir, "corpus.ttl")) == @expected

      assert {:ok, %{regenerated: true}} = OntologyAggregate.enforce(dir, agg(auto_regen: true))
      assert File.read!(Path.join(dir, "corpus.ttl")) == "# a changed\n\n# b\n"
    end

    test "constituent order in the config does not matter", %{tmp_dir: dir} do
      seed(dir)

      {:ok, _} =
        OntologyAggregate.enforce(dir, agg(constituents: ["a.ttl", "b.ttl"], auto_regen: true))

      first = File.read!(Path.join(dir, "corpus.ttl"))
      marker = File.read!(Path.join(dir, @marker))

      assert {:ok, %{regenerated: false}} =
               OntologyAggregate.enforce(dir, agg(constituents: ["b.ttl", "a.ttl"]))

      assert first == @expected
      assert File.read!(Path.join(dir, @marker)) == marker
    end

    test "hand-edited output is stale", %{tmp_dir: dir} do
      seed(dir)
      {:ok, _} = OntologyAggregate.enforce(dir, agg(auto_regen: true))
      File.write!(Path.join(dir, "corpus.ttl"), "# hand edit\n")

      assert {:error, msg} = OntologyAggregate.enforce(dir, agg())
      assert msg =~ "[FM-ONTOLOGY-AGG-001]"
      assert File.read!(Path.join(dir, "corpus.ttl")) == "# hand edit\n"

      assert {:ok, %{regenerated: true}} = OntologyAggregate.enforce(dir, agg(auto_regen: true))
      assert File.read!(Path.join(dir, "corpus.ttl")) == @expected
    end

    test "dry_run with auto_regen writes nothing", %{tmp_dir: dir} do
      seed(dir)
      before = File.ls!(dir)

      assert {:ok, %{regenerated: false}} =
               OntologyAggregate.enforce(dir, agg(auto_regen: true), dry_run: true)

      assert File.ls!(dir) == before
    end

    test "dry_run without auto_regen still refuses", %{tmp_dir: dir} do
      seed(dir)
      assert {:error, msg} = OntologyAggregate.enforce(dir, agg(), dry_run: true)
      assert msg =~ "[FM-ONTOLOGY-AGG-001]"
    end

    test "write failure => AGG-004", %{tmp_dir: dir} do
      seed(dir)
      # output's parent path is a regular file, so mkdir_p/write must fail.
      File.write!(Path.join(dir, "blocker"), "x")

      assert {:error, msg} =
               OntologyAggregate.enforce(dir, agg(output: "blocker/corpus.ttl", auto_regen: true))

      assert msg =~ "[FM-ONTOLOGY-AGG-004]"
    end
  end
end
