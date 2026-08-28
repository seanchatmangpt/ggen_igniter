defmodule GgenIgniter.WS5.TeslaPlainMapResponseTest do
  use ExUnit.Case, async: true

  test "HTTP success matching stays decoupled from Tesla.Env struct expansion" do
    source = File.read!("lib/ggen_igniter/pack.ex")
    assert source =~ "{:ok, %{status: 200, body: body}} -> body"
    refute source =~ "{:ok, %Tesla.Env{status: 200"
  end
end
