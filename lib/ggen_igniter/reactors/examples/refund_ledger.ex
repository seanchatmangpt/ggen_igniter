defmodule GgenIgniter.Reactors.Examples.RefundLedger do
  @moduledoc """
  Hand-authored (not ggen-manufactured) real, test-observable Agent-backed
  ledger recording every real refund issued by
  `GgenIgniter.Reactors.Examples.Support.refund/2` — a genuine collaborator
  with real process state (per this repo's Chicago-testing discipline: not
  a mock, a real `Agent` other tests can assert against), so tests can
  prove the generated Reactor's `compensate`/`undo` steps actually ran.
  """
  use Agent

  @spec start_link(any()) :: Agent.on_start()
  def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  @doc "Records one real refund fact: `{card_token, amount}`."
  @spec record(String.t(), number()) :: :ok
  def record(card_token, amount) do
    ensure_started!()
    Agent.update(__MODULE__, fn refunds -> [{card_token, amount} | refunds] end)
  end

  @doc "Returns every real refund recorded so far, most recent first."
  @spec all() :: [{String.t(), number()}]
  def all do
    ensure_started!()
    Agent.get(__MODULE__, & &1)
  end

  @doc "Clears the ledger — for real, test-local isolation between cases."
  @spec clear() :: :ok
  def clear do
    ensure_started!()
    Agent.update(__MODULE__, fn _ -> [] end)
  end

  defp ensure_started! do
    case Process.whereis(__MODULE__) do
      nil -> start_link([])
      _pid -> :ok
    end
  end
end
