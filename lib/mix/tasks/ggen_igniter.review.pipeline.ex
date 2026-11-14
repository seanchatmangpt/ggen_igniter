defmodule Mix.Tasks.GgenIgniter.Review.Pipeline do
  @shortdoc "Run the fixed landing-pipeline stage registry over one candidate landing"

  @moduledoc """
  CLI entry over `GgenIgniter.LandingPipeline.run/1` (delegates 100% —
  flag-parsing only, zero business logic here, per `lib/mix/tasks/CLAUDE.md`).

      mix ggen_igniter.review.pipeline --base REF [--epoch LABEL] [--out PATH] [--json]

  The pipeline runs stage 0 `:base_integrity` (real git: `rev-parse --verify`,
  `merge-base --is-ancestor`, worktree-drift check) and then the FIXED
  ordered stage registry — 1 `:epoch_check`, 2 `:risk_tier`, 3 `:build_gate`,
  4 `:fanout_review`, 5 `:security_block`, 6 `:convergence_cap`,
  7 `:incident_eval` — short-circuiting on the first block/refusal. The fixed
  order is load-bearing: risk tier precedes fan-out width. Per-stage receipts
  land in `.ggen_igniter/receipts/pipeline/<run_id>/stage-<order>-<name>.json`
  plus `landing-receipt.json`.

  ## Flags

    * `--base REF` (required) — the git base the landing is judged against
    * `--epoch LABEL` — optional epoch label recorded in the report
    * `--out PATH` — the final landing receipt is also written there
    * `--json` — exactly one JSON document on stdout (no trailing prose)
    * `--help` — this usage text

  ## Exit contract (the `mix ggen_igniter.epoch.check` exit law)

    * `0` — every stage passed with real embedded output (status ALIVE)
    * `1` — BLOCKED: base drift / first-stage block or refusal (typed JSON
      as the last line of stderr, and `landing-receipt.json` on disk)
    * `2` — invalid invocation (e.g. missing `--base`)
  """

  use Mix.Task

  alias GgenIgniter.LandingPipeline

  @impl Mix.Task
  def run(args) do
    if "--help" in args do
      print_help_and_halt()
    else
      run_pipeline(args)
    end
  end

  defp run_pipeline(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [base: :string, epoch: :string, out: :string, json: :boolean]
      )

    if invalid != [] do
      usage()
      System.halt(2)
    end

    task_opts =
      []
      |> put_opt(:base, opts[:base])
      |> put_opt(:epoch, opts[:epoch])

    case LandingPipeline.run(task_opts) do
      {2, report} ->
        emit_json(report, :stderr)
        System.halt(2)

      {code, report} ->
        maybe_write_out(opts[:out], report)
        finish(report, code, opts[:json])
    end
  end

  # Returning normally would let a runner print trailing prose AFTER the JSON document; --json
  # must stay one valid document (the `ggen_igniter.doctor` --json law).
  defp finish(report, code, true) do
    IO.puts(Jason.encode!(report))
    System.halt(code)
  end

  defp finish(report, code, _json) do
    print_human(report)
    if code == 1, do: emit_last_line_stderr(report)
    System.halt(code)
  end

  defp maybe_write_out(nil, _report), do: :ok

  defp maybe_write_out(path, report) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true) <> "\n")
  end

  defp print_human(report) do
    Mix.shell().info(
      "review pipeline: status=#{report["status"]} " <>
        "stages=#{Enum.map_join(report["stages"], ",", & &1["stage"])}"
    )

    case report["first_block"] do
      nil -> :ok
      block -> Mix.shell().info("first_block: #{block["stage"]} #{inspect(block["reason"])}")
    end

    Mix.shell().info("receipts: #{report["receipts_dir"]}")
  end

  # Exit-1 typed refusal: the full report JSON as the LAST LINE of stderr,
  # the same stream contract `mix semantic_jira.execute` exit-1 uses.
  defp emit_last_line_stderr(report),
    do: Mix.shell().error(Jason.encode!(report))

  defp emit_json(report, :stderr), do: Mix.shell().error(Jason.encode!(report))

  defp put_opt(kw, _key, nil), do: kw
  defp put_opt(kw, key, value), do: Keyword.put(kw, key, value)

  defp print_help_and_halt do
    IO.puts(usage_text())
    System.halt(0)
  end

  defp usage do
    Mix.shell().error(usage_text())
  end

  defp usage_text do
    """
    usage: mix ggen_igniter.review.pipeline --base REF [--epoch LABEL] [--out PATH] [--json]

      --base REF   (required) git base the landing is judged against
      --epoch LBL  optional epoch label recorded in the receipt
      --out PATH   also write landing-receipt.json there
      --json       exactly one JSON document on stdout
      --help       this text
    """
  end
end
