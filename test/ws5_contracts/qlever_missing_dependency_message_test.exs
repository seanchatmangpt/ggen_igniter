defmodule GgenIgniter.WS5.QleverMissingDependencyMessageTest do
  use ExUnit.Case, async: true

  test "missing GNO refusal tells consumers how to enable QLever" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ ~s(add {:gno, \"~> 0.1\"} to your own mix.exs deps)
  end
end
