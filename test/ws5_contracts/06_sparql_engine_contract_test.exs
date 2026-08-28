defmodule GgenIgniter.WS5.SparqlEngineContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "SPARQL query path remains on the admitted 0.3 line" do
    assert @mix =~ ~s({:sparql, "~> 0.3"})
  end
end
