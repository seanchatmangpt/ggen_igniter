defmodule GgenIgniter.WS5.TeslaMissingDependencyMessageTest do
  use ExUnit.Case, async: true

  test "missing Tesla refusal tells consumers how to repair the dependency" do
    # Same normalization as the qlever counterpart: unescape quotes and
    # collapse `<>`-concatenated literals so this matches the real message.
    source =
      "lib/ggen_igniter/pack.ex"
      |> File.read!()
      |> String.replace(~r/"\s*<>\s*"/s, "")
      |> String.replace(~s(\\"), ~s("))

    assert source =~ ~s(add {:tesla, "~> 1.8"} to your own mix.exs deps)
  end
end
