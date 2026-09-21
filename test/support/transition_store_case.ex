defmodule GgenIgniter.TransitionStoreCase do
  @moduledoc """
  Chicago-style: the shared store contract for
  `GgenIgniter.SemanticJira.TransitionLog.Store` implementations. A test
  module `use`s this case and supplies a `setup` that returns `%{store: spec}`
  (a directory for the file store, a `%PostgresStore{}` for Postgres). Every
  assertion is state-based against the real backend through the public
  `GgenIgniter.SemanticJira.TransitionLog` facade -- no doubles -- so the file
  and Postgres stores are held to the identical invariants.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias GgenIgniter.SemanticJira
      alias GgenIgniter.SemanticJira.TransitionLog

      import GgenIgniter.TransitionStoreCase, only: [store_contract: 0]

      defp event(i) do
        %{
          "kind" => "standing_transition_event",
          "identity" => "X#{i}",
          "from" => "UNKNOWN",
          "to" => "ALIVE",
          "receipt_digest" => "sha256:" <> String.pad_leading("#{i}", 64, "0"),
          "authority" => "NONE"
        }
      end
    end
  end

  @doc """
  Expands to the shared store-contract tests. Invoke it AFTER the test module's
  own `@moduletag`s (ExUnit reads module tags when each test is registered).
  """
  defmacro store_contract do
    quote do
      alias GgenIgniter.SemanticJira, warn: false
      alias GgenIgniter.SemanticJira.TransitionLog, warn: false

      unquote(empty_log_tests())
      unquote(append_tests())
      unquote(expected_seq_tests())
      unquote(concurrent_writer_tests())
    end
  end

  defp empty_log_tests do
    quote do
      describe "store contract: empty log" do
        test "reads as empty", %{store: store} do
          assert TransitionLog.read(store) == []
          assert TransitionLog.head(store) == 0
          assert Enum.to_list(TransitionLog.stream(store)) == []
          assert TransitionLog.get(store, "sha256:" <> String.duplicate("0", 64)) == :error
        end
      end
    end
  end

  defp append_tests do
    quote do
      describe "store contract: append/3" do
        test "assigns contiguous seq, stamps event_digest, reads ordered by seq", %{store: store} do
          stored =
            for i <- 1..5 do
              assert {:ok, ev, :appended} = TransitionLog.append(store, event(i))
              ev
            end

          assert Enum.map(stored, & &1["seq"]) == [1, 2, 3, 4, 5]

          assert Enum.all?(stored, fn ev ->
                   ev["event_digest"] ==
                     SemanticJira.digest(Map.drop(ev, ["seq", "event_digest"]))
                 end)

          assert TransitionLog.read(store) == stored
          assert Enum.to_list(TransitionLog.stream(store)) == stored
          assert TransitionLog.head(store) == 5
        end

        test "is idempotent per event digest", %{store: store} do
          assert {:ok, first, :appended} = TransitionLog.append(store, event(1))
          assert {:ok, ^first, :already_recorded} = TransitionLog.append(store, event(1))
          assert {:ok, _, :appended} = TransitionLog.append(store, event(2))
          assert {:ok, ^first, :already_recorded} = TransitionLog.append(store, event(1))
          assert length(TransitionLog.read(store)) == 2
          assert TransitionLog.head(store) == 2
        end

        test "a caller-supplied seq never reaches the stored event or its digest",
             %{store: store} do
          assert {:ok, a, :appended} = TransitionLog.append(store, event(1))

          assert {:ok, ^a, :already_recorded} =
                   TransitionLog.append(store, Map.put(event(1), "seq", 99))

          assert a["seq"] == 1
        end

        test "get/2 returns the stored event by event_digest", %{store: store} do
          {:ok, a, :appended} = TransitionLog.append(store, event(1))
          {:ok, b, :appended} = TransitionLog.append(store, event(2))
          assert TransitionLog.get(store, a["event_digest"]) == {:ok, a}
          assert TransitionLog.get(store, b["event_digest"]) == {:ok, b}
          assert TransitionLog.get(store, "sha256:" <> String.duplicate("f", 64)) == :error
        end
      end
    end
  end

  defp expected_seq_tests do
    quote do
      describe "store contract: optimistic concurrency (expected_seq)" do
        test "claims exactly the expected seq", %{store: store} do
          assert {:ok, %{"seq" => 1}, :appended} =
                   TransitionLog.append(store, event(1), expected_seq: 1)

          assert {:ok, %{"seq" => 2}, :appended} =
                   TransitionLog.append(store, event(2), expected_seq: 2)
        end

        test "a stale expectation is refused and stores nothing", %{store: store} do
          {:ok, _, :appended} = TransitionLog.append(store, event(1))
          {:ok, _, :appended} = TransitionLog.append(store, event(2))

          assert {:error, {:seq_conflict, 2}} =
                   TransitionLog.append(store, event(3), expected_seq: 2)

          assert {:error, {:seq_conflict, 2}} =
                   TransitionLog.append(store, event(3), expected_seq: 9)

          assert length(TransitionLog.read(store)) == 2
          assert TransitionLog.head(store) == 2

          # the refused event is not poisoned: it can still be appended
          assert {:ok, %{"seq" => 3}, :appended} =
                   TransitionLog.append(store, event(3), expected_seq: 3)
        end

        test "an already-recorded event stays idempotent under a stale expectation",
             %{store: store} do
          {:ok, a, :appended} = TransitionLog.append(store, event(1))

          assert {:ok, ^a, :already_recorded} =
                   TransitionLog.append(store, event(1), expected_seq: 7)
        end

        test "of N concurrent writers expecting the same seq exactly one wins", %{store: store} do
          results =
            1..12
            |> Task.async_stream(&TransitionLog.append(store, event(&1), expected_seq: 1),
              max_concurrency: 12,
              ordered: false,
              timeout: 60_000
            )
            |> Enum.map(fn {:ok, r} -> r end)

          assert Enum.count(results, &match?({:ok, %{"seq" => 1}, :appended}, &1)) == 1
          assert Enum.count(results, &match?({:error, {:seq_conflict, 1}}, &1)) == 11
          assert [%{"seq" => 1}] = TransitionLog.read(store)
        end
      end
    end
  end

  defp concurrent_writer_tests do
    quote do
      describe "store contract: concurrent writers" do
        test "distinct events from many processes get distinct contiguous seqs", %{store: store} do
          results =
            1..40
            |> Task.async_stream(&TransitionLog.append(store, event(&1)),
              max_concurrency: 40,
              ordered: false,
              timeout: 60_000
            )
            |> Enum.map(fn {:ok, r} -> r end)

          assert Enum.all?(results, &match?({:ok, _, :appended}, &1))

          read = TransitionLog.read(store)
          assert Enum.map(read, & &1["seq"]) == Enum.to_list(1..40)
          assert read |> Enum.map(& &1["event_digest"]) |> Enum.uniq() |> length() == 40

          assert read |> Enum.map(& &1["identity"]) |> Enum.sort() ==
                   1..40 |> Enum.map(&"X#{&1}") |> Enum.sort()
        end

        test "the same event from many processes is stored exactly once", %{store: store} do
          results =
            1..30
            |> Task.async_stream(fn _ -> TransitionLog.append(store, event(1)) end,
              max_concurrency: 30,
              ordered: false,
              timeout: 60_000
            )
            |> Enum.map(fn {:ok, r} -> r end)

          assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 1
          assert Enum.count(results, &match?({:ok, _, :already_recorded}, &1)) == 29
          assert [stored] = TransitionLog.read(store)
          assert Enum.all?(results, fn {:ok, ev, _} -> ev == stored end)
        end

        test "duplicates interleaved with distinct events lose nothing", %{store: store} do
          jobs = Enum.flat_map(1..15, &[&1, &1])

          jobs
          |> Task.async_stream(&TransitionLog.append(store, event(&1)),
            max_concurrency: 30,
            ordered: false,
            timeout: 60_000
          )
          |> Enum.each(fn {:ok, r} ->
            assert {:ok, _, s} = r
            assert s in [:appended, :already_recorded]
          end)

          read = TransitionLog.read(store)
          assert Enum.map(read, & &1["seq"]) == Enum.to_list(1..15)
        end
      end
    end
  end
end
