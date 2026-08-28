defmodule GgenIgniter.WS5.IgniterRuntimeDependencyTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "consumer CLI keeps Igniter as a production dependency" do
    assert @mix =~ ~s({:igniter, "~> 0.8"})
  end
end
