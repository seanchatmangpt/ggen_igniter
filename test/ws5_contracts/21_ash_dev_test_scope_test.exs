defmodule GgenIgniter.WS5.AshDevTestScopeTest do
  @moduledoc """
  Source contract for the Ash-must-not-ship fence's dependency half:

  every `:ash*` Hex dependency declared in this project's `mix.exs` must be
  scoped `only: [:dev, :test]` so Hex metadata never lists Ash as a runtime
  requirement for consumers. Companion to
  `test/ggen_igniter_package_ash_free_test.exs` (real tarball) and
  `test/ggen_igniter_shipped_packs_fence_test.exs` (pack path fence).
  """
  use ExUnit.Case, async: true

  @mix_path Path.expand("../../mix.exs", __DIR__)

  test "every ash* Hex dep is only: [:dev, :test]" do
    mix = File.read!(@mix_path)

    ash_deps = Regex.scan(~r/\{:ash[\w]*,[^}]+\}/, mix) |> Enum.map(&hd/1)

    assert ash_deps != [], "sanity: mix.exs declares at least one :ash* dep"

    for dep <- ash_deps do
      assert dep =~ ~r/only:\s*\[:dev,\s*:test\]/,
             "Ash dep must be dev/test-only (Hex fence): #{dep}"
    end

    # Named pins — refuse silent removals of the known Ash surface set.
    for name <- [
          ~s({:ash, "~> 3.0", only: [:dev, :test]}),
          ~s({:ash_postgres, "~> 2.0", only: [:dev, :test]}),
          ~s({:ash_json_api, "~> 1.0", only: [:dev, :test]}),
          ~s({:ash_ai, "~> 1.0", only: [:dev, :test]}),
          ~s({:ash_state_machine, "~> 0.2", only: [:dev, :test]}),
          ~s({:ash_oban, "~> 0.8", only: [:dev, :test]}),
          ~s({:ash_a2a, "~> 26.9", only: [:dev, :test]})
        ] do
      assert mix =~ name
    end

    refute mix =~ ~r/\{:ash_phoenix,/
  end
end
