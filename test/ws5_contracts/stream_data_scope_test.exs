defmodule GgenIgniter.WS5.StreamDataScopeTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "stream_data remains scoped to development and test" do
    assert @manifest =~ ~s({:stream_data, "~> 1.2", only: [:dev, :test]})
  end
end
