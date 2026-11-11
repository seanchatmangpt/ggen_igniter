defmodule GgenIgniterReviewStoreTest do
  @moduledoc """
  Chicago-style: real tmp dirs, real File reads/writes, real Jason encoding —
  the store is asserted through what actually lands on disk and comes back.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Review.{Finding, Store}

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_review_store_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    Process.put(:review_store_tmp, tmp_dir)
    {:ok, tmp_dir: tmp_dir}
  end

  defp finding(line, class \\ :correctness) do
    Finding.new(
      file: "lib/foo.ex",
      line: line,
      class: class,
      severity: :important,
      summary: "surface 2: undo/4 must restore pre_run_hash",
      perspective: :correctness
    )
  end

  describe "save/3 + load/3" do
    test "writes findings.json and rounds.jsonl; load returns the round doc" do
      f = finding(7)
      dir = Store.save(%{round: 1, posted: [f], suppressed: []}, "rev-1", tmp())

      assert String.starts_with?(dir, tmp())
      assert File.exists?(Path.join(dir, "findings.json"))
      assert File.exists?(Path.join(dir, "rounds.jsonl"))

      {:ok, doc} = Store.load("rev-1", 1, tmp())
      assert doc.round == 1
      assert [%Finding{} = pf] = doc.posted
      assert pf.id == f.id
      assert pf.line == 7
      assert doc.suppressed == []
    end

    test "second round overwrites findings.json but APPENDS to rounds.jsonl" do
      f1 = finding(7)
      f2 = finding(8, :invariant)

      Store.save(%{round: 1, posted: [f1], suppressed: []}, "rev-2", tmp())
      Store.save(%{round: 2, posted: [], suppressed: [f2]}, "rev-2", tmp())

      {:ok, doc} = Store.load("rev-2", 2, tmp())
      assert doc.posted == [] and length(doc.suppressed) == 1

      {:ok, history} = Store.load_history("rev-2", tmp())
      assert Enum.map(history, & &1.round) == [1, 2]

      lines = File.read!(Path.join(dir("rev-2"), "rounds.jsonl")) |> String.split("\n", trim: true)
      assert length(lines) == 2

      # findings.json holds ONLY the latest round
      {:ok, latest} = Jason.decode(File.read!(Path.join(dir("rev-2"), "findings.json")))
      assert Map.get(latest, "round") == 2
    end

    test "load/3 distinguishes :not_found from :corrupt (bad JSON)" do
      Store.save(%{round: 1, posted: [], suppressed: []}, "rev-3", tmp())
      File.write!(Path.join(dir("rev-3"), "findings.json"), "{not json")

      assert {:error, :not_found} = Store.load("rev-404", 1, tmp())
      assert {:error, :corrupt} = Store.load("rev-3", 1, tmp())
    end

    test "load/3 :not_found when the round does not match the stored doc" do
      Store.save(%{round: 1, posted: [], suppressed: []}, "rev-4", tmp())
      assert {:error, :not_found} = Store.load("rev-4", 2, tmp())
    end

    test "load_history/2 :corrupt on a bad line, :not_found when absent" do
      assert {:error, :not_found} = Store.load_history("rev-missing", tmp())

      Store.save(%{round: 1, posted: [], suppressed: []}, "rev-5", tmp())
      :ok = File.write(Path.join(dir("rev-5"), "rounds.jsonl"), "garbage line\n", [:append])

      assert {:error, :corrupt} = Store.load_history("rev-5", tmp())
    end
  end

  defp tmp, do: Process.get(:review_store_tmp)

  defp dir(review_id), do: Store.review_dir(review_id, tmp())
end
