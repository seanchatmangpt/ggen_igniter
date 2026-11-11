defmodule GgenIgniter.Review.Verifier do
  @moduledoc """
  M-verifier voting over a single finding.

  A verifier is a plain 1-arity function `finding -> :sustain | :reject |
  :abstain`. In tests these are real hand-written functions (real
  collaborators, not doubles); in production they are deterministic checks
  (e.g. "does the cited file/line exist", "is the class still in the closed
  set").

  Majority law: the finding is sustained iff
  `sustain_count >= floor(M/2) + 1` AND `sustain_count > reject_count`.
  Abstentions count toward M but toward neither side. With M = 3 that means:
  2-0 sustain passes, 2-1 passes, 1-1-1 fails (tie), 3 rejects fail.
  """

  alias GgenIgniter.Review.Finding

  @typedoc "A verifier: finding -> vote."
  @type t :: (Finding.t() -> :sustain | :reject | :abstain)

  @doc "Default verifier count."
  @spec default_count() :: 3
  def default_count, do: 3

  @doc """
  Votes one finding under `verifiers` (default 3 verifiers required when
  `:count` is given without `:verifiers` — callers inject the real functions;
  see `pad_default/2`).
  Returns `{:sustained, votes}` or `{:rejected, votes}`.
  """
  @spec vote(Finding.t(), [t()]) :: {:sustained, [:sustain | :reject | :abstain]}
  def vote(%Finding{} = finding, verifiers) when is_list(verifiers) and verifiers != [] do
    votes = Enum.map(verifiers, fn v -> v.(finding) end)
    sustain = Enum.count(votes, &(&1 == :sustain))
    reject = Enum.count(votes, &(&1 == :reject))
    m = length(votes)
    floor_n = div(m, 2) + 1

    if sustain >= floor_n and sustain > reject do
      {:sustained, votes}
    else
      {:rejected, votes}
    end
  end

  @doc """
  Pads a verifier list to `count` entries with the neutral default verifier
  (`always_abstain/1`). Used by `GgenIgniter.Review` when `--verifiers N` is
  larger than the number of injected verifiers, and to materialize the
  default M = 3 when no verifiers are injected (three abstentions reject
  everything — the fail-closed default: an unreviewed finding never posts).
  """
  @spec pad_default([t()], pos_integer()) :: [t()]
  def pad_default(verifiers, count) when count >= 1 do
    given = length(verifiers)

    if given >= count do
      Enum.take(verifiers, count)
    else
      verifiers ++ List.duplicate(&always_abstain/1, count - given)
    end
  end

  @doc "The neutral verifier: always abstains."
  @spec always_abstain(Finding.t()) :: :abstain
  def always_abstain(%Finding{}), do: :abstain
end
