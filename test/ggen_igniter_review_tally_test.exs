defmodule GgenIgniterReviewTallyTest do
  @moduledoc """
  Chicago-style: real Finding structs, real injected verifier FUNCTIONS (real
  collaborators, not doubles), real tmp-dir persistence via Review.run/2, no
  mocks or patches anywhere.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Review
  alias GgenIgniter.Review.{Finding, Tally, Verifier}

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_review_tally_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  defp finding(class \\ :correctness) do
    Finding.new(
      file: "lib/foo.ex",
      line: 7,
      class: class,
      severity: :important,
      summary: "surface 2 undo/4 must restore pre_run_hash",
      perspective: :correctness
    )
  end

  # --- Verifier.vote/2 --------------------------------------------------

  describe "Verifier.vote/2" do
    test "M=3: 2-0 with an abstain sustains (majority AND sustain > reject)" do
      verifiers = [
        fn _ -> :sustain end,
        fn _ -> :sustain end,
        fn _ -> :abstain end
      ]

      assert {:sustained, _} = Verifier.vote(finding(), verifiers)
    end

    test "M=3: 2-1 sustains" do
      verifiers = [fn _ -> :sustain end, fn _ -> :sustain end, fn _ -> :reject end]
      assert {:sustained, _} = Verifier.vote(finding(), verifiers)
    end

    test "M=3: 1-1-1 tie rejects (sustain not > reject)" do
      verifiers = [fn _ -> :sustain end, fn _ -> :reject end, fn _ -> :abstain end]
      assert {:rejected, _} = Verifier.vote(finding(), verifiers)
    end

    test "M=3: all-abstain rejects (fail closed)" do
      assert {:rejected, _} = Verifier.vote(finding(), Verifier.pad_default([], 3))
    end

    test "M=2: floor(M/2)+1 = 2 sustain needed; 1-1 rejects" do
      assert {:rejected, _} = Verifier.vote(finding(), [fn _ -> :sustain end, fn _ -> :reject end])
    end

    test "M=1: single sustain sustains; single reject rejects" do
      assert {:sustained, _} = Verifier.vote(finding(), [fn _ -> :sustain end])
      assert {:rejected, _} = Verifier.vote(finding(), [fn _ -> :reject end])
    end
  end

  # --- Tally.tally/2 ----------------------------------------------------

  describe "Tally.tally/2" do
    test "survivors are :posted, others :suppressed, both sorted" do
      f1 = finding()
      f2 = finding()

      f2 =
        Finding.new(
          file: "lib/bar.ex",
          line: 2,
          class: :invariant,
          severity: :important,
          summary: "worktree add is banned",
          perspective: :invariants
        )

      verifiers = [
        fn f -> if f.file == "lib/bar.ex", do: :sustain, else: :reject end,
        fn f -> if f.file == "lib/bar.ex", do: :sustain, else: :abstain end,
        fn _ -> :abstain end
      ]

      result = Tally.tally([f1, f2], verifiers)

      # bar: 2 sustain 0 reject -> sustained; foo: 0 sustain 1 reject -> rejected
      assert [%{file: "lib/bar.ex"}] = result.posted
      assert [%{file: "lib/foo.ex"}] = result.suppressed
    end

    test "rejecting verifiers suppress everything" do
      result = Tally.tally([finding()], [fn _ -> :reject end, fn _ -> :reject end, fn _ -> :sustain end])
      assert %{posted: [], suppressed: [_]} = result
    end
  end

  # --- Review.run/2 end to end ------------------------------------------

  describe "Review.run/2" do
    test "drops :style and :diagnostic pre-vote — they never reach verifiers" do
      called = :counters.new(1, [:atomics])

      # Empty diff: the ONLY candidate finding is the structured style note,
      # so any verifier call means the drop did not happen.
      {:ok, doc} =
        Review.run("",
          verifiers: [
            fn _ -> :counters.put(called, 1, :counters.get(called, 1) + 1) && :reject end,
            fn _ -> :reject end,
            fn _ -> :reject end
          ],
          findings: [
            %{
              file: "lib/foo.ex",
              line: 2,
              class: :style,
              severity: :nit,
              summary: "a style note",
              surface: 5
            }
          ],
          persist: false
        )

      assert doc.posted == [] and doc.suppressed == []
      # 0 verifier calls: style was dropped before the vote.
      assert :counters.get(called, 1) == 0
    end

    test "perspectives fan out over the real diff: invariant + chicago hits, epoch unattributed" do
      diff = """
      diff --git a/lib/bad.ex b/lib/bad.ex
      --- a/lib/bad.ex
      +++ b/lib/bad.ex
      @@ -1,2 +1,5 @@
      +defmodule Bad do
      +  git reset --hard
      +  import Mox
      +end
      """

      {:ok, doc} =
        Review.run(diff,
          persist: false,
          verifiers: [fn _ -> :sustain end, fn _ -> :sustain end, fn _ -> :sustain end]
        )

      classes = Enum.frequencies_by(doc.posted ++ doc.suppressed, & &1.class)

      assert classes[:invariant] == 1
      assert classes[:chicago_test] == 1
      assert classes[:epoch_law] == 1
    end

    test "attributed lib/ hunks produce no epoch_law finding" do
      diff = """
      diff --git a/lib/attributed.ex b/lib/attributed.ex
      --- a/lib/attributed.ex
      +++ b/lib/attributed.ex
      @@ -1 +1,2 @@
      +:ok
      """

      {:ok, doc} =
        Review.run(diff,
          persist: false,
          attributions: %{"lib/attributed.ex" => "HANDWRITTEN.md row 4"},
          verifiers: [fn _ -> :sustain end, fn _ -> :sustain end, fn _ -> :sustain end]
        )

      refute Enum.any?(doc.posted, &(&1.class == :epoch_law))
    end

    test "deterministic ids: same observation twice dedupes to one finding" do
      diff = """
      diff --git a/lib/dup.ex b/lib/dup.ex
      --- a/lib/dup.ex
      +++ b/lib/dup.ex
      @@ -1 +1,2 @@
      +git worktree add ../wt
      """

      {:ok, doc} = Review.run(diff, persist: false, verifier_count: 3)

      # invariants + epoch_law both flag; ids are content-derived so counts
      # are stable, and no two surviving findings share an id.
      all = doc.posted ++ doc.suppressed
      assert all != []
      assert length(all) == length(Enum.uniq_by(all, & &1.id))
    end

    test "no injected verifiers -> everything rejected (fail closed)" do
      diff = """
      diff --git a/lib/x.ex b/lib/x.ex
      --- a/lib/x.ex
      +++ b/lib/x.ex
      @@ -1 +1,2 @@
      +git reset --hard
      """

      {:ok, doc} = Review.run(diff, persist: false)
      assert doc.posted == []
      # invariant (git reset --hard) + epoch_law (unattributed lib/**/*.ex hunk)
      assert length(doc.suppressed) == 2
    end
  end
end
