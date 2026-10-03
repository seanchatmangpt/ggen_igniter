defmodule GgenIgniter.MockDisciplineTest do
  @moduledoc """
  Chicago-style: the collaborator is the real `grep` binary invoked via
  `System.cmd/3` over the real checkout tree (lib/, test/, native/), asserting
  on the real exit status and real stdout — no doubles anywhere in this file.

  The banned-token regex is the one pinned in `test/CLAUDE.md`. The pattern
  literal is assembled by concatenation so this source file cannot match the
  regex it enforces (the alternation contains the bare tokens `mo**ckall` and
  `Ma**gicMock`, which would otherwise self-hit).
  """

  use ExUnit.Case, async: true

  @banned_pattern ~S{(use|import) +(Mox|Mimic|Patch)\b|(Mox|Mimic|Patch)\.|:meck\.|mo} <>
                    ~S{ckall|Ma} <>
                    ~S{gicMock|Mock\(}

  @dirs ["lib", "test", "native"]

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

      assert exit_status == 1,
             "banned test-double tokens found (grep exit #{exit_status}):\n#{output}"

      assert output == ""
    end
  end
end
