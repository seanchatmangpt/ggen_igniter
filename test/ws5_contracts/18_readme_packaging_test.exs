defmodule GgenIgniter.WS5.ReadmePackagingTest do
  use ExUnit.Case, async: true
  test "README remains part of the package contract" do
    assert File.read!("mix.exs") =~ "README.md"
  end
end
