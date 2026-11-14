defmodule GgenIgniterReviewFilterSuppressionTest do
  @moduledoc """
  Chicago-style: real Finding structs and real round docs (the rounds.jsonl
  shape as actually persisted by Review.Store), no mocks — suppression laws
  asserted on returned state.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Review.{Filter, Finding}

  defp finding(file, line, class, severity \\ :important) do
    Finding.new(
      file: file,
      line: line,
      class: class,
      severity: severity,
      summary: "undo/4 must restore pre_run_hash",
      perspective: :correctness
    )
  end

  defp entry(f, status, round, consec) do
    m = Finding.to_map(f)

    m
    |> Map.put("status", Atom.to_string(status))
    |> Map.put("first_seen_round", round)
    |> Map.put("consecutive_suppressed", consec)
  end

  # --- law 1: repeat of a posted key is suppressed ----------------------

  describe "suppress_repeats/3" do
    test "a key posted in the latest prior round is suppressed this round" do
      f = finding("lib/foo.ex", 7, :correctness)
      prior = %{round: 1, findings: [entry(f, :posted, 1, 0)]}

      [out] = Filter.suppress_repeats([f], [prior], 2)

      assert out.status == :suppressed
      assert out.first_seen_round == 1
      assert out.consecutive_suppressed == 1
      refute out.escalation_candidate
    end

    test "a key suppressed with an ACTIVE chain in the latest round continues the chain" do
      f = finding("lib/foo.ex", 7, :correctness)

      prior = %{round: 1, findings: [entry(f, :suppressed, 1, 2)]}
      [out] = Filter.suppress_repeats([f], [prior], 2)

      assert out.status == :suppressed
      assert out.first_seen_round == 1, "first_seen_round copied through the chain"
      assert out.consecutive_suppressed == 3
      assert out.escalation_candidate
    end

    test "a key suppressed last round with consec 0 (no chain) is fresh" do
      f = finding("lib/foo.ex", 7, :correctness)

      prior = %{round: 1, findings: [entry(f, :suppressed, 1, 0)]}
      [out] = Filter.suppress_repeats([f], [prior], 2)

      assert out.status == :posted
      assert out.consecutive_suppressed == 0
    end

    test "empty history: everything posted, first_seen_round = current round" do
      f = finding("lib/foo.ex", 7, :correctness)
      [out] = Filter.suppress_repeats([f], [], 4)
      assert out.status == :posted
      assert out.first_seen_round == 4
    end

    # --- law 2: first_seen_round copied through suppression chains ------

    test "consecutive suppression accumulates and escalates at >= 3" do
      f = finding("lib/foo.ex", 7, :correctness)

      prior = %{round: 3, findings: [entry(f, :suppressed, 1, 2)]}
      [out] = Filter.suppress_repeats([f], [prior], 4)

      assert out.status == :suppressed
      assert out.first_seen_round == 1, "first_seen_round copied, not reset"
      assert out.consecutive_suppressed == 3
      assert out.escalation_candidate
    end

    test "exactly 2 consecutive is not yet an escalation candidate" do
      f = finding("lib/foo.ex", 7, :correctness)
      prior = %{round: 2, findings: [entry(f, :suppressed, 1, 1)]}
      [out] = Filter.suppress_repeats([f], [prior], 3)
      refute out.escalation_candidate
      assert out.consecutive_suppressed == 2
    end

    # --- law 3: latest prior round only ---------------------------------

    test "only the LATEST prior round matters: key absent from the latest round re-posts" do
      f = finding("lib/foo.ex", 7, :correctness)

      history = [
        %{round: 1, findings: [entry(f, :posted, 1, 0)]},
        %{round: 3, findings: []}
      ]

      [out] = Filter.suppress_repeats([f], history, 4)
      assert out.status == :posted
      assert out.consecutive_suppressed == 0
    end

    test "history entries that are for a FUTURE round never suppress" do
      f = finding("lib/foo.ex", 7, :correctness)
      prior = %{round: 9, findings: [entry(f, :posted, 9, 0)]}
      [out] = Filter.suppress_repeats([f], [prior], 2)
      assert out.status == :posted
    end

    # --- law 4: different-line pre_existing never suppressed ------------

    test "a different-line pre_existing finding is never suppressed even when a same-file key was posted" do
      posted = finding("lib/foo.ex", 7, :correctness)
      now = finding("lib/foo.ex", 42, :correctness, :pre_existing)

      prior = %{round: 1, findings: [entry(posted, :posted, 1, 0)]}
      [out] = Filter.suppress_repeats([now], [prior], 2)

      assert out.status == :posted
      assert out.line == 42
    end

    test "a SAME-line pre_existing repeat still suppresses (only different-line is exempt)" do
      f = finding("lib/foo.ex", 7, :correctness, :pre_existing)
      prior = %{round: 1, findings: [entry(f, :posted, 1, 0)]}
      [out] = Filter.suppress_repeats([f], [prior], 2)
      assert out.status == :suppressed
    end

    test "different-line NON-pre_existing repeats also never suppress (key embeds line)" do
      posted = finding("lib/foo.ex", 7, :correctness)
      moved = finding("lib/foo.ex", 42, :correctness)
      prior = %{round: 1, findings: [entry(posted, :posted, 1, 0)]}
      [out] = Filter.suppress_repeats([moved], [prior], 2)
      assert out.status == :posted
    end
  end

  describe "Finding identity" do
    test "same observation -> same id; whitespace/case-insensitive summary matches" do
      a = finding("lib/foo.ex", 7, :correctness)

      b =
        Finding.new(
          file: "lib/foo.ex",
          line: 7,
          class: :correctness,
          severity: :important,
          summary: "  UNDO/4   must   restore\npre_run_hash  ",
          perspective: :correctness
        )

      assert a.id == b.id
    end

    test "different line -> different id and different suppression_key" do
      a = finding("lib/foo.ex", 7, :correctness)
      b = finding("lib/foo.ex", 42, :correctness)
      assert a.id != b.id
      assert Finding.suppression_key(a) != Finding.suppression_key(b)
      assert Finding.suppression_key(a) == "lib/foo.ex:7:correctness"
    end

    test "to_map/from_map round-trips all fields" do
      f = %{finding("lib/foo.ex", 7, :correctness) | first_seen_round: 2, status: :suppressed}
      m = Finding.to_map(f)
      assert is_map(m) and Map.get(m, "id") == f.id
      assert %Finding{} = g = Finding.from_map(m)
      assert g.id == f.id
      assert g.line == f.line
      assert g.class == f.class
      assert g.severity == f.severity
      assert g.status == :suppressed
      assert g.first_seen_round == 2
      assert g.file == f.file
      assert g.summary == f.summary
      assert g.perspective == f.perspective
    end
  end
end
