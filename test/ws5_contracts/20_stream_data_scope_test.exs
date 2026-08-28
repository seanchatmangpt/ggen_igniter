defmodule GgenIgniter.WS5.StreamDataScopeTest do
  use ExUnit.Case, async: true

  test "property testing remains dev/test scoped" do
    assert File.read!("mix.exs") =~ ~s({:stream_data, "~> 1.2", only: [:dev, :test]})
  end
end
