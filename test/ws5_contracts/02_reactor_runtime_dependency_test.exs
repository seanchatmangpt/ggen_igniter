defmodule GgenIgniter.WS5.ReactorRuntimeDependencyTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Reactor reconciliation remains a compile-time runtime dependency" do
    assert @mix =~ ~s({:reactor, "~> 1.0"})
  end
end
