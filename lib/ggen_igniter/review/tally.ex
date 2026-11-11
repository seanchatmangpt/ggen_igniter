defmodule GgenIgniter.Review.Tally do
  @moduledoc """
  Rounds voting into a round document: survivors are `:posted`, everything
  else is `:suppressed`. Deterministic: posted and suppressed lists are each
  sorted by `{file, line, id}` so the same input always produces the same
  round doc (and therefore the same stored bytes).
  """

  alias GgenIgniter.Review.Finding

  @doc """
  Tallies `findings` under `verifier_fns`. Returns
  `%{posted: [Finding.t()], suppressed: [Finding.t()]}`.

  NOTE: class-based dropping (`:style`/`:diagnostic` never reach a vote)
  happens upstream in `GgenIgniter.Review`, pre-vote, per the round law —
  this module only tallies what it is given.
  """
  @spec tally([Finding.t()], [GgenIgniter.Review.Verifier.t()]) :: %{
          posted: [Finding.t()],
          suppressed: [Finding.t()]
        }
  def tally(findings, verifier_fns) do
    {posted, suppressed} =
      Enum.split_with(findings, fn f ->
        match?({:sustained, _}, GgenIgniter.Review.Verifier.vote(f, verifier_fns))
      end)

    %{posted: sort(posted), suppressed: sort(suppressed)}
  end

  defp sort(findings), do: Enum.sort_by(findings, &{&1.file, &1.line, &1.id})
end
