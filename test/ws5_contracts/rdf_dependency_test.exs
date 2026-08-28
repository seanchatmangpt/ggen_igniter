defmodule GgenIgniter.WS5.RDFDependencyTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "RDF dependency remains ~> 3.0" do
    assert @manifest =~ ~s({:rdf, "~> 3.0"})
  end
end
