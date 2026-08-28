defmodule GgenIgniter.WS5.TomlDependencyTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "TOML parsing dependency remains ~> 0.7" do
    assert @manifest =~ ~s({:toml, "~> 0.7"})
  end
end
