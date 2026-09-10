defmodule GgenIgniter.FinalizeEvidenceRetrySafetyTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `:finalize_evidence` on
  `GgenIgniter.Reactors.ReconcileReactor` is hardened against Reactor's
  default automatic-retry behavior (`max_retries(0)`), closing the gap
  `docs/status.md` row 122 used to describe as "no `max_retries 0`
  override".

  This reads the REAL compiled DSL state via `Reactor.Info.steps/1` (Spark's
  own introspection API for the `Reactor.Dsl` extension) against the real
  `GgenIgniter.Reactors.ReconcileReactor` module -- no mock of `Reactor` or
  the DSL, just asserting on the real, already-compiled step struct's
  `max_retries` field. `:actuate` and `:verify` are asserted alongside it as
  the other two explicit actuation-class steps this module's own comments
  say `:finalize_evidence` was hardened to match.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Reactors.ReconcileReactor

  test "finalize_evidence has max_retries(0), matching actuate/verify" do
    steps =
      ReconcileReactor
      |> Reactor.Info.reactor()
      |> Enum.filter(&match?(%Reactor.Dsl.Step{}, &1))

    finalize_evidence = Enum.find(steps, &(&1.name == :finalize_evidence))
    actuate = Enum.find(steps, &(&1.name == :actuate))
    verify = Enum.find(steps, &(&1.name == :verify))

    refute is_nil(finalize_evidence)
    refute is_nil(actuate)
    refute is_nil(verify)

    assert finalize_evidence.max_retries == 0
    assert actuate.max_retries == 0
    assert verify.max_retries == 0
  end
end
