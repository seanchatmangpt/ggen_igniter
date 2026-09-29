Code.require_file("fixtures/reactor-pack/saga_helper.exs", __DIR__)

defmodule GgenIgniter.ReactorSagaOrderTest do
  @moduledoc """
  Chicago-style: sagas manufactured from ontology facts by a real `mix ggen_igniter.sync`
  subprocess, compiled by the real compiler against real reactor, then RUN with `Reactor.run/4`.
  Side effects go to a real Agent-backed ledger; assertions are on the final ledger contents
  (undo in reverse completion order, retry idempotence), the real halt/resume result of
  `Reactor.run/4`, and a real in-flight high-water mark for `rx:maxConcurrency`. No doubles.
  """
  use ExUnit.Case, async: false
  alias B1d.SagaHelper, as: H

  @moduletag :integration
  @moduletag timeout: 600_000

  defp run_saga(ttl, ledger_name, fun) do
    pid = H.start_ledger(ledger_name)

    try do
      H.with_saga(ttl, fn [mod | _], r -> fun.(mod, r) end)
    after
      H.stop_ledger(pid)
    end
  end

  defp three_steps(undo2) do
    [
      {"s1", [], [undoes: "true"]},
      {"s2", ["s1"], if(undo2, do: [undoes: "true"], else: [])},
      {"s3", ["s2"], [failAlways: "true"]}
    ]
  end

  test "failure at step 3 undoes in reverse completion order: [run1, run2, run3_fail, undo2, undo1]" do
    ttl =
      H.saga_ttl("B1dFixture.Order3", "b1d_order_ledger", three_steps(true),
        returnStep: "s3",
        undoOrder: "reverse"
      )

    run_saga(ttl, :b1d_order_ledger, fn mod, _ ->
      assert {:error, _} = Reactor.run(mod, %{}, %{}, mod.run_options())

      assert H.ledger(:b1d_order_ledger) ==
               [{:run, :s1}, {:run, :s2}, {:fail, :s3}, {:undo, :s2}, {:undo, :s1}]
    end)
  end

  test "CANARY / FALSIFIER: without rx:undoOrder the real Reactor 1.0.6 undoes oldest-first" do
    # deps/reactor executor.ex handle_undo/2 reverses an undo stack that sync.ex and async.ex both
    # PREPEND to, i.e. completion order - the reverse-order saga contract is not native.
    ttl =
      H.saga_ttl("B1dFixture.Order3Native", "b1d_order_native_ledger", three_steps(true),
        returnStep: "s3"
      )

    run_saga(ttl, :b1d_order_native_ledger, fn mod, _ ->
      assert {:error, _} = Reactor.run(mod, %{}, %{}, mod.run_options())

      assert H.ledger(:b1d_order_native_ledger) ==
               [{:run, :s1}, {:run, :s2}, {:fail, :s3}, {:undo, :s1}, {:undo, :s2}]
    end)
  end

  test "FALSIFIER: dropping undo on step 2 changes the ledger" do
    ttl =
      H.saga_ttl("B1dFixture.Order3NoUndo", "b1d_order_ledger2", three_steps(false),
        returnStep: "s3",
        undoOrder: "reverse"
      )

    run_saga(ttl, :b1d_order_ledger2, fn mod, _ ->
      assert {:error, _} = Reactor.run(mod, %{}, %{}, mod.run_options())
      ledger = H.ledger(:b1d_order_ledger2)
      assert ledger == [{:run, :s1}, {:run, :s2}, {:fail, :s3}, {:undo, :s1}]
      refute ledger == [{:run, :s1}, {:run, :s2}, {:fail, :s3}, {:undo, :s2}, {:undo, :s1}]
    end)
  end

  test "retry (max_retries 2) of a step that fails once: side effect happens exactly once" do
    steps = [
      {"s1", [], []},
      {"s2", ["s1"], [failTimes: "1", maxRetries: "2"]}
    ]

    ttl = H.saga_ttl("B1dFixture.RetryOnce", "b1d_retry_ledger", steps, returnStep: "s2")

    run_saga(ttl, :b1d_retry_ledger, fn mod, _ ->
      assert {:ok, :s2} = Reactor.run(mod, %{}, %{}, mod.run_options())
      ledger = H.ledger(:b1d_retry_ledger)
      assert Enum.count(ledger, &(&1 == {:run, :s2})) == 1
      assert Enum.count(ledger, &(&1 == {:fail, :s2})) == 1
      assert ledger == [{:run, :s1}, {:fail, :s2}, {:run, :s2}]
    end)
  end

  test "FALSIFIER: without maxRetries the same once-failing step is not retried (run absent)" do
    steps = [{"s1", [], []}, {"s2", ["s1"], [failTimes: "1"]}]
    ttl = H.saga_ttl("B1dFixture.NoRetry", "b1d_noretry_ledger", steps, returnStep: "s2")

    run_saga(ttl, :b1d_noretry_ledger, fn mod, _ ->
      assert {:error, _} = Reactor.run(mod, %{}, %{}, mod.run_options())
      refute {:run, :s2} in H.ledger(:b1d_noretry_ledger)
    end)
  end

  test "rx:maxConcurrency 2 bounds in-flight async steps (8 steps, real high-water mark)" do
    steps = for i <- 1..8, do: {"w#{i}", [], [async: "true", holdMs: "60"]}
    ttl = H.saga_ttl("B1dFixture.Conc2", "b1d_conc_ledger", steps, maxConcurrency: 2)

    run_saga(ttl, :b1d_conc_ledger, fn mod, _ ->
      assert mod.run_options() == [max_concurrency: 2]
      assert {:ok, _} = Reactor.run(mod, %{}, %{}, mod.run_options())
      ledger = H.ledger(:b1d_conc_ledger)
      assert Enum.count(ledger, &match?({:run, _}, &1)) == 8
      assert H.high_water(ledger) <= 2
    end)
  end

  test "FALSIFIER: rx:maxConcurrency 8 lets the high-water mark exceed 2" do
    steps = for i <- 1..8, do: {"w#{i}", [], [async: "true", holdMs: "60"]}
    ttl = H.saga_ttl("B1dFixture.Conc8", "b1d_conc8_ledger", steps, maxConcurrency: 8)

    run_saga(ttl, :b1d_conc8_ledger, fn mod, _ ->
      assert {:ok, _} = Reactor.run(mod, %{}, %{}, mod.run_options())
      assert H.high_water(H.ledger(:b1d_conc8_ledger)) > 2
    end)
  end

  describe "middleware facts (rx:middleware)" do
    alias GgenIgniter.Telemetry.OcelEmitter

    defp run_with_sink(mod, ledger) do
      _ = ledger
      sink = OcelEmitter.new_sink()
      assert {:error, _} = Reactor.run(mod, %{}, %{ocel_sink: sink}, mod.run_options())
      for e <- OcelEmitter.drain_sink(sink), do: {e["activity"], hd(e["objects"])["id"]}
    end

    test "ocel middleware emits one OCEL event per compensate/undo callback, step names in callback order; telemetry attached" do
      ttl =
        H.saga_ttl("B1dFixture.OcelSaga", "b1d_ocel_ledger", three_steps(true),
          returnStep: "s3",
          middleware: "telemetry"
        )
        |> Kernel.<>("\nex:reactor rx:middleware \"ocel\" .\n")

      test_pid = self()
      handler = "b1d-telemetry-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler,
          [[:reactor, :run, :start], [:reactor, :run, :stop]],
          fn event, _m, _meta, _cfg -> send(test_pid, {:telemetry, event}) end,
          nil
        )

      run_saga(ttl, :b1d_ocel_ledger, fn mod, r ->
        assert File.read!(hd(r.files)) =~ ~r/middleware\(?Reactor\.Middleware\.Telemetry/
        events = run_with_sink(mod, :b1d_ocel_ledger)

        assert events == [
                 {"STEP_COMPENSATE", "s3"},
                 {"STEP_UNDO", "s1"},
                 {"STEP_UNDO", "s2"}
               ]

        assert_received {:telemetry, [:reactor, :run, :start]}
        assert_received {:telemetry, [:reactor, :run, :stop]}
      end)

      :telemetry.detach(handler)
    end

    test "FALSIFIER: omitting the middleware fact yields no OCEL events" do
      ttl =
        H.saga_ttl("B1dFixture.NoOcelSaga", "b1d_noocel_ledger", three_steps(true),
          returnStep: "s3"
        )

      run_saga(ttl, :b1d_noocel_ledger, fn mod, _ ->
        assert run_with_sink(mod, :b1d_noocel_ledger) == []
      end)
    end

    test "unknown rx:middleware value is REFUSED:REACTOR_MALFORMED with zero files" do
      ttl =
        H.saga_ttl("B1dFixture.BadMw", "b1d_badmw_ledger", three_steps(true),
          returnStep: "s3",
          middleware: "bogus"
        )

      assert {status, out, written} = H.refuse(ttl)
      assert status != 0 and out =~ "REFUSED:REACTOR_MALFORMED" and written == []
    end
  end
end
