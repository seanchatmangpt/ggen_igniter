defmodule Mix.Tasks.GgenIgniter.Epoch.Watermark do
  @shortdoc "Stamps the pre-epoch implementation identity (path + blob SHA) at a CalVer boundary"

  @moduledoc """
  Records which implementation files exist, as exactly which git blob SHAs,
  at the moment an epoch closes — the identity the
  `ggen_igniter.epoch.check` freshness court judges a candidate tree
  against.

      mix ggen_igniter.epoch.watermark --epoch v26.10.1 [--base-dir DIR] \\
        [--glob "lib/**/*.ex"] [--restamp REASON]

  Identity-based by design: `git blame` attributes a delete-and-re-added
  file to the re-adding commit, so the boundary is stamped as exact blob
  identities instead of authorship history. Re-stamping the same epoch over
  an UNCHANGED tree is idempotent; over a CHANGED tree it is refused unless
  `--restamp REASON` is passed (the reason is recorded in the manifest —
  redefining what "legacy" means for an epoch is not an invisible act).

  Exit `0` stamped (or idempotent no-op), `1` refused (typed JSON on
  stderr), `2` bad invocation.
  """

  use Mix.Task

  alias GgenIgniter.EpochWatermark

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, invalid} =
      OptionParser.parse(argv,
        strict: [epoch: :string, base_dir: :string, glob: :string, restamp: :string],
        aliases: [e: :epoch, d: :base_dir, g: :glob]
      )

    unless invalid == [] and is_binary(opts[:epoch]) do
      usage()
      System.halt(2)
    end

    base_dir = Keyword.get(opts, :base_dir, File.cwd!())
    stamp_opts = build_opts(opts)

    case EpochWatermark.stamp!(base_dir, opts[:epoch], stamp_opts) do
      {:ok, manifest, path} ->
        Mix.shell().info(Jason.encode!(manifest, pretty: true))

        Mix.shell().info(
          "epoch watermark: #{manifest["epoch"]} files=#{length(manifest["files"])} " <>
            "head=#{String.slice(manifest["head_sha"], 0, 12)} -> #{path}"
        )

      {:error, {:refused_epoch_watermark, %{code: code, detail: detail}}} ->
        Mix.shell().error(
          Jason.encode!(%{
            "refused" => "EPOCH_WATERMARK",
            "code" => to_string(code),
            "detail" => detail
          })
        )

        System.halt(1)
    end
  end

  defp build_opts(opts) do
    []
    |> maybe_put(:glob, opts[:glob])
    |> maybe_put(:restamp, restamp(opts[:restamp]))
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  # A bare --restamp with no reason does not define a reason; the refusal
  # path stays required to name WHY the boundary is being redefined.
  defp restamp(nil), do: false

  defp restamp(""), do: false

  defp restamp(reason), do: %{reason: reason}

  defp usage do
    Mix.shell().error("""
    usage: mix ggen_igniter.epoch.watermark --epoch LABEL [--base-dir DIR] [--glob GLOB] [--restamp REASON]
    """)
  end
end
