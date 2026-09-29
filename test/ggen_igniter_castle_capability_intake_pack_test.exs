defmodule GgenIgniter.CastleCapabilityIntakePackTest do
  use ExUnit.Case, async: true

  test "normal pack loader resolves CASTLE intake pack and its exact donors" do
    root = GgenIgniter.Pack.resolve_dir!(pack: "castle-capability-intake-pack")
    ontology_path = GgenIgniter.Pack.default_ontology(root)
    gate_path = Path.join(root, "gates/010_projection.rq")
    template_path = Path.join(root, "templates/capability-intake.md.eex")

    assert File.dir?(root)
    assert File.regular?(ontology_path)
    assert File.regular?(gate_path)
    assert File.regular?(template_path)

    ontology = File.read!(ontology_path)
    pack = File.read!(Path.join(root, "pack.toml"))
    gate = File.read!(gate_path)
    template = File.read!(template_path)

    # Real Turtle parsing proves the pack's ontology is loadable by the same
    # path the sync task uses before query/render.
    graph = GgenIgniter.Ontology.load!(ontology_path)
    assert graph != nil

    assert pack =~ ~s(name = "castle-capability-intake-pack")
    assert ontology =~ "50fdfa20c84205a80c6eb94e916cffbedc4b816e"
    assert ontology =~ "seanchatmangpt/ggen"
    assert ontology =~ "ff96f04e8c7b851e5cca53f3faf5ce1d5f43ce6e"
    assert ontology =~ "seanchatmangpt/ostar"
    assert ontology =~ "a392e009400c83d5e175b508c4e3008e189945d3"
    assert ontology =~ ~s(eco:projectionStanding "CANDIDATE")
    assert ontology =~ ~s(eco:authorityCeiling "CONSTRUCT")
    refute ontology =~ ~s(eco:authorityCeiling "DO")
    assert gate =~ "ORDER BY ?repository"
    assert template =~ "does not grant DO authority"
  end
end
