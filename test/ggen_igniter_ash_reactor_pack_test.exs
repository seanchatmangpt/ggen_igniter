Code.require_file("fixtures/reactor-pack/saga_helper.exs", __DIR__)

defmodule GgenIgniter.AshReactorPackTest do
  @moduledoc """
  Chicago-style: `Ash.Reactor` steps (create/update/destroy/action) manufactured from ontology
  facts by a real `mix ggen_igniter.sync` subprocess and compiled with the real compiler against
  real ash + reactor. The saga is RUN with `Reactor.run/4` against a real Ash resource on the
  ETS data layer (a hand-written test INPUT under `test/fixtures/reactor-pack/`); assertions read
  the data layer with real `Ash.read!/1`. A failing later step must leave the row absent (the
  generated `undo :always` / `undo_action :destroy` ran). ETS cannot roll back a transaction,
  so compensation is asserted through undo, not through `Ash.Reactor`'s `transaction`.
  """
  use ExUnit.Case, async: false
  alias B1d.SagaHelper, as: H

  @moduletag :integration
  @moduletag timeout: 600_000

  @ticket_src File.read!(Path.expand("fixtures/reactor-pack/ash_ticket.ex.txt", __DIR__))
  @ttl File.read!(Path.expand("fixtures/reactor-pack/ash_steps.ttl", __DIR__))

  defp with_flow(ttl, fun) do
    H.with_saga(ttl, [{"lib/ticket.ex", @ticket_src}], fn mods, r ->
      flow = Enum.find(mods, &(&1 == B1dFixture.TicketFlow))
      Ash.DataLayer.Ets.stop(B1dFixture.Ticket)

      try do
        fun.(flow, r)
      after
        Ash.DataLayer.Ets.stop(B1dFixture.Ticket)
      end
    end)
  end

  test "create+update steps run against real Ash/ETS: the record exists, closed" do
    with_flow(@ttl, fn flow, _r ->
      assert {:ok, ticket} = Reactor.run(flow, %{title: "hello"}, %{}, [])
      assert ticket.state == "closed"
      assert [%{title: "hello", state: "closed"}] = Ash.read!(B1dFixture.Ticket)
    end)
  end

  test "generated source uses the Ash.Reactor DSL and facts, not literals from the ontology" do
    with_flow(@ttl, fn _flow, r ->
      src = File.read!(hd(r.files))
      assert src =~ "use Reactor, extensions: [Ash.Reactor]"
      assert src =~ "create :open, B1dFixture.Ticket, :open do"
      assert src =~ "update :close, B1dFixture.Ticket, :close do"
      assert src =~ ~r/undo_action\(?:undo\)?/
      refute @ttl =~ "use Reactor"
    end)
  end

  test "a failing later step undoes the earlier create: the row is absent" do
    failing =
      @ttl <>
        """

        ex:boom a rx:SagaStep ; rx:inReactor ex:reactor ; rx:name "boom" ; rx:kind "ash" ;
            rx:ashOp "create" ; rx:resource "B1dFixture.Ticket" ; rx:ashAction "explode" ;
            rx:dependsOn ex:close ;
            rx:ashInput [ rx:param "title" ; rx:sourceKind "value" ; rx:source "never" ] .
        """

    failing = String.replace(failing, "rx:returnStep \"close\"", "rx:returnStep \"boom\"")

    with_flow(failing, fn flow, _r ->
      assert {:error, _} = Reactor.run(flow, %{title: "doomed"}, %{}, [])
      assert Ash.read!(B1dFixture.Ticket) == []
    end)
  end

  test "FALSIFIER: pointing the first create at the failing action leaves no row and no success" do
    mutated = String.replace(@ttl, "rx:ashAction \"open\"", "rx:ashAction \"explode\"")
    refute mutated == @ttl

    with_flow(mutated, fn flow, _r ->
      assert {:error, _} = Reactor.run(flow, %{title: "hello"}, %{}, [])
      assert Ash.read!(B1dFixture.Ticket) == []
    end)
  end

  test "FALSIFIER: dropping rx:undoAction from the create leaves the orphan row after a later failure" do
    failing =
      @ttl <>
        """

        ex:boom a rx:SagaStep ; rx:inReactor ex:reactor ; rx:name "boom" ; rx:kind "ash" ;
            rx:ashOp "create" ; rx:resource "B1dFixture.Ticket" ; rx:ashAction "explode" ;
            rx:dependsOn ex:close ;
            rx:ashInput [ rx:param "title" ; rx:sourceKind "value" ; rx:source "never" ] .
        """

    failing = String.replace(failing, "rx:returnStep \"close\"", "rx:returnStep \"boom\"")
    no_undo = String.replace(failing, "    rx:undoAction \"undo\" ;\n", "")
    refute no_undo == failing

    with_flow(no_undo, fn flow, _r ->
      assert {:error, _} = Reactor.run(flow, %{title: "orphan"}, %{}, [])
      assert [%{title: "orphan"}] = Ash.read!(B1dFixture.Ticket)
    end)
  end

  test "ash step lacking resource/action is REFUSED:REACTOR_MALFORMED with zero files" do
    bad =
      String.replace(
        @ttl,
        "rx:resource \"B1dFixture.Ticket\" ; rx:ashAction \"open\" ;",
        "rx:ashAction \"open\" ;"
      )

    refute bad == @ttl
    assert {status, out, written} = H.refuse(bad)
    assert status != 0
    assert out =~ "REFUSED:REACTOR_MALFORMED"
    assert written == []
  end
end
