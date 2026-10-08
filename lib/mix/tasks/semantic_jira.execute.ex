defmodule Mix.Tasks.SemanticJira.Execute do
  @shortdoc "Execute one frontier work order end to end and reconcile the receipt"

  @moduledoc """
  Drives ONE frontier-eligible work order through the full in-process chain —
  frontier -> descriptor -> execute -> receipt -> reconcile — and appends the
  standing transition to the ledger. Zero `mix` shell-outs: every hop is a
  function call into `GgenIgniter.SemanticJira.Execute.run/1`, which composes
  the real `TransitionLog`, `Reconciler`, `Descriptor`, `GgenIgniter.Reconcile`,
  `GgenIgniter.GateVerify`, `GgenIgniter.Receipt` and `Reconciler.reconcile/4`.

      mix semantic_jira.execute --work-orders PATH --ledger PATH --identity ID \\
        --verifier-suite SUITE --alias owner/repo=alias \\
        ( --pack-dir PACK --target-dir DIR --receipt-out PATH \\
          | --receipt PATH )
        [--provider NAME] [--court-map PATH] [--authority-graph PATH]
        [--template PATH] [--out-dir DIR] [--out PATH]

  ## Backends (exactly one; anything else is exit 2)

    * **local** — `--pack-dir` + `--target-dir` + `--receipt-out`: first
      enforces the order's `sj:targetPack` against the real pack — when
      the executed order names a target pack (FORMAT-verified at
      admission; `nil` = no constraint), the `--pack-dir` must resolve to
      the same pack name (`pack.toml` `[pack].name` via
      `GgenIgniter.Pack.parse_manifest/1` when present, else the
      directory's basename). A mismatch refuses
      `REFUSED(target_pack_mismatch)` / `mu_unlawful` at the `execute`
      hop BEFORE anything runs — no rev-parse, no pipeline, no receipt,
      ledger byte-unchanged (sync's `GgenIgniter.SemanticJira.TargetPack.
      enforce!/2` enforcement no longer evaporates between sync and
      execute; the pack-lock digest comparison against the sync stamp is
      the disclosed follow-on, not yet this task's law). Then checks
      `git -C <target> rev-parse HEAD` against the order's `base_sha`
      (`base_drift` on drift), runs the real `GgenIgniter.Reconcile.run/1`
      pipeline over the pack (`sync_failed` if it raises), then the real
      fail-closed `GgenIgniter.GateVerify.run/2` + `verify_unbound/2`
      (`verification_failed` on any gate or unbound-fact failure). On
      success it synthesizes the sealed export — bridge echo, outcome
      `partial_alive`, `head_verified` FALSE (honest ceiling: local caps at
      PARTIAL_ALIVE; ALIVE is xaas-fabric-only), `final_head` = 40-hex
      content identity over the actuated file set (not a git sha) — writes
      it to `--receipt-out`, maps it through
      `Descriptor.receipt_from_xaas/2`, and reconciles. A failed
      verification or sync leaves the LEDGER BYTE-UNCHANGED with no
      receipt written.
    * **external** — `--receipt PATH`: the sealed XaaS export arrives as
      data (produced by the xaas fabric elsewhere); only the mapping
      through `Descriptor.receipt_from_xaas/2` and the ledger append run.
      No pack involvement — the fabric owned the execution, so
      `sj:targetPack` is not checked on this backend (and `--receipt` is
      already mutually exclusive with `--pack-dir`/`--target-dir` at exit
      2).

  ## Flags

    * `--work-orders PATH` (required) — JSON array or `{"work_orders": [...]}`
    * `--ledger PATH` (required) — the ndjson standing ledger
    * `--identity ID` (required) — the work order to execute; must be
      frontier-eligible (a blocked order refuses `not_eligible`, an unknown
      one `unknown_identity`, a tampered ledger `ledger_refused`)
    * `--verifier-suite SUITE` — XaaS suite name (required by the descriptor)
    * `--alias owner/repo=alias` — repeatable execution-repo alias
    * `--provider NAME` — default `recipe` (the deterministic RecipeWorker;
      no LLM fallback)
    * `--court-map PATH` — minted court-map JSON (mix semantic_jira.court_map)
    * `--authority-graph PATH` — Turtle origin-authority graph (default:
      the canonical semantic-jira-pack ontology); unreadable is exit 2,
      unparseable is refused `authority_index_unavailable`
    * `--receipt-out PATH` — where the local backend writes the synthesized
      sealed export (required for the local backend)
    * `--template PATH` — explicit template path for the local backend's
      `GgenIgniter.Reconcile.run/1` render on multi-template packs (the
      semantic-jira-pack has 11); single-template packs auto-discover and
      never need it
    * `--out-dir DIR` — on any exit-1 refusal, the same typed map is also
      written to `<DIR>/refused.json`
    * `--out PATH` — on success, the result JSON is also written there

  ## Exit contract

    * `0` — executed (or `already_applied`): one JSON object on stdout
      (`{"status": "executed", ...}` / `{"status": "already_applied", ...}`)
    * `1` — typed refusal: `%{"standing" => "REFUSED", "reason" => ...,
      "broken_term" => ..., "hop" => ..., "detail" => ...}` on stderr
    * `2` — invalid invocation: `{"status": "invalid_invocation", ...}` on
      stderr (missing/ambiguous execution input, unreadable or non-JSON
      file flags)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          work_orders: :string,
          ledger: :string,
          identity: :string,
          verifier_suite: :string,
          alias: :keep,
          provider: :string,
          court_map: :string,
          authority_graph: :string,
          pack_dir: :string,
          target_dir: :string,
          template: :string,
          receipt: :string,
          receipt_out: :string,
          out_dir: :string,
          out: :string
        ]
      )

    opts
    |> GgenIgniter.SemanticJira.Execute.run()
    |> GgenIgniter.SemanticJira.Cli.emit(opts)
  end
end
