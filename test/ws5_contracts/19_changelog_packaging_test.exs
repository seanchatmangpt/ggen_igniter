defmodule GgenIgniter.WS5.ChangelogPackagingTest do
  use ExUnit.Case, async: true
  test "CHANGELOG remains part of the package contract" do
    assert File.read!("mix.exs") =~ "CHANGELOG.md"
  end
end
