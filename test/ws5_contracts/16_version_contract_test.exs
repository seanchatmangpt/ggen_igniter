defmodule GgenIgniter.WS5.VersionContractTest do
  use ExUnit.Case, async: true

  test "CalVer package identity remains 26.8.28" do
    assert File.read!("mix.exs") =~ ~s(version: "26.8.28")
  end
end
