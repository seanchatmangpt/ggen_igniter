defmodule GgenIgniter.WS5.TeslaRedirectBudgetTest do
  use ExUnit.Case, async: true

  test "pack fetch follows at most five redirects" do
    source = File.read!("lib/ggen_igniter/pack.ex")
    assert source =~ "{Tesla.Middleware.FollowRedirects, max_redirects: 5}"
  end
end
