defmodule GgenIgniter.WS5.GnoOptionalTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "GNO remains an optional QLever consumer capability" do
    assert @manifest =~ ~s({:gno, "~> 0.1", optional: true})
  end
end
