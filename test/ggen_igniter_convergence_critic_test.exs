defmodule GgenIgniter.ConvergenceCriticTest do
  @moduledoc """
  Chicago-style: real hunk-text strings critiqued by the real
  `GgenIgniter.Convergence.Critic.review/1`; class membership is checked against
  the real `GgenIgniter.Convergence.Classes.classes/0`. Pure function, no doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Convergence.Classes
  alias GgenIgniter.Convergence.Critic

  defp hunk(text, id \\ "h1", file \\ "lib/a.ex"),
    do: %{file: file, hunk_id: id, hunk_text: "@@ -1 +1 @@\n" <> text}

  defp classes(hunks), do: %{hunks: hunks} |> Critic.review() |> Enum.map(& &1.class)
  defp classes_of(text), do: classes([hunk(text)])

  describe "review/1 (formatting)" do
    test "trailing space, trailing tab and whitespace-only added lines are flagged" do
      assert [:formatting] == classes_of("+foo \n")
      assert [:formatting] == classes_of("+foo\t\n")
      assert [:formatting] == classes_of("+   \n")
    end

    test "empty added body and context lines are not flagged" do
      assert [] == classes_of("+\n")
      assert [] == classes_of(" foo \n")
      assert [] == classes_of("-foo \n")
    end

    # CHARACTERIZATION: text is split on "\n" only, so a CRLF line keeps its "\r",
    # which is neither space nor tab: trailing whitespace before CRLF is not seen.
    test "CHARACTERIZATION: CRLF line endings are not flagged" do
      assert [] == classes_of("+foo \r\n")
    end
  end

  describe "review/1 (dead_code)" do
    test "IO.inspect and dbg( are flagged" do
      assert [:dead_code] == classes_of("+IO.inspect(x)\n")
      assert [:dead_code] == classes_of("+dbg(x)\n")
    end

    test "removed debug lines are not flagged" do
      assert [] == classes_of("-IO.inspect(x)\n")
    end

    test "substring match is pinned: mydbg(x) is flagged" do
      assert [:dead_code] == classes_of("+mydbg(x)\n")
    end

    test "multiple hits on one line come in order formatting, dead_code" do
      assert [:formatting, :dead_code] == classes_of("+IO.inspect(x) \n")
    end
  end

  describe "review/1 (missing_doc)" do
    test "bare defmodule is flagged" do
      assert [:missing_doc] == classes_of("+defmodule Foo do\n")
    end

    test "moduledoc added before the defmodule line leaves it clean" do
      assert [] == classes_of("+@moduledoc \"x\"\n+defmodule Foo do\n")
    end

    test "moduledoc added after the defmodule line does not help it" do
      assert [:missing_doc] == classes_of("+defmodule Foo do\n+  @moduledoc \"x\"\n")
    end

    test "@moduledoc false counts as a moduledoc" do
      assert [] == classes_of("+@moduledoc false\n+defmodule Foo do\n")
    end

    test "two defmodules after one moduledoc are both clean" do
      assert [] == classes_of("+@moduledoc false\n+defmodule A do\n+defmodule B do\n")
    end

    test "a moduledoc in a separate hunk is not seen, and state does not leak across hunks" do
      hunks = [hunk("+@moduledoc false\n", "h1"), hunk("+defmodule Foo do\n", "h2")]
      assert [%{class: :missing_doc, hunk_id: "h2"}] = Critic.review(%{hunks: hunks})
    end

    test "@@ lines are skipped" do
      h = %{file: "f", hunk_id: "h", hunk_text: "@@ -1 +1 @@ defmodule Foo do \n"}
      assert [] == Critic.review(%{hunks: [h]})
    end
  end

  describe "review/1 (finding shape and determinism)" do
    test "finding carries file, hunk_id, message and a closed-set class" do
      input = %{hunks: [hunk("+IO.inspect(x)\n+defmodule Foo do\n", "h9", "lib/z.ex")]}
      findings = Critic.review(input)

      assert [
               %{file: "lib/z.ex", hunk_id: "h9", class: :dead_code},
               %{file: "lib/z.ex", hunk_id: "h9", class: :missing_doc}
             ] = findings

      assert Enum.all?(findings, &is_binary(&1.message))
      assert Enum.all?(findings, &(&1.class in Classes.classes()))
    end

    test "findings follow hunk order, then line order" do
      hunks = [hunk("+dbg(a)\n", "h1"), hunk("+defmodule A do\n+foo \n", "h2")]

      assert [{"h1", :dead_code}, {"h2", :missing_doc}, {"h2", :formatting}] ==
               %{hunks: hunks} |> Critic.review() |> Enum.map(&{&1.hunk_id, &1.class})
    end

    test "same input gives the same findings" do
      input = %{hunks: [hunk("+IO.inspect(x) \n+defmodule Foo do\n")]}
      assert Critic.review(input) == Critic.review(input)
    end

    test "scope and round keys are ignored" do
      hunks = [hunk("+dbg(a)\n")]

      assert Critic.review(%{hunks: hunks}) ==
               Critic.review(%{hunks: hunks, scope: :anything, round: 7})
    end
  end

  describe "review/1 (fail-soft inputs)" do
    test "non-conforming inputs return []" do
      assert [] == Critic.review(%{hunks: []})
      assert [] == Critic.review(%{})
      assert [] == Critic.review(nil)
      assert [] == Critic.review(%{hunks: :bad})
    end

    test "malformed hunk maps are skipped while valid ones are still critiqued" do
      bad = [%{file: "a"}, %{file: "a", hunk_id: "x", hunk_text: 42}, :junk, nil]
      assert [:dead_code] == classes(bad ++ [hunk("+dbg(a)\n")])
    end
  end

  describe "review/1 (header-prefix probe)" do
    # PREDICTED-RED: the critic skips every line starting `+++`, so an added line
    # whose content begins `++ ` (diff line `+++ IO.inspect(x)`) is dropped even
    # though it is real added debug code. Correct behavior: caught as dead_code.
    @tag :expected_red
    test "`+++ IO.inspect(x)` added line is caught as dead_code" do
      assert [:dead_code] == classes_of("+++ IO.inspect(x)\n")
    end
  end
end
