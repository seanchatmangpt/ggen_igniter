defmodule GgenIgniter.WS5.ElixirFloorTest do
  use ExUnit.Case, async: true

  test "Elixir compatibility floor remains 1.17" do
    assert File.read!("mix.exs") =~ ~s(elixir: "~> 1.17")
  end
end
