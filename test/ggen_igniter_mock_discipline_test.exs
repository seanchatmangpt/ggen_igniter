defmodule GgenIgniter.MockDisciplineTest do
  @moduledoc """
  Chicago-style: the collaborator is the real `grep` binary invoked via
  `System.cmd/3` over the real checkout tree (lib/, test/, native/), asserting
  on the real exit status and real stdout — no doubles anywhere in this file.

  The banned-token regex is the one pinned in `test/CLAUDE.md`. The pattern
  literal is assembled by concatenation so this source file cannot match the
  regex it enforces (the alternation contains the bare tokens `mo**ckall` and
  `Ma**gicMock`, which would otherwise self-hit).

  Allowlist (named exceptions, per `testing-chicago-style.md` — each is a
  real-state self-reference, not a test double):

    * `lib/ggen_igniter/review/perspectives/chicago_tests.ex` — the review
      perspective that CARRIES the enforcement regex itself (self-match).
    * `test/ggen_igniter_review_tally_test.exs` — its hit is a diff-fixture
      heredoc line (`+  import Mox` inside a diff string) fed to the real
      Review pipeline to prove the perspective detects the token in a real
      diff — a real-state fixture, not a mock.
    * `test/ggen_igniter_mock_discipline_test.exs` — this file: the
      disclosure above quotes the tokens; `test/CLAUDE.md` already
      anticipates moduledoc self-matches.

  The allowlist is anti-vacuous: each entry is asserted to still produce a
  grep hit, so a fixed file makes the stale allowlist entry fail loudly
  instead of silently widening the sweep.
  """

  use ExUnit.Case, async: true

  @banned_pattern ~S{(use|import) +(Mox|Mimic|Patch)\b|(Mox|Mimic|Patch)\.|:meck\.|mo} <>
                    ~S{ckall|Ma} <>
                    ~S{gicMock|Mock\(}

  @dirs ["lib", "test", "native"]

  # `path:line:` prefixes of hits that are the enforcement machinery or
  # real-state fixtures naming the tokens, never doubles.
  @allowlist_prefixes [
    "lib/ggen_igniter/review/perspectives/chicago_tests.ex:",
    "test/ggen_igniter_review_tally_test.exs:",
    "test/ggen_igniter_mock_discipline_test.exs:"
  ]

  describe "mock discipline sweep (test/CLAUDE.md regex)" do
    test "grep for banned test-double tokens over lib/, test/, native/ exits 1 with zero output" do
      {output, exit_status} =
        System.cmd(
          "grep",
          [
            "-rn",
            "--include=*.ex",
            "--include=*.exs",
            "--include=*.rs",
            "--include=*.py",
            "--exclude-dir=_build",
            "--exclude-dir=deps",
            "-E",
            @banned_pattern
          ] ++ @dirs,
          cd: File.cwd!()
        )

      hits = String.split(output, "\n", trim: true)
      {allowlisted, violations} = Enum.split_with(hits, fn hit -> allowlisted?(hit) end)

      assert violations == [],
             "banned test-double tokens found (grep exit #{exit_status}):\n#{output}"

      # Anti-vacuity: every allowlist entry must still be earning its place.
      # A file fixed or removed should shrink this list, not rot silently.
      for prefix <- @allowlist_prefixes do
        assert Enum.any?(allowlisted, &String.starts_with?(&1, prefix)),
               "stale allowlist entry: #{prefix} no longer matches — remove it"
      end
    end
  end

  defp allowlisted?(hit) do
    line = hit |> String.split(":", parts: 2) |> hd()

    Enum.any?(@allowlist_prefixes, fn prefix ->
      path = String.trim_trailing(prefix, ":")
      line == path
    end)
  end
end
