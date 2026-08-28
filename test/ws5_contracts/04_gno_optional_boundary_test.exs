defmodule GgenIgniter.WS5.GnoOptionalBoundaryTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "QLever integration keeps gno optional for consumers" do
    assert @mix =~ ~s({:gno, "~> 0.1", optional: true})
  end
end
