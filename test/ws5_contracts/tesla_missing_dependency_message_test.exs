defmodule GgenIgniter.WS5.TeslaMissingDependencyMessageTest do
  use ExUnit.Case, async: true

  test "missing Tesla refusal tells consumers how to repair the dependency" do
    source = File.read!("lib/ggen_igniter/pack.ex")
    assert source =~ ~s(add {:tesla, \"~> 1.8\"} to your own mix.exs deps)
  end
end
