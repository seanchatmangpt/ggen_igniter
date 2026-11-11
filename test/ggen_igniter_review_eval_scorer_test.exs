defmodule GgenIgniter.ReviewEval.ScorerTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Chicago-style: pure adjudication over real finding maps; includes a
  mutation court — moving the finding across the tolerance boundary must
  flip the verdict, proving the line check is load-bearing (not vacuous).
  """

  alias GgenIgniter.ReviewEval.Scorer

  @thing "lib/ggen_igniter/review_eval/thing.ex"

  defp mk_case(line \\ 50, tol \\ 3) do
    %{
      "case_id" => "INC-001-abc1234",
      "location" => %{"file" => @thing, "line" => line, "line_tolerance" => tol},
      "defect" => %{"invariant" => "f/1 must add, not subtract", "surfaces" => ["review_eval"]}
    }
  end

  describe "adjudicate/2 (caught)" do
    test "finding at the exact line, exact path suffix" do
      findings = [%{"file" => @thing, "line" => 50}]

      assert %{verdict: :caught, fp_findings: 0, match_evidence: ev} =
               Scorer.adjudicate(mk_case(), findings)

      assert is_binary(ev)
    end

    test "finding at the tolerance edge (line + 3) is caught" do
      assert %{verdict: :caught} = Scorer.adjudicate(mk_case(50, 3), [%{"file" => @thing, "line" => 53}])
      assert %{verdict: :caught} = Scorer.adjudicate(mk_case(50, 3), [%{"file" => @thing, "line" => 47}])
    end

    test "suffix path match: reviewer cites basename only" do
      assert %{verdict: :caught} =
               Scorer.adjudicate(mk_case(), [%{"file" => "review_eval/thing.ex", "line" => 50}])
    end

    test "out-of-tolerance line is caught via invariant citation" do
      findings = [
        %{"file" => @thing, "line" => 500, "text" => "violates: f/1 must add, not subtract"}
      ]

      assert %{verdict: :caught, match_evidence: ev} = Scorer.adjudicate(mk_case(), findings)
      assert ev =~ "within tolerance"
    end
  end

  describe "adjudicate/2 (missed + fp)" do
    test "wrong file is a miss even on the exact line" do
      results = Scorer.adjudicate(mk_case(), [%{"file" => "lib/other/thing.ex", "line" => 50}])
      assert %{verdict: :missed, fp_findings: 1} = results
    end

    test "right file, line beyond tolerance without invariant is a miss" do
      results = Scorer.adjudicate(mk_case(50, 3), [%{"file" => @thing, "line" => 54}])
      assert %{verdict: :missed} = results
    end

    test "nil findings (reviewer error path) is a clean miss" do
      assert %{verdict: :missed, fp_findings: 0} = Scorer.adjudicate(mk_case(), nil)
    end

    test "unmatched findings count as fp, never toward caught" do
      findings = [
        %{"file" => "lib/unrelated.ex", "line" => 1},
        %{"file" => @thing, "line" => 51}
      ]

      assert %{verdict: :caught, fp_findings: 1} = Scorer.adjudicate(mk_case(), findings)
    end
  end

  describe "mutation court (tolerance check is load-bearing)" do
    test "moving the finding one line past tolerance flips caught -> missed" do
      # mutant = same finding, line mutated from the edge to edge+1
      at_edge = [%{"file" => @thing, "line" => 53}]
      past_edge = [%{"file" => @thing, "line" => 54}]

      assert %{verdict: :caught} = Scorer.adjudicate(mk_case(50, 3), at_edge)
      assert %{verdict: :missed} = Scorer.adjudicate(mk_case(50, 3), past_edge)
    end

    test "breaking the path-suffix match flips caught -> missed" do
      assert %{verdict: :caught} =
               Scorer.adjudicate(mk_case(), [%{"file" => @thing, "line" => 50}])

      assert %{verdict: :missed} =
               Scorer.adjudicate(mk_case(), [%{"file" => "lib/ggen_igniter/review_eval/THING.ex", "line" => 50}])
    end
  end

  describe "path_match?/2" do
    test "exact, suffix, and corpus-suffix forms match" do
      assert Scorer.path_match?(@thing, @thing)
      assert Scorer.path_match?("repo/" <> @thing, @thing)
      assert Scorer.path_match?("thing.ex", "lib/x/thing.ex")
      refute Scorer.path_match?("athing.ex", "lib/x/thing.ex")
      refute Scorer.path_match?(nil, @thing)
    end
  end
end
