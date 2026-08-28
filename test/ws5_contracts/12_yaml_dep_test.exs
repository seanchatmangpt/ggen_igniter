defmodule GgenIgniter.WS5.YamlDependencyTest do
  use ExUnit.Case, async: true

  test "YAML ingestion remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:yaml_elixir, "~> 2.9"})
  end
end
