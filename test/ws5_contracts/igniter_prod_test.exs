defmodule GgenIgniter.WS5.IgniterProdTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Igniter remains a production compile dependency" do
    assert @manifest =~ ~s({:igniter, "~> 0.8"})
  end
end
