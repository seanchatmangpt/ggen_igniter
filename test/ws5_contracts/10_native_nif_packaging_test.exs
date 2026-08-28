defmodule GgenIgniter.WS5.NativeNifPackagingTest do
  use ExUnit.Case, async: true

  test "native graph NIF sources remain packaged" do
    mix = File.read!("mix.exs")
    assert mix =~ "native/ggen_graph_nif/Cargo.toml"
    assert mix =~ "native/ggen_graph_nif/src"
  end
end
