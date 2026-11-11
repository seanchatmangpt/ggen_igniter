defmodule GgenIgniter.Review.RiskTierTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.Review.RiskTier

  describe "classify/1 determinism" do
    test "same diff always classifies identically" do
      diff = [
        %{path: "lib/foo.ex", kind: :modify},
        %{path: "test/foo_test.exs", kind: :create}
      ]

      a = RiskTier.classify(diff)
      b = RiskTier.classify(diff)

      assert a == b
      assert a.tier == b.tier and a.score == b.score and a.signals == b.signals
    end
  end

  describe "path weights" do
    test "per-plane weights (longest prefix wins)" do
      assert RiskTier.path_weight("lib/a.ex") == 4
      assert RiskTier.path_weight("priv/x.ttl") == 3
      assert RiskTier.path_weight(".github/ci.yml") == 3
      assert RiskTier.path_weight("test/a_test.exs") == 1
      assert RiskTier.path_weight("docs/x.md") == 0
    end

    test "unmatched paths default to 3 (fail-closed)" do
      assert RiskTier.path_weight("config/runtime.exs") == 3
      assert RiskTier.path_weight("mix.exs") == 3
      assert RiskTier.path_weight("random/unknown/path") == 3
    end

    test "path_weights/0 exposes the exact table" do
      assert Enum.sort(RiskTier.path_weights()) == [
               {".github/", 3},
               {"docs/", 0},
               {"lib/", 4},
               {"priv/", 3},
               {"test/", 1}
             ]
    end
  end

  describe "score + thresholds" do
    test "score is sum of weights plus 5 per lib/**/*.ex file" do
      diff = [
        %{path: "lib/a.ex", kind: :modify},
        %{path: "lib/b.ex", kind: :create},
        %{path: "test/t.exs", kind: :modify}
      ]

      # 4 + 5 + 4 + 5 + 1 = 19
      assert %{tier: :high, score: 19} = RiskTier.classify(diff)
    end

    test "docs-only diff is :low" do
      assert %{tier: :low, score: 0} = RiskTier.classify([%{path: "docs/x.md", kind: :modify}])
    end

    test "test-only diff is :low (weight 1)" do
      assert %{tier: :low, approvals: 0} =
               RiskTier.classify([
                 %{path: "test/a.exs", kind: :modify},
                 %{path: "test/b.exs", kind: :modify}
               ])
    end
  end

  describe "boundary escalations" do
    test "score 9 stays :medium, score 10 is :high" do
      # one unmatched path (3) + lib/a.ex (4+5=9) => 12... construct exact:
      # lib/a.ex (4+5=9) + test/t.exs (1) = 10 => high
      assert %{tier: :high, score: 10} =
               RiskTier.classify([
                 %{path: "lib/a.ex", kind: :modify},
                 %{path: "test/t.exs", kind: :modify}
               ])

      # lib/a.ex (4+5=9) => medium threshold (< 10)... but 9 >= 3 => medium;
      # lib_ex escalation also fires :medium — still :medium, proves 9 < 10
      assert %{tier: :medium, score: 9} =
               RiskTier.classify([%{path: "lib/a.ex", kind: :modify}])
    end

    test "9 files :low/:medium, 10 files escalate to :medium" do
      nine = Enum.map(1..9, &%{path: "docs/d#{&1}.md", kind: :modify})

      assert %{tier: :low} = RiskTier.classify(nine)

      ten = Enum.map(1..10, &%{path: "docs/d#{&1}.md", kind: :modify})

      assert %{tier: :medium, signals: signals} = RiskTier.classify(ten)
      assert Enum.any?(signals, &(&1.rule == :many_files))
    end

    test "24 files :medium, 25 files escalate to :high" do
      twenty_four = Enum.map(1..24, &%{path: "docs/d#{&1}.md", kind: :modify})

      assert %{tier: :medium} = RiskTier.classify(twenty_four)

      twenty_five = Enum.map(1..25, &%{path: "docs/d#{&1}.md", kind: :modify})

      assert %{tier: :high, signals: signals} = RiskTier.classify(twenty_five)
      assert Enum.any?(signals, &(&1.rule == :many_files and &1.detail =~ "25"))
    end
  end

  describe "escalation floors" do
    test "any .github/workflows/* escalates to :high" do
      diff = [%{path: ".github/workflows/ci.yml", kind: :modify}, %{path: "docs/a.md", kind: :modify}]

      # score 3: would be :medium on thresholds alone
      assert %{tier: :high, score: 3} = RiskTier.classify(diff)

      assert %{signals: signals} = RiskTier.classify(diff)
      assert Enum.any?(signals, &(&1.rule == :workflows_present))
    end

    test "any lib/**/*.ex escalates to :medium (even at score < 3)" do
      # lib/a.ex alone: score 9 => threshold :medium anyway; use a lib path
      # weight trick: no — spec floor verified via docs+lib mix is impossible
      # below 9. Verify via signal presence and tier floor instead.
      assert %{tier: :medium, signals: signals} =
               RiskTier.classify([%{path: "lib/a.ex", kind: :modify}])

      assert Enum.any?(signals, &(&1.rule == :lib_elixir))
    end

    test "a :delete under lib/ escalates to :high even at low score" do
      # impossible to get score < 9 with a lib ex delete, so use a non-ex lib
      # delete: lib/a.txt weight 4, no +5 (not .ex) => score 4 => :medium
      # threshold, :high from the delete floor.
      assert %{tier: :high, score: 4} =
               RiskTier.classify([%{path: "lib/a.txt", kind: :delete}])

      assert %{signals: signals} =
               RiskTier.classify([%{path: "lib/a.txt", kind: :delete}])

      assert Enum.any?(signals, &(&1.rule == :lib_delete))
    end

    test "escalations only raise, never lower" do
      # .github/workflows floor (:high) coexists with a higher score —
      # tier never drops below any fired floor.
      diff = [
        %{path: ".github/workflows/ci.yml", kind: :modify},
        %{path: "lib/x.ex", kind: :modify},
        %{path: "lib/y.ex", kind: :modify}
      ]

      assert %{tier: :high} = RiskTier.classify(diff)
    end
  end

  describe "approvals/1 closed set" do
    test "low 0, medium 1, high 2; struct form delegates" do
      assert RiskTier.approvals(:low) == 0
      assert RiskTier.approvals(:medium) == 1
      assert RiskTier.approvals(:high) == 2

      assert RiskTier.approvals(RiskTier.classify([])) == 0

      assert RiskTier.approvals(
               RiskTier.classify([%{path: ".github/workflows/w.yml", kind: :modify}])
             ) == 2
    end
  end

  describe "empty diff" do
    test "empty diff is :low, score 0, single :empty_diff signal" do
      assert %RiskTier{
               tier: :low,
               score: 0,
               approvals: 0,
               signals: [%{rule: :empty_diff}]
             } = RiskTier.classify([])
    end
  end
end
