defmodule GgenIgniter.WS5.SPARQLDependencyTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "SPARQL dependency remains ~> 0.3" do
    assert @manifest =~ ~s({:sparql, "~> 0.3"})
  end
end
