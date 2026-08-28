defmodule GgenIgniter.WS5.RustlerNifContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "native graph integration preserves Rustler 0.36" do
    assert @mix =~ ~s({:rustler, "~> 0.36"})
  end
end
