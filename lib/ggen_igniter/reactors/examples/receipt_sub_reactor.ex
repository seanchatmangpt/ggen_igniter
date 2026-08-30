defmodule GgenIgniter.Reactors.Examples.ReceiptSubReactor do
  @moduledoc """
  Hand-authored (not ggen-manufactured) real sub-Reactor, composed into
  `GgenIgniter.Reactors.Examples.ExpenseApprovalReactor` via `compose/2` —
  demonstrates `Reactor.compose/2` embedding one real Reactor inside another,
  per `Reactor.Dsl.Compose`.
  """
  use Reactor

  input(:charge)

  step :format do
    argument(:charge, input(:charge))

    run(fn %{charge: charge}, _context ->
      {:ok, "sub-reactor formatted: #{charge.amount}"}
    end)
  end

  return(:format)
end
