defmodule GgenIgniter.SecurityReview do
  @moduledoc """
  The diff-level security gate: one behaviour plus its `run/2` driver that
  acquires the reviewed diff via `GgenIgniter.SecurityReview.DiffSource`,
  fans it through every `@checks` implementation, dedups the findings,
  delegates ledger persistence to `GgenIgniter.SecurityReview.Receipt`, and
  returns the clear/blocked verdict `Mix.Tasks.GgenIgniter.SecurityReview`
  (exit 5) and `GgenIgniter.SemanticJira.Complete`'s pre-step branch on.

  Structure follows `lib/ggen_igniter/CLAUDE.md`'s top-level-behaviour +
  subdirectory-impl split (`query.ex`/`query/oxigraph.ex` precedent):

    * `GgenIgniter.SecurityReview.Checks.SecretsInDiff` — AWS keys, PEM
      private keys, high-entropy credential assignments (value masked to
      first 4 chars in evidence)
    * `GgenIgniter.SecurityReview.Checks.ShellInterpolation` — `System.cmd`
      with `\#{}`/`<>` command building, `:os.cmd`, `Port.open` shell strings
    * `GgenIgniter.SecurityReview.Checks.PathTraversal` — `File.`/`Path.`
      with `..` concatenation or unvalidated interpolation
    * `GgenIgniter.SecurityReview.Checks.DependencyChange` — any `mix.exs`
      deps block or `mix.lock` line (blocking, never negotiated)
    * `GgenIgniter.SecurityReview.Checks.HookSettingsChange` — added lines
      under `.claude/settings*.json`, `.claude/hooks/**`, hook-wired `.sh`

  Only ADDED diff lines are reviewed (checks see what a change introduces).
  Check evidence is redacted centrally in `run/2`: truncated to 80 chars,
  with secret values masked by the secrets check itself before it returns.

  Findings dedup by stable `id` (`Receipt.finding_id/1`), so the same defect
  reported by two checks — or by two runs against reflowed lines — is one
  finding, and a previously-open finding absent from the current set is
  auto-cleared (`Receipt.write/3`). Verdict: `:blocked` iff any open finding
  remains.

  Typed refusal: `{:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE,
  detail}}` when the base cannot be resolved or the diff cannot be produced —
  the gate never fabricates a diff from a guessed ref.
  """

  @enforce_keys [:category, :file, :rule, :severity, :evidence]
  defstruct [:category, :file, :rule, :severity, :evidence, :line, :id, :first_seen_commit, :state]

  @type severity :: :high | :medium
  @type state :: :open | :auto_cleared

  @type t :: %__MODULE__{
          category: String.t(),
          file: String.t(),
          rule: String.t(),
          severity: severity(),
          evidence: String.t(),
          line: non_neg_integer() | nil,
          id: String.t() | nil,
          first_seen_commit: String.t() | nil,
          state: state() | nil
        }

  @typedoc "What a check receives: the parsed diff plus runtime options."
  @type diff :: GgenIgniter.SecurityReview.DiffSource.diff()

  @typedoc "A check's raw finding — a plain map the driver normalizes into `t:t/0`."
  @type raw_finding :: %{
          required(:category) => String.t(),
          required(:file) => String.t(),
          required(:rule) => String.t(),
          required(:severity) => severity(),
          required(:evidence) => String.t(),
          optional(:line) => non_neg_integer()
        }

  @callback check(diff(), opts :: keyword()) :: [raw_finding()]

  @checks [
    GgenIgniter.SecurityReview.Checks.SecretsInDiff,
    GgenIgniter.SecurityReview.Checks.ShellInterpolation,
    GgenIgniter.SecurityReview.Checks.PathTraversal,
    GgenIgniter.SecurityReview.Checks.DependencyChange,
    GgenIgniter.SecurityReview.Checks.HookSettingsChange
  ]

  @doc "The registered checks, in fan-out order."
  @spec checks() :: [module()]
  def checks, do: @checks

  @max_evidence 80

  @doc """
  Runs the full review over `opts` (`:cwd` repo root, `:base` 40-hex flag,
  `:write` — default true — set false for the read-only `--check` mode, which
  computes the receipt via `Receipt.compute/3` and touches no file).
  `checks_override` replaces `checks/0` — a test seam for fixture diffs, not
  a production config channel. Returns `{:ok, %{status: :clear | :blocked,
  findings: [t()], receipt: map()}}` on a produced diff, or the typed
  `SECURITY_REVIEW_DIFF_UNAVAILABLE` refusal.
  """
  @spec run(keyword(), [module()]) ::
          {:ok, %{status: :clear | :blocked, findings: [t()], receipt: map()}}
          | GgenIgniter.SecurityReview.DiffSource.refusal()
  def run(opts \\ [], checks_override \\ nil) do
    checks = checks_override || @checks
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    commit = current_commit(opts)

    with {:ok, diff} <- GgenIgniter.SecurityReview.DiffSource.run(opts) do
      findings =
        diff
        |> fan(checks, opts)
        |> normalize()
        |> dedup()

      receipt =
        if Keyword.get(opts, :write, true) do
          GgenIgniter.SecurityReview.Receipt.write(findings, cwd, commit)
        else
          previous = GgenIgniter.SecurityReview.Receipt.read_ledger(cwd)

          GgenIgniter.SecurityReview.Receipt.compute(findings, previous, commit)
        end

      status = if open?(receipt), do: :blocked, else: :clear
      {:ok, %{status: status, findings: findings, receipt: receipt}}
    end
  end

  defp fan(diff, checks, opts) do
    Enum.flat_map(checks, fn
      mod when is_atom(mod) -> mod.check(diff, opts)
      fun when is_function(fun, 2) -> fun.(diff, opts)
    end)
  end

  defp normalize(raw) do
    for f <- raw do
      %__MODULE__{
        category: to_string(f.category),
        file: to_string(f.file),
        rule: to_string(f.rule),
        severity: f.severity,
        evidence: truncate(f.evidence)
      }
    end
  end

  defp truncate(evidence) when byte_size(evidence) <= @max_evidence, do: evidence

  defp truncate(evidence), do: binary_part(evidence, 0, @max_evidence)

  # Two checks (or two lines of one check) reporting the same category+file+
  # rule+normalized evidence collapse to one finding — dedup happens before
  # the ledger sees anything.
  defp dedup(findings) do
    Enum.uniq_by(findings, fn f ->
      {f.category, f.file, f.rule, GgenIgniter.SecurityReview.Receipt.normalize_evidence(f.evidence)}
    end)
  end

  defp open?(receipt), do: Enum.any?(receipt["findings"], &(&1["state"] == "open"))

  defp current_commit(opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    case System.cmd("git", ["rev-parse", "HEAD"], cd: cwd, stderr_to_stdout: true) do
      {sha, 0} -> String.trim_trailing(sha)
      {_, _} -> nil
    end
  end
end
