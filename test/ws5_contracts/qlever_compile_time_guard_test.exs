defmodule GgenIgniter.WS5.QleverCompileTimeGuardTest do
  use ExUnit.Case, async: true

  test "QLever implementation remains behind the GNO compile-time fence" do
    source = File.read!("lib/ggen_igniter/query/qlever.ex")
    assert source =~ "if Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do"
  end
end
