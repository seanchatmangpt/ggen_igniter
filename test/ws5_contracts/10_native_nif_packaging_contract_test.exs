defmodule GgenIgniter.WS5.NativeNifPackagingContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Hex package preserves native ggen graph NIF sources" do
    assert @mix =~ "native/ggen_graph_nif/Cargo.toml"
    assert @mix =~ "native/ggen_graph_nif/src"
  end
end
