defmodule GgenIgniter.WS5.QleverLiteralNormalizationTest do
  use ExUnit.Case, async: true

  test "QLever RDF literals normalize to bare values" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ "defp unwrap(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)"
  end
end
