defmodule GgenIgniter.EngineTest do
  @moduledoc """
  Doctests for `GgenIgniter.Engine` -- `registry/0`, `valid_names/0`, and
  `fetch!/1` are pure map lookups (no file I/O, network, or NIF calls), so
  their documented examples are run as real, asserted tests here.

  No test file existed for `GgenIgniter.Engine` itself before this one (only
  per-adapter tests like `test/ggen_igniter_oxigraph_engine_test.exs` and
  `test/ggen_igniter_sync_qlever_engine_test.exs` existed, which exercise the
  `GgenIgniter.Engine.Oxigraph`/`Qlever` adapter modules, not the `Engine`
  registry module itself) -- this is a new, minimal file.
  """
  use ExUnit.Case, async: true

  doctest GgenIgniter.Engine
end
