defmodule Mix.Tasks.SemanticJira.CompileProse do
  @shortdoc "Admits prose candidates and manufactures the finite sJira WorkOrder delta (GC23-0/GC23-2)."

  @moduledoc """
  First-mile compiler (GC-26.9.23 gates GC23-0 and GC23-2; PRD PR-002..PR-005,
  ARD sections 5 and 17). Thin CLI over `GgenIgniter.SemanticJira.Prose`:
  provenance binding -> SHACL admission -> domain rules (contradiction,
  foreign requirement, gate coverage) -> deterministic delta
  (`prose/delta.construct.rq`) -> sorted N-Triples outputs.

  No LLM, network model API or clock participates: the admitted graph ->
  WorkOrder manufacture replays byte-identically (ARD section 5.5).

  ## Usage

      mix semantic_jira.compile_prose --source prose.md --candidates candidates.ttl \\
        --goal goal.ttl [--receipts-dir DIR] --out-dir DIR [--check] [--pack-dir DIR]

  ## Flags

    * `--source PATH` -- the accepted prose (its bytes are the provenance).
    * `--candidates PATH` -- PVOCAB candidate Turtle (`sj:Proposition`s).
    * `--goal PATH` -- the goal graph; its single root GoalCheckpoint (children,
      no parent) defines the gates and the instance namespace.
    * `--receipts-dir DIR` -- optional; fleet R-schema receipts (`*.json`) whose
      ALIVE `identity.subject` names a proposition or its gate witness it, so no
      WorkOrder is manufactured for it.
    * `--out-dir DIR` -- where `propositions.ttl` and `orders.ttl` are written.
    * `--check` -- write nothing; exit 0 only when `--out-dir` already holds
      byte-identical outputs.
    * `--pack-dir DIR` -- defaults to `priv/ggen/semantic-jira-pack`.

  Exits 0 only when admission and coverage pass (and, with `--check`, the
  outputs recompute byte-identically); otherwise prints one
  `REFUSED(<code>) <subject>: <detail>` line per refusal and exits 1.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Prose

  @switches [
    source: :string,
    candidates: :string,
    goal: :string,
    receipts_dir: :string,
    out_dir: :string,
    pack_dir: :string,
    check: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] or positional != [] ->
        refuse(["REFUSED(usage) -: unexpected arguments #{inspect(invalid ++ positional)}"])

      opts[:out_dir] == nil ->
        refuse(["REFUSED(usage) -: --out-dir is required"])

      true ->
        opts |> compile_opts() |> Prose.compile() |> finish(opts)
    end
  end

  defp compile_opts(opts) do
    Keyword.take(opts, [:source, :candidates, :goal, :receipts_dir, :pack_dir])
  end

  defp finish({:refused, refusals}, _opts),
    do: refuse(Enum.map(refusals, &Prose.render_refusal/1))

  defp finish({:ok, result}, opts) do
    if opts[:check] do
      case Prose.check(result, opts[:out_dir]) do
        :ok ->
          print_summary(result.summary)
          Mix.shell().info("CHECK: #{opts[:out_dir]} outputs recompute byte-identically")

        {:refused, refusals} ->
          refuse(Enum.map(refusals, &Prose.render_refusal/1))
      end
    else
      Prose.write!(result, opts[:out_dir])
      print_summary(result.summary)

      Mix.shell().info(
        "WROTE: #{Enum.map_join(Prose.output_files(), ", ", &Path.join(opts[:out_dir], &1))}"
      )
    end
  end

  defp print_summary(summary) do
    Mix.shell().info(
      "ADMITTED: #{summary.admitted} propositions " <>
        "(#{summary.required} required, #{summary.not_required} not required)"
    )

    Mix.shell().info("KINDS: #{pairs(summary.by_kind)}")
    Mix.shell().info("REQUIRED_BY: #{pairs(summary.required_by)}")

    Mix.shell().info(
      "DELTA: #{summary.delta_required} required Postcondition/Invariant/Falsifier, " <>
        "#{summary.witnessed} witnessed ALIVE (#{summary.receipts_alive} ALIVE receipts read), " <>
        "#{summary.orders} work orders"
    )

    Mix.shell().info("propositions.ttl #{summary.propositions_sha256}")
    Mix.shell().info("orders.ttl #{summary.orders_sha256}")
  end

  defp pairs(map),
    do: map |> Enum.sort() |> Enum.map_join(" ", fn {key, count} -> "#{key}=#{count}" end)

  defp refuse(lines) do
    shell = Mix.shell()
    Enum.each(lines, &shell.error/1)
    Mix.shell().error("REFUSED: #{length(lines)} refusal(s); nothing written")
    exit({:shutdown, 1})
  end
end
