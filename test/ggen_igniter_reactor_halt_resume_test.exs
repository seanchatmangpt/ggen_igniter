Code.require_file("fixtures/reactor-pack/saga_helper.exs", __DIR__)

defmodule GgenIgniter.ReactorHaltResumeTest do
  @moduledoc """
  Chicago-style: a generated saga containing a step that returns `{:halt, _}` (fact `rx:haltOnce`)
  is run with the real `Reactor.run/4`; the returned `{:halted, reactor}` is resumed with a second
  real `Reactor.run/4`. State assertions: the pre-halt step's run count in a real Agent ledger
  stays 1 across resume, and a from-scratch restart (falsifier) raises it to 2.
  """
  use ExUnit.Case, async: false
  alias B1d.SagaHelper, as: H

  @moduletag :integration
  @moduletag timeout: 600_000

  @steps [
    {"pre", [], []},
    {"gate", ["pre"], [haltOnce: "true"]},
    {"post", ["gate"], []}
  ]

  defp with_halting(name, fun) do
    ttl =
      H.saga_ttl("B1dFixture.Halting#{name}", "b1d_halt_ledger_#{name}", @steps,
        returnStep: "post"
      )

    ledger = :"b1d_halt_ledger_#{name}"
    pid = H.start_ledger(ledger)

    try do
      H.with_saga(ttl, fn [mod | _], _ -> fun.(mod, ledger) end)
    after
      H.stop_ledger(pid)
    end
  end

  test "halt then resume does not re-run completed steps" do
    with_halting("resume", fn mod, ledger ->
      assert {:halted, halted} = Reactor.run(mod, %{}, %{}, mod.run_options())
      assert Enum.count(H.ledger(ledger), &(&1 == {:run, :pre})) == 1
      refute {:run, :post} in H.ledger(ledger)

      assert {:ok, :post} = Reactor.run(halted, %{}, %{}, mod.run_options())
      events = H.ledger(ledger)
      assert Enum.count(events, &(&1 == {:run, :pre})) == 1
      # a halted step's `{:halt, value}` is its result: it is never re-run on resume
      assert Enum.count(events, &(&1 == {:halt, :gate})) == 1
      assert Enum.count(events, &(&1 == {:run, :gate})) == 0
      assert Enum.count(events, &(&1 == {:run, :post})) == 1
    end)
  end

  test "FALSIFIER: restarting from scratch re-runs the pre-halt step (counter 2)" do
    with_halting("restart", fn mod, ledger ->
      assert {:halted, _halted} = Reactor.run(mod, %{}, %{}, mod.run_options())
      # discard the halted reactor: a fresh run starts over
      assert {:ok, :post} = Reactor.run(mod, %{}, %{}, mod.run_options())
      assert Enum.count(H.ledger(ledger), &(&1 == {:run, :pre})) == 2
    end)
  end
end
