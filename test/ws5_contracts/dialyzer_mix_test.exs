defmodule GgenIgniter.WS5.DialyzerMixTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Dialyzer PLT includes Mix for CLI task analysis" do
    assert @manifest =~ "plt_add_apps: [:mix]"
  end
end
