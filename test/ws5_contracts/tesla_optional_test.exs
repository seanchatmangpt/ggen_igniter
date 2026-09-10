defmodule GgenIgniter.WS5.TeslaOptionalTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Tesla remains an optional consumer capability" do
    assert @manifest =~ ~s({:tesla, "~> 1.8", optional: true})
  end
end
