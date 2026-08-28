defmodule GgenIgniter.WS5.IgniterProdTest do
  use ExUnit.Case, async: true

  test "Igniter remains a production dependency" do
    mix = File.read!("mix.exs")
    assert mix =~ ~s({:igniter, "~> 0.8"})
    refute mix =~ ~s({:igniter, "~> 0.8", only:)
  end
end
