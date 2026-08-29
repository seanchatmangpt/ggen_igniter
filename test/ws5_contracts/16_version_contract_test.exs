defmodule GgenIgniter.WS5.VersionContractTest do
  use ExUnit.Case, async: true

  test "CalVer package identity remains 26.9.1" do
    assert File.read!("mix.exs") =~ ~s(version: "26.9.1")
  end
end
