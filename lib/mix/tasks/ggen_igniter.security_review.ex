defmodule Mix.Tasks.GgenIgniter.SecurityReview do
  # `run/1` ends in `System.halt/1` on every real exit path (0/5/2) — the
  # whole contract is a distinguishable process exit code a CI step branches
  # on. Dialyzer correctly flags the no-local-return; that is the intended
  # CLI-exit contract, not a bug.
  @dialyzer {:no_return, halt: 1}

  @moduledoc """
  The CLI hop of the diff-level security gate
  (`GgenIgniter.SecurityReview`): reviews the added lines of the working
  diff (`--base` 40-hex SHA, else merge-base with the default branch, else
  `HEAD~1`) through the five registered checks and exits on the
  `GgenIgniter.TaskContract` code table.

      mix ggen_igniter.security_review [--base SHA] [--cwd DIR]
                                       [--receipt-out FILE] [--json] [--check]

  ## Exit codes (`GgenIgniter.TaskContract.exit_codes/0`)

    * `0` — review ran, no open security findings (`:ok` / ALIVE)
    * `5` — review ran, open findings block landing (`:security_blocked` /
      SECURITY_BLOCKED — distinct from `:drift`'s BLOCKED: the tree is not
      stale, the diff carries open security findings)
    * `2` — invalid invocation (bad flag, unresolvable base)
    * `1` — typed refusal `REFUSED:SECURITY_REVIEW_DIFF_UNAVAILABLE` (the
      diff could not be produced)

  `--check` is the read mode: the review runs and reports but writes no
  ledger/sealed copy. `--json` prints the `TaskContract.envelope/3` shape;
  `--receipt-out FILE` additionally writes the envelope to FILE.
  """

  use Mix.Task

  alias GgenIgniter.{SecurityReview, TaskContract}

  @shortdoc "Reviews the working diff for security findings (exit 5 = blocked)"

  @switches [
    base: :string,
    cwd: :string,
    receipt_out: :string,
    json: :boolean,
    check: :boolean,
    help: :boolean
  ]

  @aliases [h: :help]

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      opts[:help] ->
        print_help_and_halt()

      invalid != [] ->
        invalid_invocation("unrecognized flag(s): #{inspect(invalid)}", opts)

      true ->
        review(opts)
    end
  end

  defp review(opts) do
    cwd = opts[:cwd] || File.cwd!()
    run_opts = [cwd: cwd, base: opts[:base], write: !opts[:check]]

    case SecurityReview.run(run_opts) do
      {:ok, %{status: :clear, findings: findings, receipt: receipt}} ->
        emit(findings, receipt, opts, :ok)

      {:ok, %{status: :blocked, findings: findings, receipt: receipt}} ->
        emit(findings, receipt, opts, :security_blocked)

      {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}} ->
        envelope =
          TaskContract.envelope("security_review", :refusal,
            refusal: {:SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}
          )

        print_and_write(envelope, opts)
        halt(1)
    end
  end

  defp emit(findings, receipt, opts, outcome) do
    envelope =
      TaskContract.envelope("security_review", outcome,
        data: %{
          "open_count" => receipt["open_count"],
          "findings" => Enum.map(findings, &finding_summary/1)
        },
        refusal:
          if(outcome == :security_blocked,
            do:
              {:SECURITY_BLOCKED,
               "#{receipt["open_count"]} open security findings (digest: #{digest(findings)})"},
            else: nil
          )
      )

    print_and_write(envelope, opts)

    case outcome do
      :ok -> halt(0)
      :security_blocked -> halt(5)
    end
  end

  defp finding_summary(f) do
    %{
      "id" => GgenIgniter.SecurityReview.Receipt.finding_id(%{
        category: f.category,
        file: f.file,
        rule: f.rule,
        evidence: f.evidence
      }),
      "category" => f.category,
      "file" => f.file,
      "line" => f.line,
      "severity" => to_string(f.severity)
    }
  end

  # A short deterministic digest of the open-finding id set, for the refusal
  # detail line — enough to tell two different blocked states apart without
  # re-printing every finding.
  defp digest(findings) do
    payload =
      findings
      |> Enum.map(&GgenIgniter.SecurityReview.Receipt.finding_id(%{
        category: &1.category,
        file: &1.file,
        rule: &1.rule,
        evidence: &1.evidence
      }))
      |> Enum.sort()
      |> Enum.join(",")

    <<d::binary-size(4), _::binary>> = :crypto.hash(:sha256, payload)
    Base.encode16(d, case: :lower)
  end

  defp print_and_write(envelope, opts) do
    json = TaskContract.encode(envelope)

    if opts[:json] do
      Mix.shell().info(json)
    else
      Mix.shell().info(human_lines(envelope))
    end

    if path = opts[:receipt_out] do
      File.write!(path, json <> "\n")
    end
  end

  defp human_lines(envelope) do
    case envelope["refusal"] do
      %{"code" => "SECURITY_BLOCKED", "detail" => detail} ->
        "security_review: BLOCKED (exit 5) — #{detail}"

      %{"code" => code, "detail" => detail} ->
        "security_review: #{code} — #{detail}"

      nil ->
        "security_review: clear (exit 0) — no open security findings"
    end
  end

  defp invalid_invocation(message, opts) do
    Mix.shell().error("ggen_igniter.security_review: #{message}")

    if opts[:json] do
      Mix.shell().info(Jason.encode!(%{"error" => message}))
    end

    halt(2)
  end

  # Plain `use Mix.Task` (the `replay.ex` shape): no Igniter runner prints a
  # trailing footer after us, so there is no `--json` corruption quirk to
  # work around — but the exit contract still needs the real `System.halt/1`
  # so 0/1/2/5 are distinguishable process exit codes.
  defp halt(code), do: System.halt(code)

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.security_review [--base SHA] [--cwd DIR]
                                     [--receipt-out FILE] [--json] [--check]

    Reviews the added lines of the working diff through the five registered
    security checks (secrets, shell interpolation, path traversal, dependency
    change, hook/settings change) and exits on the TaskContract table.

    FLAGS
        --base SHA          40-hex commit to diff against (default:
                            merge-base with main/master, else HEAD~1)
        --cwd DIR           repo root to review (default: cwd)
        --receipt-out FILE  also write the JSON envelope to FILE
        --json              print the TaskContract envelope (machine-readable)
        --check             read mode: report only, write no ledger/sealed copy
        --help, -h          this help, exit 0

    EXIT CODES
        0  clear — no open security findings
        1  REFUSED:SECURITY_REVIEW_DIFF_UNAVAILABLE — diff could not be produced
        2  invalid invocation
        5  SECURITY_BLOCKED — open security findings block landing
    """)

    halt(0)
  end
end
