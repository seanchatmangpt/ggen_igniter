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

    assert descriptor["work_order_iri"] == "urn:gall:work-order:example:001"
    assert descriptor["checkpoint_iri"] == "urn:gall:checkpoint:example:001"
    refute descriptor["work_order_iri"] == descriptor["checkpoint_iri"]

    assert descriptor["repository_identity"] == "seanchatmangpt/ggen_igniter"
    assert descriptor["execution_repo_alias"] == "ggen_igniter"
    assert descriptor["base_sha"] == String.duplicate("b", 40)
    assert descriptor["base_sha"] =~ ~r/^[0-9a-f]{40}$/
    assert descriptor["graph_digest"] == "sha256:" <> String.duplicate("a", 64)
    assert descriptor["graph_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert descriptor["provider"] == "zcode"
    assert descriptor["verifier_suite"] == "example-dod"
    assert descriptor["execution_policy"] == "continuous_epoch_run"
    assert descriptor["dependencies"] == []

    expected_keys =
      ~w(base_sha checkpoint_iri dependencies execution_policy execution_repo_alias goal graph_digest provider repository_identity verifier_suite work_order_iri)

    assert Map.keys(descriptor) |> Enum.sort() == Enum.sort(expected_keys)

    for forbidden <- ~w(lease lease_token epoch epoch_id worker worker_id receipt receipt_iri receipt_digest authority standing) do
      refute Map.has_key?(descriptor, forbidden)
    end

    assert ticket =~ "Edit the ontology, not this projection"
    assert ticket =~ descriptor["checkpoint_iri"]
    assert ticket =~ descriptor["work_order_iri"]
    assert ticket =~ descriptor["repository_identity"]
  end
end
