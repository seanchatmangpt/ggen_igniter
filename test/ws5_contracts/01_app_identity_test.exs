defmodule GgenIgniter.WS5.AppIdentityTest do
  use ExUnit.Case, async: true

  test "application identity remains ggen_igniter" do
    assert File.read!("mix.exs") =~ "app: :ggen_igniter"
  end
end
