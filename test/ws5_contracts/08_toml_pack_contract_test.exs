defmodule GgenIgniter.WS5.TomlPackContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "pack configuration retains TOML support" do
    assert @mix =~ ~s({:toml, "~> 0.7"})
  end
end
