defmodule GgenIgniter.WS5.QleverSparqlClientExecutionTest do
  use ExUnit.Case, async: true

  test "QLever query execution remains delegated to SPARQL.Client" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ "case SPARQL.Client.query(query_string, endpoint) do"
  end
end
