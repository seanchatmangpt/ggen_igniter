defmodule GgenIgniter.WS5.MixPltTest do
  use ExUnit.Case, async: true

  test "Mix remains in the Dialyzer PLT for CLI tasks" do
    assert File.read!("mix.exs") =~ "plt_add_apps: [:mix]"
  end
end
