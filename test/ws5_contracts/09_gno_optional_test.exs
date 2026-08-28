defmodule GgenIgniter.WS5.GnoOptionalTest do
  use ExUnit.Case, async: true

  test "GNO remains an optional consumer capability" do
    assert File.read!("mix.exs") =~ ~s({:gno, "~> 0.1", optional: true})
  end
end
