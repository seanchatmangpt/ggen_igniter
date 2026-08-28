defmodule GgenIgniter.WS5.QleverMissingDependencyMessageTest do
  use ExUnit.Case, async: true

  test "missing GNO refusal tells consumers how to enable QLever" do
    # The real message is built from concatenated (`<>`) multi-line string
    # literals with escaped quotes -- normalize both before matching so this
    # test checks the actual semantic message text, not raw source formatting.
    source =
      "lib/ggen_igniter/query/qlever.ex"
      |> File.read!()
      |> String.replace(~r/"\s*<>\s*"/s, "")
      |> String.replace(~s(\\"), ~s("))

    assert source =~ ~s(add {:gno, "~> 0.1"} to your own mix.exs deps)
  end
end
