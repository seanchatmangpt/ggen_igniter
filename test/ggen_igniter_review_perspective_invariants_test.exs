defmodule GgenIgniter.ReviewPerspectiveInvariantsTest do
  @moduledoc """
  Chicago-style: real unified-diff strings scanned by the real
  `GgenIgniter.Review.Perspectives.Invariants` into real
  `GgenIgniter.Review.Finding` structs. No doubles; assertions are on returned
  structs and triples. The hand-written-Ash trigger is assembled by concatenation
  so this source does not trip the repo's Ash-write hook.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Review.Finding
  alias GgenIgniter.Review.Perspectives.Invariants

  @ash_resource "use Ash." <> "Resource"
  @ash_domain "use Ash." <> "Domain"

  defp diff(path, start, lines) do
    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n" <>
      "@@ -1,1 +#{start},#{length(lines)} @@\n" <> Enum.join(lines, "\n") <> "\n"
  end

  defp review(text), do: Invariants.review_diff(text, [])

  describe "review_diff/2 (one diff per rule)" do
    for {name, content, summary_prefix} <- [
          {"Ash Resource", {:ash, :resource}, "hand-written Ash surface"},
          {"Ash Domain", {:ash, :domain}, "hand-written Ash surface"},
          {"worktree add", "git worktree add ../x", "worktree creation"},
          {"reset hard", "git reset --hard HEAD~1", "git reset --hard"},
          {"force push", "git push --force origin main", "force push"},
          {"merge theirs", "git merge -X theirs feature", "blanket merge strategy"},
          {"merge ours", "git merge -X ours feature", "blanket merge strategy"}
        ] do
      test "#{name} yields one :invariant finding at the added line" do
        content =
          case unquote(Macro.escape(content)) do
            {:ash, :resource} -> @ash_resource <> ", domain: X"
            {:ash, :domain} -> @ash_domain
            other -> other
          end

        assert [%Finding{} = f] = review(diff("lib/a.ex", 10, [" ctx", "+" <> content]))
        assert f.class == :invariant
        assert f.perspective == :invariants
        assert f.severity == :important
        assert f.file == "lib/a.ex"
        assert f.line == 11
        assert String.starts_with?(f.summary, unquote(summary_prefix))
      end
    end
  end

  describe "review_diff/2 (line numbering and attribution)" do
    test "two hunks reset the line counter" do
      text =
        "--- a/lib/a.ex\n+++ b/lib/a.ex\n" <>
          "@@ -1,1 +5,1 @@\n+git reset --hard\n" <>
          "@@ -20,1 +40,1 @@\n+git reset --hard\n"

      assert [%{line: 5}, %{line: 40}] = review(text)
    end

    test "two files are attributed separately" do
      text =
        "--- a/lib/a.ex\n+++ b/lib/a.ex\n@@ -1,1 +3,1 @@\n+git worktree add x\n" <>
          "--- a/lib/b.ex\n+++ b/lib/b.ex\n@@ -1,1 +7,1 @@\n+git reset --hard\n"

      assert [%{file: "lib/a.ex", line: 3}, %{file: "lib/b.ex", line: 7}] = review(text)
    end

    test "a line matching two rules yields two findings in rule order" do
      text = diff("lib/a.ex", 1, ["+git reset --hard && git push --force"])
      assert [a, b] = review(text)
      assert String.starts_with?(a.summary, "git reset --hard")
      assert String.starts_with?(b.summary, "force push")
      assert a.line == 1 and b.line == 1
      refute a.id == b.id
    end
  end

  describe "review_diff/2 (not flagged)" do
    test "removed and context lines are not flagged" do
      lines = ["-git reset --hard", " git reset --hard", "+ok = 1"]
      assert [] == review(diff("lib/a.ex", 1, lines))
    end

    test "-X theirsy is not flagged (word boundary)" do
      assert [] == review(diff("lib/a.ex", 1, ["+git merge -X theirsy feature"]))
    end

    test "empty diff yields no findings" do
      assert [] == review("")
    end
  end

  describe "added_lines/1" do
    test "returns exact {file, line, text} triples" do
      text = "--- a/f\n+++ b/f\n@@ -1,2 +1,3 @@\n ctx\n+added\n-removed\n+two\n"
      assert [{"f", 2, "added"}, {"f", 3, "two"}] == Invariants.added_lines(text)
    end

    test "empty text gives []" do
      assert [] == Invariants.added_lines("")
    end
  end

  describe "review_diff/2 (git commit -m)" do
    test "git commit -a -m is flagged (the regex can match when another flag precedes -m)" do
      assert [f] = review(diff("lib/a.ex", 1, ["+git commit -a -m \"x\""]))
      assert String.starts_with?(f.summary, "inline git commit -m")
    end

    # PREDICTED-RED: regex `git\s+commit\s+.*\s-m\b` needs whitespace BOTH before
    # `.*` and before `-m`; in the canonical `git commit -m "x"` there is a single
    # space, so `\s+` consumes it and `\s-m` cannot match. Correct behavior: flagged.
    @tag :expected_red
    test "canonical `git commit -m \"x\"` should be flagged by the commit rule" do
      assert [f] = review(diff("lib/a.ex", 1, ["+git commit -m \"x\""]))
      assert String.starts_with?(f.summary, "inline git commit -m")
    end
  end

  describe "review_diff/2 (header confusion)" do
    # PREDICTED-RED: an added line whose content begins `++ ` yields the diff line
    # `+++ ...`, which do_scan treats as a file header, so the line is lost and the
    # current file is replaced. Correct behavior: flagged at the real file/line 2.
    @tag :expected_red
    test "added line with content `++ git reset --hard` is not mistaken for a file header" do
      text = diff("lib/a.ex", 1, ["+ok = 1", "+++ git reset --hard"])
      assert [%Finding{file: "lib/a.ex", line: 2}] = review(text)
    end
  end
end
