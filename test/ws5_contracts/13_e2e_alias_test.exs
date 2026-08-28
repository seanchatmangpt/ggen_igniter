defmodule GgenIgniter.WS5.E2EAliasTest do
  use ExUnit.Case, async: true

  test "consumer scaffold E2E verifier remains callable" do
    assert File.read!("mix.exs") =~ ~s(e2e: ["run test/e2e/run_e2e.exs"])
  end
end
