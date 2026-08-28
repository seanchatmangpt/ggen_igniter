defmodule GgenIgniter.WS5.VersionTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "package version remains 26.8.27" do
    assert @manifest =~ ~s(version: "26.8.27")
  end
end
