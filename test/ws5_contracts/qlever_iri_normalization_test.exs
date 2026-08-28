defmodule GgenIgniter.WS5.QleverIRINormalizationTest do
  use ExUnit.Case, async: true

  test "QLever RDF IRIs normalize to strings" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ "defp unwrap(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)"
  end
end
