defmodule GgenIgniter.SemanticJira.Complete do
  @moduledoc """
  The project-completion driver: loop frontier -> execute -> reconcile over an
  admitted work-order backlog until the frontier is EMPTY.

  Each iteration recomputes the frontier exactly the way
  `GgenIgniter.SemanticJira.Execute.run/1`'s frontier hop does --
  `TransitionLog.fetch/1` -> `Reconciler.project/2` ->
  `Reconciler.frontier/3` -- and drives the FIRST eligible identity through
  `Execute.run/1` verbatim, so every gate the single-order executor enforces
  (target-pack check, base-drift `git rev-parse`, the real pipeline, the
  fail-closed `GateVerify` courts, the receipt seam, the reconciler append)
  holds per order with no reimplementation here. Zero `mix` shell-outs: the
  whole loop is function calls into `TransitionLog`, `Reconciler` and
  `Execute`; eligibility seen here is eligibility execution enforces.

  Fail-closed law:

    * The FIRST per-order exit-1 refusal STOPS the loop. The ledger holds
      only the orders closed before the refusal; the refused identity and
      its full typed verdict are echoed in the completion receipt
      (`"reason" => "order_refused"`), together with the kernel's blocked
      list when the frontier was computable. The refused iteration wrote
      nothing to the ledger (`Execute.run/1`'s own fail-closed property).
    * `--max` (default 1000) bounds the loop. Exhausting it with eligible
      work remaining is a typed exit-1 refusal
      (`"reason" => "max_iterations_exhausted"`, with `remaining_eligible`),
      never a silent partial.
    * A per-order exit-2 invalid invocation passes through verbatim (exit 2)
      -- a broken invocation is not a refusal of any order.

  Completion-receipt status vocabulary:

    * `"complete"` (exit 0) -- the frontier is empty. Blocked orders are
      listed with the kernel's own reason (`"blocked"`); they are settled or
      unadmissible work the kernel reported, not failures.
    * `"refused"` (exit 1) -- the first per-order refusal stopped the loop.
    * `"invalid_invocation"` (exit 2) -- missing/unreadable flags, before
      the loop starts. An authority graph that is present but unparseable as
      Turtle is a typed refusal `authority_index_unavailable` (exit 1), the
      same boundary `Execute.run/1` draws.

  Per-order exit-0 maps are echoed, in close order, under `"orders"`;
  `"closed"` carries the identities in close order.
  """

  alias GgenIgniter.SemanticJira.{Execute, Reconciler, TransitionLog}

  @default_max 1000

  @spec run(keyword()) :: {0 | 1 | 2, map()}
  def run(opts) do
    with {:ok, work_orders} <- work_orders(opts),
         {:ok, ledger} <- required(opts, :ledger),
         :ok <- pack_source_exclusive(opts),
         {:ok, authority_opts} <- authority_graph(opts),
         {:ok, receipt_opts} <- receipt_opts(opts) do
      loop(
        Keyword.merge(opts, receipt_opts),
        work_orders,
        ledger,
        authority_opts,
        [],
        [],
        0
      )
    else
      {:error, {:authority, reason}} ->
        {1,
         %{
           "status" => "refused",
           "reason" => "authority_index_unavailable",
           "detail" => inspect(reason)
         }}

      {:invalid, reason} ->
        {2, %{"status" => "invalid_invocation", "reason" => reason}}
    end
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  # One iteration: recompute the frontier over the CURRENT ledger (the same
  # hops Execute.run/1 runs), take the first eligible identity, drive it
  # through Execute.run/1 verbatim with :identity/:receipt_out merged in.
  defp loop(opts, work_orders, ledger, authority_opts, closed, orders, n) do
    # compile-freeze unblock (smalt ex5 lane, 2026-10-19): max_of/1 is not a
    # macro, so it cannot be called in a guard — hoist it to the body.
    max = max_of(opts)

    with {:ok, events} <- frontier_hop(TransitionLog.fetch(ledger)),
         {:ok, front} <- frontier_hop(Reconciler.frontier(work_orders, events, authority_opts)) do
      case front.eligible do
        [] ->
          complete(opts, ledger, closed, orders, front.blocked)

        [%{"identity" => _identity} | _] when n >= max ->
          {1,
           %{
             "status" => "refused",
             "reason" => "max_iterations_exhausted",
             "detail" => "--max #{max} iterations reached with eligible work remaining",
             "closed" => closed,
             "remaining_eligible" => length(front.eligible)
           }}

        [%{"identity" => identity} | _] ->
          step(opts, work_orders, ledger, authority_opts, closed, orders, n, identity)
      end
    else
      {:error, reason} ->
        {1,
         %{
           "status" => "refused",
           "reason" => "frontier_refused",
           "detail" => inspect(reason)
         }}
    end
  end

  # Exactly one pack source: the fixed --pack-dir OR --packs-root (per-order
  # resolution), never both (exit 2, same boundary as Execute.run/1's backend
  # exclusivity).
  defp pack_source_exclusive(opts) do
    if present?(opts[:pack_dir]) and present?(opts[:packs_root]) do
      {:invalid, "--pack-dir and --packs-root are mutually exclusive"}
    else
      :ok
    end
  end

  defp frontier_hop({:ok, value}), do: {:ok, value}
  defp frontier_hop({:error, reason}), do: {:error, reason}

  # Per-order pack resolution (`--packs-root DIR`): a multi-pack backlog (one
  # project consuming several packs — smalt consumes smalt-substrate-pack AND
  # smalt-semconv-pack) closes in ONE completion run when each order's
  # `sj:targetPack` resolves to `<packs-root>/<target_pack>`. The fixed
  # `--pack-dir` still wins when the executed order names no target pack (or
  # names the same one); `--pack-dir` and `--packs-root` are mutually
  # exclusive at the invocation boundary (exit 2), so the source of the pack
  # is never ambiguous. Execute.run/1's own `sj:targetPack` WORLD check at
  # the execute hop still runs over the resolved dir per order.
  defp maybe_resolve_pack(opts, work_orders, identity) do
    root = opts[:packs_root]
    order = Enum.find(work_orders, &(&1["identity"] == identity))

    if root && order && order["target_pack"] do
      Keyword.put(opts, :pack_dir, Path.join(root, order["target_pack"]))
    else
      opts
    end
  end

  defp step(opts, work_orders, ledger, authority_opts, closed, orders, n, identity) do
    # The per-order sealed export lands at
    # `<receipts-dir>/<sanitized-identity>.json` (the local backend requires
    # a `--receipt-out`; `receipt_opts/1` guarantees the dir when local).
    per_order_receipt =
      if dir = opts[:receipts_dir],
        do: Path.join(dir, sanitize(identity) <> ".json")

    order_opts =
      opts
      |> Keyword.merge(identity: identity)
      |> maybe_resolve_pack(work_orders, identity)
      |> then(
        &if per_order_receipt, do: Keyword.put(&1, :receipt_out, per_order_receipt), else: &1
      )

    # Additive security pre-step (lane L5, 2026-10-20): before any per-order
    # execution, run the diff-level security gate over the current worktree
    # (GgenIgniter.SecurityReview.run/2 — same diff every order would actuate
    # on, so it runs once per order hop, fail-closed). SECURITY_BLOCKED is
    # distinct from :drift's BLOCKED (TaskContract exit code 5 vs 4): open
    # security findings are a refusal this loop records in the completion
    # receipt, never a settled-blocked order.
    case security_pre_step(order_opts) do
      :ok ->
        case Execute.run(order_opts) do
          {0, order_receipt} ->
            loop(
              opts,
              work_orders,
              ledger,
              authority_opts,
              closed ++ [identity],
              orders ++ [order_receipt],
              n + 1
            )

          {1, verdict} ->
            {1,
             %{
               "status" => "refused",
               "reason" => "order_refused",
               "identity" => identity,
               "verdict" => verdict,
               "closed" => closed,
               "closed_count" => length(closed)
             }}

          {2, reason} ->
            {2, reason}
        end

      {:refused, :security_blocked, detail} ->
        {1,
         %{
           "status" => "refused",
           "reason" => "security_blocked",
           "identity" => identity,
           "detail" => detail,
           "closed" => closed,
           "closed_count" => length(closed)
         }}

      {:refused, :security_review_diff_unavailable, detail} ->
        {1,
         %{
           "status" => "refused",
           "reason" => "security_review_diff_unavailable",
           "identity" => identity,
           "detail" => detail,
           "closed" => closed,
           "closed_count" => length(closed)
         }}
    end
  end

  # The gate runs against the completion run's own cwd (opts[:cwd], default
  # File.cwd!()). A `:clear` verdict is :ok and execution proceeds unchanged
  # — the pre-step is purely additive.
  defp security_pre_step(order_opts) do
    cwd = Keyword.get(order_opts, :cwd, File.cwd!())

    # R1-5 (2026-10-20): write: false (--check semantics) — landing must never
    # mutate the tree it is gating; the verdict is identical either way, the
    # ledger/sealed receipt write is the only difference.
    case GgenIgniter.SecurityReview.run(cwd: cwd, write: false) do
      {:ok, %{status: :clear}} ->
        :ok

      {:ok, %{status: :blocked, receipt: receipt}} ->
        open = Enum.filter(receipt["findings"], &(&1["state"] == "open"))

        {:refused, :security_blocked,
         "#{length(open)} open security findings (ledger: #{Path.join(cwd, ".ggen_igniter/security-findings.json")})"}

      {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}} ->
        {:refused, :security_review_diff_unavailable, detail}
    end
  end

  defp complete(_opts, ledger, closed, orders, blocked) do
    # An order this run just closed stands PARTIAL_ALIVE, so the frontier
    # projection lists it under `blocked` (standing=PARTIAL_ALIVE). In the
    # completion receipt those rows are SETTLED, not blocked -- report only
    # genuinely-open blocked rows (identity not closed this run or before).
    open_blocked = Enum.reject(blocked, &(&1["identity"] in closed))

    {0,
     %{
       "status" => "complete",
       "closed" => closed,
       "orders" => orders,
       "blocked" => open_blocked,
       "ledger" => ledger,
       "closed_count" => length(closed),
       "blocked_count" => length(open_blocked)
     }}
  end

  defp max_of(opts), do: opts[:max] || @default_max

  # ── per-order receipt plumbing ──────────────────────────────────────────────

  # The local backend (`--pack-dir` + `--target-dir`) requires a synthesized
  # sealed export per order (`Execute.run/1`'s own `--receipt-out` law), so
  # `--receipts-dir` is required exactly when the local flags are present;
  # each order's export lands at `<receipts-dir>/<sanitized-identity>.json`.
  defp receipt_opts(opts) do
    local? = present?(opts[:pack_dir]) or present?(opts[:target_dir])

    if local? do
      with {:ok, receipts_dir} <- required(opts, :receipts_dir) do
        File.mkdir_p!(receipts_dir)
        {:ok, [receipts_dir: receipts_dir]}
      end
    else
      {:ok, []}
    end
  end

  @doc "The per-order receipt file name: the identity with every character outside [A-Za-z0-9._-] replaced by `_`."
  @spec sanitize(String.t()) :: String.t()
  def sanitize(identity), do: String.replace(identity, ~r/[^A-Za-z0-9._-]/, "_")

  # ── invocation helpers (Execute.run/1's own semantics, reimplemented
  #    locally because its copies are private) ─────────────────────────────────

  defp authority_graph(opts) do
    case Keyword.fetch(opts, :authority_graph) do
      :error ->
        {:ok, []}

      {:ok, path} when is_binary(path) and path != "" ->
        read_authority_graph(path)

      {:ok, _} ->
        {:invalid, "missing --authority-graph"}
    end
  end

  defp read_authority_graph(path) do
    case File.read(path) do
      {:ok, bytes} -> parse_authority_graph(path, bytes)
      {:error, reason} -> {:invalid, "#{path}: #{inspect(reason)}"}
    end
  end

  defp parse_authority_graph(path, bytes) do
    case RDF.Turtle.read_string(bytes) do
      {:ok, graph} ->
        {:ok, [authority: graph]}

      {:error, reason} ->
        {:error, {:authority, {:authority_index_unavailable, path, inspect(reason)}}}
    end
  end

  defp work_orders(opts) do
    with {:ok, decoded} <- json_file(opts, :work_orders) do
      case decoded do
        list when is_list(list) -> {:ok, list}
        %{"work_orders" => list} when is_list(list) -> {:ok, list}
        _ -> {:invalid, "--work-orders must be a JSON array or {\"work_orders\": [...]}"}
      end
    end
  end

  defp json_file(opts, key) do
    with {:ok, path} <- required(opts, key),
         {:ok, body} <- File.read(path) |> or_invalid(path) do
      body |> Jason.decode() |> or_invalid(path)
    end
  end

  defp or_invalid({:ok, _} = ok, _path), do: ok
  defp or_invalid({:error, reason}, path), do: {:invalid, "#{path}: #{inspect(reason)}"}

  defp required(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:invalid, "missing --#{key |> to_string() |> String.replace("_", "-")}"}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
