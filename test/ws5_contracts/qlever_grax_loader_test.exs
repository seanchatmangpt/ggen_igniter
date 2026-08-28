defmodule GgenIgniter.WS5.QleverGraxLoaderTest do
  use ExUnit.Case, async: true

  test "QLever store descriptions continue to load through Grax" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ "case Grax.load(graph, RDF.iri(store_id), Qlever) do"
  end
end
