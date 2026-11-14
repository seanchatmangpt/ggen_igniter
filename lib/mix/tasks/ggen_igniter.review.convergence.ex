defmodule Mix.Tasks.GgenIgniter.Review.Convergence do
  @shortdoc "Bounded review-convergence rounds (cap 3) over one content-sha"

  @moduledoc """
  Thin CLI over `GgenIgniter.Convergence.run/2`:

      mix ggen_igniter.review.convergence --sha SHA [--diff PATH] \\
        [--max-rounds N] [--json]

  Round state machine per content-sha: `ROUND_RUNNING -> ROUND_PASSED |
  ROUND_FIXED_ADVANCES | REVIEW_ESCALATED`; terminal states are final — no
  round 4 ever (`--max-rounds` overrides the cap for tests only).

  Exit `0` passed, `1` escalated, `2` bad invocation. Rounds persist to
  `<base_dir>/.ggen_igniter/reviews/<sha>/rounds.jsonl` via
  `GgenIgniter.ReviewStore`.

  Scope note (honest): no automated critic is wired to this task yet — the
  default reviewer is a deterministic structural pass (empty findings), so
  a run without `--diff`-backed findings passes on round 1. Real critic
  integration lands with the reviewer contract, not by silently extending
  this task.
  """

  use Mix.Task

  alias GgenIgniter.Convergence
  alias GgenIgniter.ReviewStore

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [sha: :string, diff: :string, max_rounds: :integer, json: :boolean],
        aliases: [s: :sha, d: :diff, m: :max_rounds]
      )

    validate_args!(opts, invalid)

    base_dir = File.cwd!()
    diff = opts[:diff] && File.read!(opts[:diff])

    reviewer = fn input ->
      # Default deterministic reviewer: structurally, an empty-finding pass.
      # See moduledoc scope note.
      _ = input
      []
    end

    run_opts =
      [reviewer: reviewer]
      |> maybe_put(:max_rounds, opts[:max_rounds])

    case Convergence.run(%{sha: opts[:sha], base_dir: base_dir, diff: diff}, run_opts) do
      {:ok, result} ->
        rounds = ReviewStore.read_rounds(base_dir, opts[:sha])
        final = to_string(result.state)

        report(opts, final, rounds, result)

        if final == "review_escalated", do: System.halt(1), else: :ok

      {:error, reason} ->
        Mix.shell().error("review convergence failed: #{inspect(reason)}")
        System.halt(2)
    end
  end

  defp validate_args!(opts, invalid) do
    if invalid != [] or not is_binary(opts[:sha]) do
      Mix.shell().error(
        "usage: mix ggen_igniter.review.convergence --sha SHA [--diff PATH] [--max-rounds N] [--json]"
      )

      System.halt(2)
    end

    if opts[:max_rounds] != nil and opts[:max_rounds] <= 0 do
      Mix.shell().error("--max-rounds must be >= 1, got: #{opts[:max_rounds]}")
      System.halt(2)
    end
  end

  defp report(opts, final, rounds, result) do
    if opts[:json] do
      Mix.shell().info(
        Jason.encode!(%{"sha" => opts[:sha], "final_state" => final, "rounds" => rounds})
      )
    else
      Mix.shell().info(
        "review convergence: sha=#{opts[:sha]} final=#{final} rounds=#{result.rounds_executed}"
      )
    end
  end

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)
end
