defmodule GgenIgniter.ReviewVerifierTest do
  @moduledoc """
  Chicago-style: real `GgenIgniter.Review.Finding` structs voted on by real
  hand-written verifier functions (including ones that read a real tmp file on
  disk). No doubles; assertions are on the returned verdict and vote list.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Review.Finding
  alias GgenIgniter.Review.Verifier

  setup do
    dir = Path.join(System.tmp_dir!(), "verifier_test_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp finding(file \\ "lib/a.ex", line \\ 1) do
    Finding.new(
      file: file,
      line: line,
      class: :correctness,
      severity: :important,
      summary: "s",
      perspective: :correctness
    )
  end

  defp const(vote), do: fn _f -> vote end
  defp verdict(votes), do: votes |> Enum.map(&const/1) |> then(&Verifier.vote(finding(), &1))

  # Real verifier: the cited file exists and has at least `line` lines.
  defp file_line_exists(%Finding{file: file, line: line}) do
    case File.read(file) do
      {:ok, body} ->
        if line >= 1 and line <= length(String.split(body, "\n", trim: true)),
          do: :sustain,
          else: :reject

      {:error, _} ->
        :reject
    end
  end

  describe "vote/2 (majority table)" do
    test "M=1" do
      assert {:sustained, [:sustain]} = verdict([:sustain])
      assert {:rejected, [:reject]} = verdict([:reject])
      assert {:rejected, [:abstain]} = verdict([:abstain])
    end

    test "M=2" do
      assert {:sustained, _} = verdict([:sustain, :sustain])
      assert {:rejected, _} = verdict([:sustain, :abstain])
      assert {:rejected, _} = verdict([:sustain, :reject])
    end

    test "M=3" do
      assert {:sustained, _} = verdict([:sustain, :sustain, :reject])
      assert {:sustained, _} = verdict([:sustain, :sustain, :abstain])
      assert {:sustained, _} = verdict([:sustain, :sustain, :sustain])
      assert {:rejected, _} = verdict([:sustain, :reject, :abstain])
      assert {:rejected, _} = verdict([:reject, :reject, :reject])
      assert {:rejected, _} = verdict([:abstain, :abstain, :abstain])
    end

    test "M=4 needs 3 sustains" do
      assert {:sustained, _} = verdict([:sustain, :sustain, :sustain, :abstain])
      assert {:sustained, _} = verdict([:sustain, :sustain, :sustain, :reject])
      assert {:rejected, _} = verdict([:sustain, :sustain, :abstain, :abstain])
      assert {:rejected, _} = verdict([:sustain, :sustain, :reject, :reject])
    end

    test "M=5" do
      assert {:sustained, _} = verdict([:sustain, :sustain, :sustain, :reject, :reject])
      assert {:rejected, _} = verdict([:sustain, :sustain, :abstain, :abstain, :abstain])
      assert {:rejected, _} = verdict([:sustain, :sustain, :reject, :reject, :abstain])
    end
  end

  describe "vote/2 (votes and failure modes)" do
    test "votes are returned in verifier input order" do
      assert {:rejected, [:abstain, :reject, :sustain]} =
               verdict([:abstain, :reject, :sustain])
    end

    test "an unknown vote atom counts toward M only" do
      assert {:sustained, [:sustain, :sustain, :weird]} = verdict([:sustain, :sustain, :weird])
      assert {:rejected, _} = verdict([:sustain, :weird])
    end

    test "a raising verifier propagates" do
      boom = fn _f -> raise "verifier exploded" end

      assert_raise RuntimeError, "verifier exploded", fn ->
        Verifier.vote(finding(), [const(:sustain), boom, const(:sustain)])
      end
    end

    test "empty verifier list raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Verifier.vote(finding(), []) end
    end

    test "non-Finding raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Verifier.vote(%{file: "x"}, [const(:sustain)]) end
    end

    test "non-list verifiers raise FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Verifier.vote(finding(), const(:sustain)) end
    end
  end

  describe "vote/2 (real file-reading verifiers)" do
    test "existing file and in-range line sustains; missing file and past-end reject", %{dir: dir} do
      path = Path.join(dir, "real.ex")
      File.write!(path, "one\ntwo\nthree\n")
      verifiers = [&file_line_exists/1, &file_line_exists/1, &file_line_exists/1]

      assert {:sustained, [:sustain, :sustain, :sustain]} =
               Verifier.vote(finding(path, 3), verifiers)

      assert {:rejected, [:reject, :reject, :reject]} =
               Verifier.vote(finding(path, 4), verifiers)

      assert {:rejected, [:reject, :reject, :reject]} =
               Verifier.vote(finding(Path.join(dir, "missing.ex"), 1), verifiers)
    end
  end

  describe "pad_default/2" do
    test "default_count is 3" do
      assert Verifier.default_count() == 3
    end

    test "pads with always_abstain up to count" do
      padded = Verifier.pad_default([const(:sustain)], 3)
      assert length(padded) == 3
      assert Enum.map(padded, & &1.(finding())) == [:sustain, :abstain, :abstain]
    end

    test "empty list pads to all abstentions, which reject (fail-closed default)" do
      padded = Verifier.pad_default([], Verifier.default_count())
      assert {:rejected, [:abstain, :abstain, :abstain]} = Verifier.vote(finding(), padded)
    end

    test "truncates when more verifiers than count" do
      vs = [const(:sustain), const(:reject), const(:abstain), const(:reject)]
      assert Enum.map(Verifier.pad_default(vs, 2), & &1.(finding())) == [:sustain, :reject]
    end

    test "exact count is unchanged" do
      vs = [const(:sustain), const(:reject)]
      assert Enum.map(Verifier.pad_default(vs, 2), & &1.(finding())) == [:sustain, :reject]
    end

    test "count below 1 raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Verifier.pad_default([], 0) end
    end
  end

  describe "always_abstain/1" do
    test "abstains on any Finding" do
      assert Verifier.always_abstain(finding()) == :abstain
    end

    test "non-Finding raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Verifier.always_abstain(%{}) end
    end
  end
end
