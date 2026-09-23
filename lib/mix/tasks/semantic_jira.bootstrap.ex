defmodule Mix.Tasks.SemanticJira.Bootstrap do
  @shortdoc "Cold bootstrap: reconstruct sJira state from durable artifacts only (GC23-1)."

  @moduledoc """
  Cold bootstrap (GC-26.9.23 gate GC23-1; PRD section 8.1, ARD section 16).
  Thin CLI over `GgenIgniter.SemanticJira.Bootstrap.run/1`: reconstructs the
  current subjects and exact SHAs, capabilities, authority rules, the active
  GoalCheckpoint (root + gates), per-order derived standing, the frontier
  (`GgenIgniter.SemanticJira.frontier_from_events/3`) and the
  BLOCKED/UNSUPPORTED/REFUSED state from git refs, canonical RDF, receipts,
  the TransitionLog and the provider registry -- never from a transcript,
  `~/.claude`, `~/.zcode` or conversation memory.

  ## Usage

      mix semantic_jira.bootstrap --fleet matrix.ttl|universe.json --goal goal.ttl \\
        [--graphs work-graph.ttl|work-orders.json]... [--receipts-dir DIR]... \\
        --ledger LEDGER [--registry recipes.json] [--checkout owner/repo=DIR]... \\
        --out state.json [--pack-dir DIR]

  `--graphs`, `--receipts-dir` and `--checkout` repeat (one value each).
  The output is canonical JSON (keys sorted, no timestamps, no absolute
  paths): `{"state": {...}, "state_digest": "sha256:..."}`, where
  `state_digest` is the sha256 of the canonical JSON of `state`. Two runs
  over the same artifacts write byte-identical files.

  Prints `STATE_DIGEST <digest>`, a one-line summary and `WROTE <out>`, exit
  0. A typed refusal prints one `REFUSED(<code>) <subject>: <detail>` line per
  refusal on stderr and exits 1, writing nothing: `llm_credential_present`
  (an `ANTHROPIC_*`/`CLAUDE_*`/`OPENAI_*`/`ZAI_*`/`Z_AI_*`/`GLM_*`/`ZCODE_*`
  variable is set; broken_term `mu_on_O`), `forbidden_input` (a path under
  `.claude`/`.zcode` or naming a transcript), `input_unreadable`,
  `input_invalid`, `goal_root`, `duplicate_work_order`, `ledger_refused`,
  `absolute_path_in_state`, `usage`.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira.Bootstrap
  alias GgenIgniter.SemanticJira.Bootstrap.Guard

  @switches [
    fleet: :string,
    goal: :string,
    graphs: :keep,
    receipts_dir: :keep,
    ledger: :string,
    registry: :string,
    checkout: :keep,
    out: :string,
    pack_dir: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] or positional != [] ->
        refuse(["REFUSED(usage) -: unexpected arguments #{inspect(invalid ++ positional)}"])

      opts[:out] in [nil, ""] ->
        refuse(["REFUSED(usage) -: --out is required"])

      reason = Guard.forbidden_path(opts[:out]) ->
        refuse(["REFUSED(forbidden_input) out: #{reason}"])

      true ->
        opts |> bootstrap_opts() |> Bootstrap.run() |> finish(opts[:out])
    end
  end

  defp bootstrap_opts(opts) do
    [
      fleet: opts[:fleet],
      goal: opts[:goal],
      ledger: opts[:ledger],
      registry: opts[:registry],
      graphs: Keyword.get_values(opts, :graphs),
      receipts_dirs: Keyword.get_values(opts, :receipts_dir),
      checkouts: Keyword.get_values(opts, :checkout)
    ]
    |> then(fn base ->
      if opts[:pack_dir], do: Keyword.put(base, :pack_dir, opts[:pack_dir]), else: base
    end)
  end

  defp finish({:refused, refusals}, _out),
    do: refuse(Enum.map(refusals, &Bootstrap.render_refusal/1))

  defp finish({:ok, result}, out) do
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Bootstrap.document(result))
    orders = result.state["orders"]
    classes = orders |> Map.values() |> Enum.frequencies_by(& &1["frontier"])
    critical = Enum.count(orders, fn {_id, order} -> order["critical_path"] end)

    Mix.shell().info("STATE_DIGEST #{result.digest}")

    Mix.shell().info(
      "ORDERS #{map_size(orders)} (critical_path #{critical}) FRONTIER " <>
        Enum.map_join(Enum.sort(classes), " ", fn {class, n} -> "#{class}=#{n}" end) <>
        " SUBJECTS #{length(result.state["subjects"])} RECEIPTS #{length(result.state["receipts"])}"
    )

    Mix.shell().info("WROTE #{out}")
  end

  defp refuse(lines) do
    shell = Mix.shell()
    Enum.each(lines, &shell.error/1)
    shell.error("REFUSED: #{length(lines)} refusal(s); nothing written")
    exit({:shutdown, 1})
  end
end
