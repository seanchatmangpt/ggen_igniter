defmodule GgenIgniter.ReviewPerspectiveCorrectnessTest do
  @moduledoc """
  Chicago-style: real structured-finding maps projected by the real
  `GgenIgniter.Review.Perspectives.Correctness.review_diff/2` into real
  `GgenIgniter.Review.Finding` structs. No doubles; assertions are on the
  returned structs and raised exceptions.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Review.Finding
  alias GgenIgniter.Review.Perspectives.Correctness

  defp raw(overrides \\ %{}) do
    Map.merge(%{surface: 1, file: "lib/a.ex", line: 3, summary: "stale manifest"}, overrides)
  end

  defp review(findings), do: Correctness.review_diff("diff text", findings: findings)

  describe "review_diff/2 (projection)" do
    test "surfaces 1..6 project to correctness findings with defaults" do
      for s <- 1..6 do
        assert [%Finding{} = f] = review([raw(%{surface: s})])
        assert f.file == "lib/a.ex"
        assert f.line == 3
        assert f.summary == "stale manifest"
        assert f.class == :correctness
        assert f.severity == :important
        assert f.perspective == :correctness
      end
    end

    test "severity map: blocker/major -> important, minor -> nit, closed set passes through" do
      sev = fn s -> hd(review([raw(%{severity: s})])).severity end
      assert sev.(:blocker) == :important
      assert sev.(:major) == :important
      assert sev.(:minor) == :nit
      assert sev.(:important) == :important
      assert sev.(:nit) == :nit
      assert sev.(:pre_existing) == :pre_existing
    end

    test "class passes through for correctness, style, diagnostic" do
      for c <- [:correctness, :style, :diagnostic] do
        assert [%{class: ^c}] = review([raw(%{class: c})])
      end
    end

    test "order is preserved" do
      out = review([raw(%{summary: "a"}), raw(%{summary: "b"}), raw(%{summary: "c"})])
      assert Enum.map(out, & &1.summary) == ["a", "b", "c"]
    end

    test "empty list and missing :findings give []" do
      assert [] == review([])
      assert [] == Correctness.review_diff("diff text", [])
    end

    test "diff_text is ignored" do
      opts = [findings: [raw()]]
      assert Correctness.review_diff("one", opts) == Correctness.review_diff("two", opts)
    end
  end

  describe "review_diff/2 (fail-closed)" do
    test "surface outside 1..6 or non-integer raises ArgumentError" do
      for bad <- [0, 7, -1, "1"] do
        assert_raise ArgumentError, ~r/unknown surface/, fn -> review([raw(%{surface: bad})]) end
      end
    end

    test "missing surface raises ArgumentError" do
      assert_raise ArgumentError, ~r/missing :surface/, fn ->
        review([Map.delete(raw(), :surface)])
      end
    end

    test "unprojectable class raises ArgumentError" do
      assert_raise ArgumentError, ~r/not projectable/, fn ->
        review([raw(%{class: :invariant})])
      end
    end

    test "unknown severity raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> review([raw(%{severity: :catastrophic})]) end
    end

    # MISMATCH: the moduledoc promises ArgumentError for a missing required key;
    # the real behavior is Map.fetch!/2 -> KeyError.
    test "MISMATCH: missing :file, :line or :summary raises KeyError (not ArgumentError)" do
      for key <- [:file, :line, :summary] do
        assert_raise KeyError, fn -> review([Map.delete(raw(), key)]) end
      end
    end

    test "one poisoned entry in a list still raises" do
      assert_raise ArgumentError, fn -> review([raw(), raw(%{surface: 9}), raw()]) end
    end
  end
end
