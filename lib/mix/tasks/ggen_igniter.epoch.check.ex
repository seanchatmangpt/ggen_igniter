defmodule Mix.Tasks.GgenIgniter.Epoch.Check do
  @shortdoc "Proves a candidate tree's implementation freshness against an epoch watermark"

  @moduledoc """
  The epoch self-gate — the WITNESS. Judges every implementation-plane
  file in the tree against the watermark stamped for the epoch and refuses
  anything carried over from the pre-epoch implementation.

      mix ggen_igniter.epoch.check --epoch v26.10.1 [--base-dir DIR] \\
        [--threshold F] [--report PATH]

  Two-layer law: admission (`semantic_jira.admit_candidates --epoch-manifest`)
  refuses known-illegal plans before they run; this check proves the
  resulting BYTES afterwards; promotion requires both. Admission ≠ proof,
  proof ≠ prevention.

  Detector law: receipts admit; similarity falsifies; blame informs. A
  refusal exit of 1 is the DESIGNED outcome for a legacy-carrying tree —
  a verdict, not a crash.

  Exit `0` every file ALIVE, `1` any refusal/unknown (report JSON printed),
  `2` bad invocation.
  """

  use Mix.Task

  alias GgenIgniter.EpochFreshness

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [epoch: :string, base_dir: :string, threshold: :float, report: :string],
        aliases: [e: :epoch, d: :base_dir, t: :threshold, r: :report]
      )

    unless invalid == [] and is_binary(opts[:epoch]) do
      usage()
      System.halt(2)
    end

    base_dir = Keyword.get(opts, :base_dir, File.cwd!())

    check_opts =
      []
      |> maybe_put(:threshold, opts[:threshold])
      |> maybe_put(:report_path, opts[:report])

    case EpochFreshness.check(base_dir, opts[:epoch], check_opts) do
      {:ok, report} ->
        Mix.shell().info(Jason.encode!(report, pretty: true))

        counts = report["implementation_files"]

        Mix.shell().info(
          "epoch check: standing=#{report["standing"]} " <>
            "admitted_generated=#{counts["admitted_generated"]} " <>
            "admitted_residue=#{counts["admitted_residue"]} refused=#{counts["refused"]}"
        )

        if report["standing"] == :ALIVE, do: :ok, else: System.halt(1)

      {:error, {:refused_epoch_check, %{code: code, detail: detail}}} ->
        Mix.shell().error(
          Jason.encode!(%{
            "refused" => "EPOCH_CHECK",
            "code" => to_string(code),
            "detail" => detail
          })
        )

        System.halt(1)
    end
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp usage do
    Mix.shell().error("""
    usage: mix ggen_igniter.epoch.check --epoch LABEL [--base-dir DIR] [--threshold F] [--report PATH]
    """)
  end
end
