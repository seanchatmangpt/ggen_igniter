defmodule GgenIgniter.EDS.EvidenceStateTest do
  @moduledoc "Chicago-style: pure Elixir logic under test, no external collaborator to fake."

  use ExUnit.Case, async: true

  alias GgenIgniter.EDS.EvidenceState

  test "valid?/1 accepts exactly the paper's S7 vocabulary" do
    for state <-
          ~w(proposed implemented executable observed verified reproducible reproduced falsified blocked unsupported unknown)a do
      assert EvidenceState.valid?(state)
    end

    refute EvidenceState.valid?(:done)
    refute EvidenceState.valid?(:working)
    refute EvidenceState.valid?(:passing)
  end

  test "collapse?/2 identifies the paper's four named collapses, both directions" do
    assert EvidenceState.collapse?(:implemented, :verified)
    assert EvidenceState.collapse?(:verified, :implemented)
    assert EvidenceState.collapse?(:executable, :observed)
    assert EvidenceState.collapse?(:observed, :verified)
    assert EvidenceState.collapse?(:verified, :reproduced)
  end

  test "collapse?/2 is false for a state and itself, and for unrelated pairs" do
    refute EvidenceState.collapse?(:verified, :verified)
    refute EvidenceState.collapse?(:proposed, :blocked)
    refute EvidenceState.collapse?(:unknown, :unsupported)
  end

  test "assert_no_collapse!/2 raises with the specific states named, refuses the collapse" do
    assert_raise ArgumentError, ~r/:implemented.*:verified/, fn ->
      EvidenceState.assert_no_collapse!(:implemented, :verified)
    end
  end

  test "assert_no_collapse!/2 passes through non-collapsed transitions" do
    assert EvidenceState.assert_no_collapse!(:proposed, :implemented) == :implemented
  end
end
