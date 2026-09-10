defmodule GgenIgniter.WS5.RustlerDependencyTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Rustler NIF bridge remains ~> 0.36" do
    assert @manifest =~ ~s({:rustler, "~> 0.36"})
  end
end
