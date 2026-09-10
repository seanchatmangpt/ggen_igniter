defmodule GgenIgniter.WS5.NifPackagingTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Rust NIF sources remain package-owned" do
    assert @manifest =~ "native/ggen_graph_nif/Cargo.toml"
    assert @manifest =~ "native/ggen_graph_nif/src"
  end
end
