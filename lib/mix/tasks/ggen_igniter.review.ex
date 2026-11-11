defmodule Mix.Tasks.GgenIgniter.Review do
  @shortdoc "One fan-out review round over a diff: perspectives -> verifiers -> tally -> store."

  @moduledoc """
  Runs one review round (L2 review core) over the diff between `--base` and
  `--head`, delegating 100% to `GgenIgniter.Review`. The Mix task is parsing
  and envelope only — no review logic lives here.

  ## Usage

      mix ggen_igniter.review --base main --head HEAD
      mix ggen_igniter.review --base HEAD~1 --json
      mix ggen_igniter.review --base main --round 2 --review-id my-feature

  ## Flags

    * `--base REF` (default `HEAD`) — git ref to diff against.
    * `--head REF` — optional second ref; with it the task runs
      `git diff base head`, without it `git diff base` (working tree).
    * `--verifiers N` — verifier count M (default 3); the core pads with
      neutral abstainers, so with no injected verifiers every finding is
      rejected (fail closed).
    * `--round N` — review round number (default 1); drives cross-round
      repeat suppression and `rounds.jsonl` history.
    * `--review-id ID` — persistence key under
      `.ggen_igniter/reviews/<ID>/` (default "current").
    * `--json` — the round doc as one JSON document on stdout.
    * `--help`, `-h` — usage.

  ## Exit codes (GgenIgniter.TaskContract)

    * 0 (`:ok`) — round completed with no POSTED findings (clean, or all
      suppressed).
    * 1 (`:refusal`) — round completed but posted findings remain (or a
      typed refusal: bad diff refs).
    * 2 (`:invocation`) — bad flags or unresolvable input.
  """

  use Mix.Task

  alias GgenIgniter.Review

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [
          base: :string,
          head: :string,
          verifiers: :integer,
          round: :integer,
          review_id: :string,
          json: :boolean,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    cond do
      opts[:help] ->
        print_help()

      invalid != [] ->
        invocation!("unknown flag(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

      opts[:verifiers] == nil or opts[:verifiers] >= 1 ->
        review(opts)

      true ->
        invocation!("--verifiers must be >= 1")
    end
  end

  defp review(opts) do
    base = opts[:base] || "HEAD"

    diff_text =
      case git_diff(base, opts[:head]) do
        {:ok, text} ->
          text

        {:error, output} ->
          refusal({"GIT_DIFF_FAILED", "git diff #{base} failed: #{String.trim(output)}"})
      end

    # Review.run/2 is {:ok, doc}-only; a crashed perspective raises before returning.
    {:ok, doc} =
      Review.run(diff_text,
        review_id: opts[:review_id] || "current",
        round: opts[:round] || 1,
        verifier_count: opts[:verifiers] || 3
      )

    report(doc, opts)
  end

  defp git_diff(base, nil) do
    case System.cmd("git", ["diff", "--unified=3", base], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  defp git_diff(base, head) do
    case System.cmd("git", ["diff", "--unified=3", base, head], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  defp report(doc, _opts) do
    n_posted = length(doc.posted)

    data = %{
      "round" => doc.round,
      "posted_count" => n_posted,
      "suppressed_count" => length(doc.suppressed),
      "posted" => Enum.map(doc.posted, &GgenIgniter.Review.Finding.to_map/1),
      "suppressed" => Enum.map(doc.suppressed, &GgenIgniter.Review.Finding.to_map/1)
    }

    {outcome, refusal} =
      if n_posted == 0 do
        {:ok, nil}
      else
        {:refusal, {"POSTED_FINDINGS", "#{n_posted} finding(s) remain posted"}}
      end

    env = GgenIgniter.TaskContract.envelope("review", outcome, data: data, refusal: refusal)
    IO.puts(GgenIgniter.TaskContract.encode(env))

    if outcome == :ok, do: :ok, else: System.halt(1)
  end

  defp refusal({code, detail}) do
    env = GgenIgniter.TaskContract.envelope("review", :refusal, refusal: {code, detail})
    IO.puts(GgenIgniter.TaskContract.encode(env))
    System.halt(1)
  end

  # Bad flags / unresolvable input: exit 2, never Mix.raise's 1.
  @spec invocation!(String.t()) :: no_return()
  defp invocation!(message) do
    IO.puts(:stderr, "ggen_igniter.review: " <> message)
    System.halt(2)
  end

  defp print_help do
    IO.puts(@moduledoc)
  end
end
