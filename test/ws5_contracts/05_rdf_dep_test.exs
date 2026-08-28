defmodule GgenIgniter.WS5.RDFDependencyTest do
  use ExUnit.Case, async: true

  test "RDF remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:rdf, "~> 3.0"})
  end
end
