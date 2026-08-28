defmodule GgenIgniter.WS5.LoggerAppTest do
  use ExUnit.Case, async: true

  test "logger remains an explicit runtime application" do
    assert File.read!("mix.exs") =~ "extra_applications: [:logger]"
  end
end
