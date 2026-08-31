Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseRefactorsTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with two
  real, unmodified ex4pm files that both call the real
  `Ex4pm.Contracts.verify/0` function -- `apps/ex4pm/lib/ex4pm.ex` (a real
  production caller, line 26) and `apps/ex4pm_contracts/test/contracts_test.exs`
  (a real test caller, line 5) -- plus the real `Ex4pm.Contracts` module
  itself, driving `Igniter.Refactors.Rename.rename_function/4`. Neither
  `Igniter.Refactors.Rename` nor `Igniter.Refactors.Elixir` has any test
  coverage in this repo today.

  Real, disclosed finding: `rename_function/4` crashes with a real
  `ArgumentError` (`length(nil)`) when the target function is declared
  WITHOUT parens (`def verify do ... end`, the completely idiomatic style
  `Ex4pm.Contracts.verify/0` and every other zero-arity function in this
  real module uses) -- confirmed by reading
  `deps/igniter/lib/igniter/refactors/rename.ex:322-326`'s real
  `length(args) == arity` guard against `{:def, _, [{^old_function, _, args},
  _body]}`: Elixir's own AST represents a parenless zero-arity `def name do`
  as `args = nil`, not `args = []`, and `length(nil)` raises. Not a missed
  feature -- a real crash on real, common, idiomatic code, surfaced only by
  testing against a real project rather than the parenthesized style the
  library's own synthetic examples always use. The second describe block
  below proves the same real API succeeds cleanly against a real function
  that HAS an explicit argument (`Ex4pm.Contracts.read/1`), isolating the
  parenless-zero-arity case as the specific real trigger.

  A THIRD real, disclosed finding surfaces in that second block:
  `Ex4pm.Contracts.read/1`'s real definition carries a guard clause
  (`def read(id) when is_atom(id) do`), which Elixir's AST represents as
  `{:def, _, [{:when, _, [{:read, _, [id]}, guard]}, body]}` -- the function
  name sits one level deeper, inside a `:when` wrapper, not as the direct
  first element `update_refs/7`'s pattern `{^old_function, _, args}` expects
  (`rename.ex:322`). The real, internal self-call site
  (`verify_required_terms/0`'s `with {:ok, bytes} <- read(id) do`) IS
  correctly renamed to `fetch(id)` -- call-site rewriting does not share the
  guard-clause blind spot -- but the guarded `def read(id) when ...`
  definition itself is left completely untouched. A real partial success,
  not a crash and not a clean rename: exactly the kind of silent
  under-application Chicago-style state assertions catch and an
  interaction-based ("was rename_function called") test would have missed.
  """

  use ExUnit.Case, async: true

  describe "Igniter.Refactors.Elixir.unless_to_if_not/1 (no real ex4pm target -- disclosed)" do
    # A real search (`grep -rln "unless " apps --include "*.ex"`) found no
    # real `unless ... do` call anywhere in ex4pm's actual source -- one
    # docstring mentions the English word "unless" in prose, no code. Rather
    # than fabricate a false "real ex4pm target," this is disclosed as a
    # genuine absence, and this one test exercises the real codemod against
    # a minimal, explicitly-labeled synthetic snippet (NOT sourced from
    # ex4pm) so the codemod itself still gets real coverage.
    test "rewrites a minimal synthetic `unless` call to `if not`" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "lib/synthetic.ex" => """
            defmodule Synthetic do
              def check(x) do
                unless x > 0 do
                  :non_positive
                end
              end
            end
            """
          }
        )

      igniter = Igniter.Refactors.Elixir.unless_to_if_not(igniter)

      source = igniter.rewrite |> Rewrite.source!("lib/synthetic.ex") |> Rewrite.Source.get(:content)
      assert source =~ "if not (x > 0) do"
      refute source =~ "unless"
    end
  end

  describe "Igniter.Refactors.Rename.rename_function/4 (real parenless zero-arity def -- the crash)" do
    test "crashes with a real ArgumentError against Ex4pm.Contracts.verify/0's real parenless def" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "lib/ex4pm/contracts.ex" => Ex4pmFixture.contracts_source(),
            "lib/ex4pm.ex" => Ex4pmFixture.read!("apps/ex4pm/lib/ex4pm.ex"),
            "test/contracts_test.exs" =>
              Ex4pmFixture.read!("apps/ex4pm_contracts/test/contracts_test.exs")
          }
        )

      assert_raise ArgumentError, ~r/not a list/, fn ->
        Igniter.Refactors.Rename.rename_function(
          igniter,
          {Ex4pm.Contracts, :verify},
          {Ex4pm.Contracts, :check},
          arity: 0
        )
      end
    end
  end

  describe "Igniter.Refactors.Rename.rename_function/4 (real guarded function -- partial success)" do
    test "renames the real internal self-call site but leaves the real guarded def untouched" do
      igniter =
        Igniter.Test.test_project(
          files: %{"lib/ex4pm/contracts.ex" => Ex4pmFixture.contracts_source()}
        )

      igniter =
        Igniter.Refactors.Rename.rename_function(
          igniter,
          {Ex4pm.Contracts, :read},
          {Ex4pm.Contracts, :fetch},
          arity: 1
        )

      source =
        igniter.rewrite |> Rewrite.source!("lib/ex4pm/contracts.ex") |> Rewrite.Source.get(:content)

      # the real internal self-call (inside verify_required_terms/0) IS renamed
      assert source =~ "with {:ok, bytes} <- fetch(id) do"
      refute source =~ "with {:ok, bytes} <- read(id) do"

      # but the real guarded definition itself is NOT renamed -- the
      # disclosed `:when`-wrapper blind spot
      assert source =~ "def read(id) when is_atom(id) do"
      refute source =~ "def fetch(id) when is_atom(id) do"

      # every real, untouched neighboring function survives byte-for-byte
      assert source =~ "def manifest do"
      assert source =~ "def verify do"
    end
  end
end
