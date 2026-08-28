defmodule GgenIgniter.WS5.ReactorProdTest do
  use ExUnit.Case, async: true

  test "Reactor remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:reactor, "~> 1.0"})
  end
end
