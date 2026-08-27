defmodule GgenIgniter.FrontmatterTest do
  @moduledoc """
  Doctests for `GgenIgniter.Frontmatter` and
  `GgenIgniter.Frontmatter.MatchSpec` -- both modules are pure, deterministic
  parsing/tagging logic (no file I/O, network, or NIF calls), so their
  documented examples are run as real, asserted tests here rather than left
  as illustrative-only prose.

  No dedicated unit test file existed for these two modules before this file
  (the pre-existing `test/ggen_igniter_sync_frontmatter_test.exs` is a
  `mix ggen_igniter.sync` integration test exercising frontmatter parsing
  indirectly through a real CLI run, not a unit test of
  `GgenIgniter.Frontmatter`'s own functions) -- so this is a new, minimal
  file rather than an addition to a redundant existing one.
  """
  use ExUnit.Case, async: true

  doctest GgenIgniter.Frontmatter
  doctest GgenIgniter.Frontmatter.MatchSpec
end
