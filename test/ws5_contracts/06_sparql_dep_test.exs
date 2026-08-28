defmodule GgenIgniter.WS5.SPARQLDependencyTest do
  use ExUnit.Case, async: true

  test "SPARQL remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:sparql, "~> 0.3"})
  end
end
