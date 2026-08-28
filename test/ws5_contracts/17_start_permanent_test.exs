defmodule GgenIgniter.WS5.StartPermanentTest do
  use ExUnit.Case, async: true

  test "production keeps start_permanent enabled" do
    assert File.read!("mix.exs") =~ "start_permanent: Mix.env() == :prod"
  end
end
