defmodule GgenIgniter.EDS.EvidenceState do
  @moduledoc """
  The Executable Design Science evidence-state vocabulary
  (Executable Design Science, S7: `PROPOSED | IMPLEMENTED | EXECUTABLE |
  OBSERVED | VERIFIED | REPRODUCIBLE | REPRODUCED | FALSIFIED | BLOCKED |
  UNSUPPORTED | UNKNOWN`) as real, checkable Elixir -- not documentation
  prose repeating the paper's vocabulary.

  The paper's central prohibition is state collapse (S7):

      IMPLEMENTED != VERIFIED
      EXECUTABLE  != OBSERVED_CONSEQUENCE
      OBSERVED    != VERIFIED
      VERIFIED    != INDEPENDENTLY_REPRODUCED

  This module makes that prohibition mechanically enforceable:
  `collapse?/2` names which state pairs would silently equate materially
  different epistemic claims, and `assert_no_collapse!/2` raises rather
  than let a caller narrate one state as another.
  """

  @type t ::
          :proposed
          | :implemented
          | :executable
          | :observed
          | :verified
          | :reproducible
          | :reproduced
          | :falsified
          | :blocked
          | :unsupported
          | :unknown

  @states ~w(proposed implemented executable observed verified reproducible reproduced falsified blocked unsupported unknown)a

  @doc "All valid evidence states, per the paper's S7 vocabulary."
  @spec states() :: [t()]
  def states, do: @states

  @spec valid?(t()) :: boolean()
  def valid?(state), do: state in @states

  # The paper's four named collapses (S7), plus the two symmetric reverses.
  # Each pair here is a claim the paper says must NOT be treated as
  # equivalent -- reaching one does not, by itself, license reaching the
  # other.
  @collapsed_pairs [
    {:implemented, :verified},
    {:executable, :observed},
    {:observed, :verified},
    {:verified, :reproduced}
  ]

  @doc """
  Would treating `from` as equivalent to `to` collapse two states the paper
  explicitly holds distinct? Symmetric -- collapse is a relation between the
  two states, not a direction.
  """
  @spec collapse?(t(), t()) :: boolean()
  def collapse?(from, to) when from == to, do: false

  def collapse?(from, to) do
    Enum.any?(@collapsed_pairs, fn {a, b} -> {from, to} in [{a, b}, {b, a}] end)
  end

  @doc """
  Raises with a message naming the exact prohibited collapse if `from` and
  `to` are a collapsed pair; otherwise returns `to` unchanged. Intended to
  guard the one place in a pipeline where a caller is tempted to write
  "verified" because "observed" already happened.
  """
  @spec assert_no_collapse!(t(), t()) :: t()
  def assert_no_collapse!(from, to) do
    if collapse?(from, to) do
      raise ArgumentError,
            "EDS state collapse refused: #{inspect(from)} does not by itself establish #{inspect(to)} " <>
              "(Executable Design Science S7: these are held explicitly distinct)"
    else
      to
    end
  end
end
