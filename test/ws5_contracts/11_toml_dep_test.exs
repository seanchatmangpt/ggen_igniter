defmodule GgenIgniter.WS5.TomlDependencyTest do
  use ExUnit.Case, async: true

  test "TOML ingestion remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:toml, "~> 0.7"})
  end
end
