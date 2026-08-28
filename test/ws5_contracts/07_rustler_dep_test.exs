defmodule GgenIgniter.WS5.RustlerDependencyTest do
  use ExUnit.Case, async: true

  test "Rustler remains a production dependency for the graph NIF" do
    assert File.read!("mix.exs") =~ ~s({:rustler, "~> 0.36"})
  end
end
