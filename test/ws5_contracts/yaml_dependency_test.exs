defmodule GgenIgniter.WS5.YamlDependencyTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "YAML parsing dependency remains ~> 2.9" do
    assert @manifest =~ ~s({:yaml_elixir, "~> 2.9"})
  end
end
