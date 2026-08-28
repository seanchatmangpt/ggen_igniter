defmodule GgenIgniter.WS5.RdfEngineContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "ontology ingestion remains on RDF 3" do
    assert @mix =~ ~s({:rdf, "~> 3.0"})
  end
end
