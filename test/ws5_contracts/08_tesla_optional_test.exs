defmodule GgenIgniter.WS5.TeslaOptionalTest do
  use ExUnit.Case, async: true

  test "Tesla remains an optional consumer capability" do
    assert File.read!("mix.exs") =~ ~s({:tesla, "~> 1.8", optional: true})
  end
end
