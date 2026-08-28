defmodule GgenIgniter.WS5.YamlPackContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "pack configuration retains YAML ingestion" do
    assert @mix =~ ~s({:yaml_elixir, "~> 2.9"})
  end
end
