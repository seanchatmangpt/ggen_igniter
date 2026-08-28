defmodule GgenIgniter.WS5.ReactorProdTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Reactor remains a production compile dependency" do
    assert @manifest =~ ~s({:reactor, "~> 1.0"})
  end
end
