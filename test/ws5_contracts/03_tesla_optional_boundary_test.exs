defmodule GgenIgniter.WS5.TeslaOptionalBoundaryTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "HTTP pack fetching keeps Tesla optional for consumers" do
    assert @mix =~ ~s({:tesla, "~> 1.8", optional: true})
  end
end
