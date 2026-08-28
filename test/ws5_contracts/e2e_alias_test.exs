defmodule GgenIgniter.WS5.E2EAliasTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "e2e alias runs the canonical E2E script" do
    assert @manifest =~ ~s([e2e: ["run test/e2e/run_e2e.exs"]])
  end
end
