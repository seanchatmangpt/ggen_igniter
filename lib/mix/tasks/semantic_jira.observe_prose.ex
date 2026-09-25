defmodule Mix.Tasks.SemanticJira.ObserveProse do
  @shortdoc "Observes prose candidates into a stamped propositions.ttl (SJ-002: Prose never manufactures WorkOrders)."

  @moduledoc """
  First-mile observer (GC-26.9.23 gates GC23-0 and GC23-2; PRD PR-002..PR-005,
  ARD sections 5 and 17). Thin CLI over `GgenIgniter.SemanticJira.Prose`:
  provenance binding -> SHACL admission -> observation stamp
  (`sj:candidateStanding "UNKNOWN"`, `sj:authorityClaim "NONE"`) -> domain
  rules (contradiction, foreign requirement, gate coverage) -> sorted
  N-Triples output.

  Prose never manufactures WorkOrders (SJ-002: Prose ↛ WorkOrder): the only
  output is `propositions.ttl`.

  No LLM, network model API or clock participates: the observation replays
  byte-identically (ARD section 5.5).

  ## Usage

      mix semantic_jira.observe_prose --source prose.md --candidates candidates.ttl \\
        --goal goal.ttl --out-dir DIR [--check] [--pack-dir DIR]

  ## Flags

    * `--source PATH` -- the accepted prose (its bytes are the provenance).
    * `--candidates PATH` -- PVOCAB candidate Turtle (`sj:Proposition`s).
    * `--goal PATH` -- the goal graph; its single root GoalCheckpoint (children,
      no parent) defines the gates and the instance namespace.
    * `--out-dir DIR` -- where `propositions.ttl` is written.
    * `--check` -- write nothing; exit 0 only when `--out-dir` already holds
      the byte-identical output.
    * `--pack-dir DIR` -- defaults to `priv/ggen/semantic-jira-pack`.
    * `--admit-goal` -- GC23-3 shapes court plus authority stamping instead of
      an observation: validate `--goal` merged with the pack ontology and every
      `--context PATH` (repeatable; e.g. the predecessor goal) against the pack
      shapes, with violations scoped to the goal's own subjects, then delegate
      authority stamping to `GgenIgniter.SemanticJira.Authority.admit/2`.
      Needs only `--goal`.

  Exits 0 only when admission and coverage pass (and, with `--check`, the
  output recomputes byte-identically); otherwise prints one
  `REFUSED(<code>) <subject>: <detail>` line per refusal and exits 1.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Prose

  @switches [
    source: :string,
    candidates: :string,
    goal: :string,
    out_dir: :string,
    pack_dir: :string,
    check: :boolean,
    admit_goal: :boolean,
    context: :keep
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] or positional != [] ->
        refuse(["REFUSED(usage) -: unexpected arguments #{inspect(invalid ++ positional)}"])

      opts[:admit_goal] ->
        admit_goal(opts)

      opts[:out_dir] == nil ->
        refuse(["REFUSED(usage) -: --out-dir is required"])

      true ->
        opts |> observe_opts() |> Prose.observe() |> finish(opts)
    end
  end

  defp admit_goal(opts) do
    goal_opts = [
      goal: opts[:goal],
      context: Keyword.get_values(opts, :context),
      pack_dir: opts[:pack_dir] || "priv/ggen/semantic-jira-pack"
    ]

    case Prose.admit_goal(goal_opts) do
      {:ok, summary} ->
        Mix.shell().info(
          "GOAL ADMITTED: #{opts[:goal]} (#{summary.goal_checkpoints} GoalCheckpoints, " <>
            "#{map_size(summary.stamped)} authorities stamped)"
        )

      {:refused, refusals} ->
        refuse(Enum.map(refusals, &Prose.render_refusal/1))
    end
  end

  defp observe_opts(opts), do: Keyword.take(opts, [:source, :candidates, :goal, :pack_dir])

  defp finish({:refused, refusals}, _opts),
    do: refuse(Enum.map(refusals, &Prose.render_refusal/1))

  defp finish({:ok, result}, opts) do
    if opts[:check] do
      case Prose.check(result, opts[:out_dir]) do
        :ok ->
          print_observed(result.summary)

          Mix.shell().info(
            "CHECK: #{Path.join(opts[:out_dir], "propositions.ttl")} recomputes byte-identically"
          )

        {:refused, refusals} ->
          refuse(Enum.map(refusals, &Prose.render_refusal/1))
      end
    else
      Prose.write!(result, opts[:out_dir])
      print_observed(result.summary)
      Mix.shell().info("propositions.ttl sha256:#{result.summary.propositions_sha256}")
      Mix.shell().info("WROTE: #{Path.join(opts[:out_dir], "propositions.ttl")}")
    end
  end

  defp print_observed(summary) do
    Mix.shell().info(
      "OBSERVED: #{summary.observed} candidate propositions " <>
        "(#{summary.required} required, #{summary.not_required} not required)"
    )

    Mix.shell().info("KINDS: #{pairs(summary.by_kind)}")
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
