defmodule GgenIgniter.SemanticJiraPublicAlignmentFalsifierTest do
  @moduledoc """
  Chicago-style falsifiers against the ADR-011 enforcement claim (gate
  `047_public_vocab_alignment.rq` plus `PackHealth`): the real Turtle loader,
  both real query engines (`oxigraph` NIF, pure-Elixir `sparql`), real files
  on disk, real copies of the shipped pack. No test doubles.

  Each test builds one concrete input that a correct enforcement must reject
  and asserts on the real returned rows / health verdict. They were written by
  the qualifier (`test(falsifier)`), not the builder, and each was observed to
  FAIL on head `fd700f5` before being committed: they document holes in the
  enforcement, not in the shipped 67-term partition (which holds).

  async: false because the real pack copies and mutated ontologies are written
  under unique scratch dirs but the engines share a process-wide NIF.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.{Engine, Ontology}
  alias GgenIgniter.SemanticJira.PackHealth

  @moduletag :integration

  @pack_dir "priv/ggen/semantic-jira-pack"
  @ontology_path Path.join(@pack_dir, "ontology.ttl")
  @gate_path Path.join(@pack_dir, "gates/047_public_vocab_alignment.rq")
  @gate_file "gates/047_public_vocab_alignment.rq"

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @engines ~w(oxigraph sparql)

  @alignment_block ~r/# BEGIN sj-public-alignment \(ADR-011\).*?# END sj-public-alignment \(ADR-011\)\n/s

  @prefixes """
  @prefix sj: <#{@sj}> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
  @prefix owl: <http://www.w3.org/2002/07/owl#> .
  @prefix prov: <http://www.w3.org/ns/prov#> .
  """

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sj_alignment_falsifier_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp gate_rows(engine_name, path) do
    engine = Engine.fetch!(engine_name)
    context = engine.prepare!(Ontology.load!(path), [])
    engine.run(context, File.read!(@gate_path))
  end

  defp mutated_ontology!(dir, name, extra) do
    path = Path.join(dir, name)
    File.write!(path, File.read!(@ontology_path) <> "\n" <> @prefixes <> extra <> "\n")
    path
  end

  defp pack_copy!(tag) do
    root = scratch_dir!("pack_" <> tag)
    dest = Path.join(root, "semantic-jira-pack")
    File.cp_r!(@pack_dir, dest)
    dest
  end

  describe "gate 047 accepts stub residue reasons and non-IRI 'alignments'" do
    for engine <- @engines do
      test "a whitespace-only sj:residueReason is not a reason (#{engine} engine)" do
        dir = scratch_dir!("ws_reason")

        path =
          mutated_ontology!(
            dir,
            "ws_reason.ttl",
            ~s(sj:WhitespaceReasonProbe a rdfs:Class ; sj:residueReason "   " .)
          )

        assert gate_rows(unquote(engine), path) == [%{"term" => @sj <> "WhitespaceReasonProbe"}],
               "a blank residue reason must be a violation exactly like the empty string"
      end

      test "a string literal naming a public IRI is not an alignment (#{engine} engine)" do
        dir = scratch_dir!("literal_target")

        path =
          mutated_ontology!(
            dir,
            "literal_target.ttl",
            ~s(sj:LiteralTargetProbe a rdfs:Class ; rdfs:subClassOf "http://www.w3.org/ns/prov#Entity" .)
          )

        assert gate_rows(unquote(engine), path) == [%{"term" => @sj <> "LiteralTargetProbe"}],
               "a literal is not a public term; the anti-join must require an IRI target"
      end

      test "an owl:Class-declared sj: term is inside the gate's term universe (#{engine} engine)" do
        dir = scratch_dir!("owl_class")

        path = mutated_ontology!(dir, "owl_class.ttl", "sj:OwlClassProbe a owl:Class .")

        assert gate_rows(unquote(engine), path) == [%{"term" => @sj <> "OwlClassProbe"}],
               "retyping an sj: class as owl:Class must not exempt it from the alignment partition"
      end
    end
  end

  describe "PackHealth's alignment enforcement is name-coupled and fails open when the gate is absent" do
    test "deleting gate 047 together with the alignment block does not read as healthy" do
      pack_dir = pack_copy!("gate_deleted")
      ontology = Path.join(pack_dir, "ontology.ttl")

      File.rm!(Path.join(pack_dir, @gate_file))
      File.write!(ontology, Regex.replace(@alignment_block, File.read!(ontology), ""))

      assert {:error, detail} = PackHealth.check(pack_dir)
      assert detail =~ "public_vocab_alignment"
    end

    test "renaming gate 047 lets an unaligned sj: term through as a 'clean' gate" do
      pack_dir = pack_copy!("gate_renamed")
      ontology = Path.join(pack_dir, "ontology.ttl")

      File.rename!(
        Path.join(pack_dir, @gate_file),
        Path.join(pack_dir, "gates/048_vocab_audit.rq")
      )

      File.write!(
        ontology,
        File.read!(ontology) <>
          "\n<#{@sj}RenamedGateProbe> a <http://www.w3.org/2000/01/rdf-schema#Class> .\n"
      )

      assert {:error, detail} = PackHealth.check(pack_dir)
      assert detail =~ "RenamedGateProbe" or detail =~ "public_vocab_alignment"
    end
  end
end
