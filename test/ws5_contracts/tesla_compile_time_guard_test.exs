defmodule GgenIgniter.WS5.TeslaCompileTimeGuardTest do
  use ExUnit.Case, async: true

  test "optional Tesla calls remain behind compile-time admission" do
    source = File.read!("lib/ggen_igniter/pack.ex")
    assert source =~ "if Code.ensure_loaded?(Tesla) do"
  end
end
