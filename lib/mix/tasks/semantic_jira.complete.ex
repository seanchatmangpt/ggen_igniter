defmodule Mix.Tasks.SemanticJira.Complete do
  @shortdoc "Loop frontier→execute→reconcile until the work-order frontier is empty"

  @moduledoc """
  Drives an admitted work-order backlog to completion: loops frontier ->
  execute -> reconcile until the frontier is EMPTY, delegating every
  per-order execution to `GgenIgniter.SemanticJira.Execute.run/1` verbatim
  (so all of its gates hold per order). Zero `mix` shell-outs.

      mix semantic_jira.complete --work-orders PATH --ledger PATH
        ( --pack-dir PACK --target-dir DIR --receipts-dir DIR
          | --receipt PATH )
        [--template PATH] [--verifier-suite SUITE] [--alias owner/repo=alias]
        [--provider NAME] [--court-map PATH] [--authority-graph PATH]
        [--max N] [--out-dir DIR] [--out PATH]

  ## Flags

    * `--work-orders PATH` (required) — JSON array or `{"work_orders": [...]}`
    * `--ledger PATH` (required) — the ndjson standing ledger
    * `--pack-dir PACK` + `--target-dir DIR` — the local execution backend
      (exactly one backend per invocation, enforced by `Execute.run/1`);
      requires `--receipts-dir`
    * `--receipts-dir DIR` — where each order's synthesized sealed export is
      written: `<DIR>/<sanitized-identity>.json` (every character outside
      `A-Za-z0-9._-` replaced by `_`); required for the local backend
    * `--template PATH` — explicit template path for multi-template packs
      (single-template packs auto-discover)
    * `--verifier-suite SUITE` — XaaS suite name (required by the descriptor)
    * `--alias owner/repo=alias` — repeatable execution-repo alias
    * `--provider NAME` — default `recipe` (the deterministic RecipeWorker)
    * `--court-map PATH` — minted court-map JSON (mix semantic_jira.court_map)
    * `--authority-graph PATH` — Turtle origin-authority graph (default: the
      canonical semantic-jira-pack ontology); unreadable is exit 2,
      unparseable is refused `authority_index_unavailable`
    * `--max N` — iteration bound (default 1000); exhausting it with
      eligible work remaining is a typed refusal, never a silent partial
    * `--out-dir DIR` — reserved for refusals (unused on the success path)
    * `--out PATH` — on success, the result JSON is also written there

  ## Exit contract

    * `0` — `"complete"`: the frontier is empty. One JSON object on stdout
      with `closed` (identities in close order), `orders` (the per-order
      exit-0 maps in close order), `blocked` (the kernel's blocked rows,
      with their own reasons — settled work, not failures), `ledger`,
      `closed_count`, `blocked_count`
    * `1` — `"refused"`: the FIRST per-order refusal stopped the loop
      (`reason: "order_refused"`, the refused `identity` and its full typed
      `verdict` echoed, plus `closed`/`closed_count`), or the iteration
      bound was hit (`reason: "max_iterations_exhausted"` with
      `remaining_eligible`), or the frontier itself refused
      (`reason: "frontier_refused"`). The ledger holds only the orders
      closed before the refusal; the refused iteration wrote nothing.
    * `2` — `"invalid_invocation"`: missing/unreadable/non-JSON flags
      (passed through verbatim from `Execute.run/1`'s invocation boundary)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          work_orders: :string,
          ledger: :string,
          pack_dir: :string,
          target_dir: :string,
          receipts_dir: :string,
          template: :string,
          verifier_suite: :string,
          alias: :keep,
          provider: :string,
          court_map: :string,
          authority_graph: :string,
          max: :integer,
          out_dir: :string,
          out: :string
        ]
      )

    opts
    |> GgenIgniter.SemanticJira.Complete.run()
    |> GgenIgniter.SemanticJira.Cli.emit(opts)
  end
end
