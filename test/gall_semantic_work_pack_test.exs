defmodule GgenIgniter.GallSemanticWorkPackTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{Engine, Ontology, Render}

  @pack Path.expand("../priv/ggen/gall-semantic-work-pack", __DIR__)

  test "pack queries a semantic checkpoint and deterministically renders execution and human projections" do
    graph = Ontology.load!(Path.join(@pack, "ontology.ttl"))
    query = File.read!(Path.join(@pack, "gates/010_checkpoints.rq"))

    [row] = Engine.Sparql.run(graph, query)

    bindings =
      row
      |> Map.new(fn {key, value} -> {String.to_atom(to_string(key)), to_string(value)} end)

    descriptor =
      @pack
      |> Path.join("templates/descriptor.json.eex")
      |> File.read!()
      |> Render.render(bindings)
      |> Jason.decode!()

    ticket =
      @pack
      |> Path.join("templates/ticket.md.eex")
      |> File.read!()
      |> Render.render(bindings)

    assert descriptor["checkpoint_iri"] == "urn:gall:checkpoint:example:001"
    assert descriptor["base_sha"] == String.duplicate("b", 40)
    assert descriptor["graph_digest"] == "sha256:" <> String.duplicate("a", 64)
    assert descriptor["dependencies"] == []
    assert ticket =~ "Edit the ontology, not this projection"
    assert ticket =~ descriptor["checkpoint_iri"]
  end
end
