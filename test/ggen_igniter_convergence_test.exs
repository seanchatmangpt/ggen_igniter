defmodule GgenIgniterConvergenceTest do
  @moduledoc "Chicago-style: real tmp dirs under System.tmp_dir!(), real unified-diff text, real JSONL rounds.jsonl on disk, real Digest.sha256 ids, real GgenIgniter.Receipt structs — no mocks. async: false because reviewer fns message the test process and each test owns its own tmp dir anyway."
  use ExUnit.Case, async: false

  alias GgenIgniter.Convergence
  alias GgenIgniter.Convergence.Classes
  alias GgenIgniter.Convergence.Hunks
  alias GgenIgniter.ReviewStore

  @diff_text """
  diff --git a/lib/foo.ex b/lib/foo.ex
  index 111..222 100644
  --- a/lib/foo.ex
  +++ b/lib/foo.ex
  @@ -1,3 +1,4 @@
   defmodule Foo do
  +  def broken, do: :oops
   end
  diff --git a/lib/bar.ex b/lib/bar.ex
  index 333..444 100644
  --- a/lib/bar.ex
  +++ b/lib/bar.ex
  @@ -10,3 +10,3 @@
  -  def old, do: 1
  +  def new, do: 2
  """

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "convergence-test-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  defp finding(file, hunk_id, class, msg \\ "fix me") do
    %{file: file, hunk_id: hunk_id, class: class, message: msg}
  end

  defp hunk_ids(diff) do
    diff |> Hunks.parse_unified() |> Map.new(fn h -> {h.file, h.hunk_id} end)
  end

  describe "decide/2,3" do
    test "no findings -> pass with rounds_to_pass written once" do
      {:ok, :pass, record} = Convergence.decide(2, [])
      assert record.state == :round_passed
      assert record.rounds_to_pass == 2
      assert record.decision == :pass
    end

    test "findings at cap -> escalate with receipt_hash" do
      {:ok, :escalate, record} =
        Convergence.decide(3, [finding("a.ex", "h1", :naming)], max_rounds: 3)

      assert record.state == :review_escalated
      assert String.starts_with?(record.receipt_hash, "sha256:")
      assert record.rounds_to_pass == nil
    end

    test "findings under cap -> continue (fixed advances)" do
      {:ok, :continue, record} =
        Convergence.decide(1, [finding("a.ex", "h1", :naming)], max_rounds: 3)

      assert record.state == :round_fixed_advances
      assert record.decision == :continue
    end

    test "cap <= 0 refuses via escalation shape, never a bypass pass" do
      {:ok, decision, record} = Convergence.decide(1, [], max_rounds: 0)
      assert decision == :escalate
      assert record.state == :review_escalated
    end

    test "total on garbage input — typed record, no raise" do
      assert {:ok, :escalate, record} = Convergence.decide("nope", :worse)
      assert match?({:bad_invocation, _}, record.refusal)
    end

    test "findings_carried without findings_new: carried findings NOT misrecorded as new (R1-4)" do
      carried = [finding("a.ex", "h1", :naming), finding("b.ex", "h2", :formatting)]
      genuinely_new = finding("c.ex", "h3", :dead_code)

      {:ok, :continue, record} =
        Convergence.decide(2, carried ++ [genuinely_new],
          max_rounds: 3,
          findings_carried: carried
        )

      assert record.findings_carried == carried
      assert record.findings_new == [genuinely_new]
    end
  end

  describe "Hunks.parse_unified/1" do
    test "parses both files' hunks with stable sha256 hunk_ids" do
      hunks = Hunks.parse_unified(@diff_text)
      assert length(hunks) == 2

      assert Enum.all?(hunks, fn h ->
               String.starts_with?(h.hunk_id, "sha256:") and is_binary(h.file)
             end)

      ids = hunk_ids(@diff_text)
      assert ids == hunk_ids(@diff_text)
    end

    test "changing a hunk changes its id; identical hunk keeps id" do
      changed =
        String.replace(@diff_text, "def broken, do: :oops", "def broken, do: :fixed")

      old_ids = hunk_ids(@diff_text)
      new_ids = hunk_ids(changed)

      assert new_ids["lib/foo.ex"] != old_ids["lib/foo.ex"]
      assert new_ids["lib/bar.ex"] == old_ids["lib/bar.ex"]
    end

    test "nil and empty diffs parse to []" do
      assert Hunks.parse_unified(nil) == []
      assert Hunks.parse_unified("") == []
    end
  end

  describe "Classes" do
    test "apply_class_fix closes all same-class findings across files" do
      findings = [
        finding("a.ex", "h1", :formatting),
        finding("b.ex", "h2", :formatting),
        finding("c.ex", "h3", :naming)
      ]

      assert {:ok, fixed, 2} = Classes.apply_class_fix(findings, :formatting)

      fixed_formatting = Enum.filter(fixed, &(&1.class == :formatting))
      assert length(fixed_formatting) == 2
      assert Enum.all?(fixed_formatting, &(&1.reason == "class_fixed"))
      assert Enum.find(fixed, &(&1.class == :naming)) |> Map.get(:reason) == nil
    end

    test "typo'd class is a refusal, not a bypass" do
      assert {:error, {:unknown_class, :formating}} =
               Classes.apply_class_fix([], :formating)

      assert :formating not in Classes.classes()
    end
  end

  describe "run/2 loop driver" do
    test "passes on round 1 when reviewer finds nothing; writes rounds + summary" do
      base = tmp_dir()
      reviewer = fn _input -> [] end

      {:ok, result} =
        Convergence.run(%{sha: "sha-pass", base_dir: base, diff: @diff_text},
          reviewer: reviewer
        )

      assert result.state == :round_passed
      assert result.rounds_executed == 1
      assert result.rounds_to_pass == 1

      rounds = ReviewStore.read_rounds(base, "sha-pass")
      assert length(rounds) == 1
      assert hd(rounds)["state"] == "round_passed"
      assert %{"final_state" => "round_passed"} = ReviewStore.read_summary(base, "sha-pass")
      assert File.exists?(ReviewStore.diff_path(base, "sha-pass", 1))
    end

    test "cap blocks round-4 dispatch — reviewer raises if ever called a 4th time" do
      base = tmp_dir()
      test_pid = self()

      reviewer = fn input ->
        send(test_pid, {:reviewer_called, input.round})
        # Always a NEW finding (new hunk each round via unique message).
        [finding("a.ex", "hunk-#{input.round}", :naming)]
      end

      {:ok, result} =
        Convergence.run(%{sha: "sha-cap", base_dir: base, diff: @diff_text},
          reviewer: reviewer,
          max_rounds: 3
        )

      assert result.state == :review_escalated
      called_rounds =
        collect_calls([]) |> Enum.map(fn {:reviewer_called, r} -> r end)

      assert called_rounds == [1, 2, 3]

      rounds = ReviewStore.read_rounds(base, "sha-cap")
      assert length(rounds) == 3
      assert List.last(rounds)["state"] == "review_escalated"
      assert %{"final_state" => "review_escalated"} = ReviewStore.read_summary(base, "sha-cap")
    end

    test "diff-only re-review: carried findings not re-posted to reviewer" do
      base = tmp_dir()
      ids = hunk_ids(@diff_text)
      test_pid = self()

      reviewer = fn input ->
        send(test_pid, {:reviewed, input.round, Enum.map(input.hunks, & &1.hunk_id)})

        case input.round do
          1 -> [finding("lib/foo.ex", ids["lib/foo.ex"], :naming, "round1")]
          _ -> []
        end
      end

      {:ok, result} =
        Convergence.run(%{sha: "sha-diff", base_dir: base, diff: @diff_text},
          reviewer: reviewer
        )

      assert [%{round: 1, decision: :continue}, round2] = result.all_records
      assert round2.state == :round_passed
      assert round2.rounds_to_pass == 2

      # Round 1: full scope, both hunks. Round 2: diff-only, ZERO hunks (the
      # diff is settled) — the round-1 finding is carried in the round-2
      # record, never re-posted as a reviewer finding.
      calls = collect_calls([])
      assert [{:reviewed, 1, ids_list}, {:reviewed, 2, []} | _] = calls

      assert ids_list == [ids["lib/foo.ex"], ids["lib/bar.ex"]]

      rounds = ReviewStore.read_rounds(base, "sha-diff")
      assert hd(rounds)["reviewed_scope"] == "full"
      assert List.last(rounds)["decision"] == "pass"

      # The round-1 finding was never re-posted: round 2 reviews zero hunks
      # and the finding closes via the class-fix pass (reason class_fixed).
      assert Enum.any?(
               List.last(rounds)["findings_cleared"],
               &(&1["reason"] == "class_fixed")
             )
    end

    test "hunk-less open findings are carried, never silently dropped (R1-2)" do
      base = tmp_dir()
      ids = hunk_ids(@diff_text)
      test_pid = self()

      reviewer = fn input ->
        send(test_pid, {:reviewed, input.round, input.hunks})
        []
      end

      initial = [
        finding("lib/foo.ex", ids["lib/foo.ex"], :naming, "hunk still present"),
        finding("lib/gone.ex", "sha256:vanished-hunk", :naming, "hunk disappeared"),
        %{file: "lib/loose.ex", class: :naming, message: "no hunk_id at all"}
      ]

      {:ok, result} =
        Convergence.run(%{sha: "sha-hunkless", base_dir: base, diff: @diff_text},
          reviewer: reviewer,
          initial_findings: initial,
          max_rounds: 2
        )

      r1 = hd(result.all_records)

      # Still-present hunk -> carried. Hunk-less -> carried (conservative:
      # no hunk to disappear, so it is never silently cleared).
      assert Enum.any?(r1.findings_carried, &(&1.hunk_id == ids["lib/foo.ex"]))
      assert %{file: "lib/loose.ex"} in Enum.map(r1.findings_carried, &Map.take(&1, [:file]))
      assert r1.findings_cleared == [
               finding("lib/gone.ex", "sha256:vanished-hunk", :naming, "hunk disappeared")
             ]

      # The hunk-less finding stays open in findings_open — not dropped.
      assert Enum.any?(r1.findings_open, &(&1.file == "lib/loose.ex"))
    end

    test "class fix closes cross-file instances; class_fixed recorded globally" do
      base = tmp_dir()
      ids = hunk_ids(@diff_text)

      reviewer = fn
        %{round: 1} ->
          [
            finding("lib/foo.ex", ids["lib/foo.ex"], :formatting),
            finding("lib/bar.ex", ids["lib/bar.ex"], :formatting)
          ]

        _ ->
          []
      end

      {:ok, result} =
        Convergence.run(%{sha: "sha-class", base_dir: base, diff: @diff_text},
          reviewer: reviewer,
          max_rounds: 2
        )

      assert result.state == :round_passed
      assert result.rounds_to_pass == 2
      assert result.class_fixed_globally == [:formatting]

      rounds = ReviewStore.read_rounds(base, "sha-class")
      [r1, r2] = rounds
      assert length(r1["findings_new"]) == 2
      assert Enum.all?(r2["findings_cleared"], &(&1["reason"] == "class_fixed"))
      assert r2["class_fixed_globally"] == ["formatting"]
    end

    test "rounds_to_pass is written exactly once across the run" do
      base = tmp_dir()
      ids = hunk_ids(@diff_text)

      reviewer = fn
        %{round: 1} -> [finding("lib/foo.ex", ids["lib/foo.ex"], :naming)]
        _ -> []
      end

      {:ok, result} =
        Convergence.run(%{sha: "sha-rtp", base_dir: base, diff: @diff_text}, reviewer: reviewer)

      assert result.rounds_to_pass == 2
      rounds = ReviewStore.read_rounds(base, "sha-rtp")
      rtp = Enum.map(rounds, & &1["rounds_to_pass"])
      assert Enum.count(rtp, &is_integer/1) == 1
    end

    test "escalation record carries a real receipt wrapper hash" do
      base = tmp_dir()

      reviewer = fn %{round: r} -> [finding("a.ex", "hunk-#{r}", :test_gap)] end

      {:ok, result} =
        Convergence.run(%{sha: "sha-esc", base_dir: base, diff: nil},
          reviewer: reviewer,
          max_rounds: 2
        )

      assert result.state == :review_escalated
      assert String.starts_with?(result.receipt_hash, "sha256:")
      assert result.reviewed_scope == :diff_only
    end
  end

  describe "Critic (default deterministic reviewer)" do
    test "flags trailing whitespace, IO.inspect, and doc-less defmodule; clean diff is silent" do
      dirty = """
      diff --git a/lib/dirty.ex b/lib/dirty.ex
      index 111..222 100644
      --- a/lib/dirty.ex
      +++ b/lib/dirty.ex
      @@ -1,3 +1,5 @@
      +defmodule Dirty do
      +  def x, do: IO.inspect(:oops)
      +  def y, do: :ok
      +  def z, do: :ok   
      """

      hunks = Hunks.parse_unified(dirty <> "\n")
      assert [%{hunk_id: id}] = hunks

      findings = Convergence.Critic.review(%{scope: :full, hunks: hunks, round: 1})

      classes = Enum.map(findings, & &1.class) |> Enum.sort()
      assert classes == [:dead_code, :formatting, :missing_doc]
      assert Enum.all?(findings, &(&1.file == "lib/dirty.ex" and &1.hunk_id == id))
    end

    test "added @moduledoc earlier in the hunk suppresses missing_doc" do
      docd = """
      diff --git a/lib/docd.ex b/lib/docd.ex
      index 111..222 100644
      --- a/lib/docd.ex
      +++ b/lib/docd.ex
      @@ -1,3 +1,4 @@
      +@moduledoc "docs"
      +defmodule Docd do
      +  def x, do: :ok
      +  def y, do: :ok
      """

      findings = Convergence.Critic.review(%{scope: :full, hunks: Hunks.parse_unified(docd <> "\n"), round: 1})
      refute Enum.any?(findings, &(&1.class == :missing_doc))
    end

    test "run/2 without a reviewer uses the critic: dirty diff escalates, clean diff passes" do
      base_dirty = tmp_dir()
      dirty_diff = String.replace(@diff_text, "def broken, do: :oops", "def broken, do: IO.inspect(:x) ")

      {:ok, result} =
        Convergence.run(%{sha: "sha-critic-dirty", base_dir: base_dirty, diff: dirty_diff}, [])

      # Round 1: the critic fires (dead_code + formatting) -> :continue, not a
      # round-1 pass. Round 2: class-fix pass closes both classes, clean
      # diff-only re-review -> :round_passed.
      assert result.state == :round_passed
      assert result.rounds_executed == 2

      [r1, _r2] = result.all_records
      assert r1.decision == :continue
      assert Enum.any?(r1.findings_new, &(&1.class in [:dead_code, :formatting]))

      base_clean = tmp_dir()
      clean_diff = String.replace(@diff_text, "def broken, do: :oops", "def fine, do: :ok")

      {:ok, result} =
        Convergence.run(%{sha: "sha-critic-clean", base_dir: base_clean, diff: clean_diff}, [])

      assert result.state == :round_passed
      assert result.rounds_to_pass == 1
    end
  end

  defp collect_calls(acc) do
    receive do
      msg -> collect_calls(acc ++ [msg])
    after
      0 -> acc
    end
  end
end
