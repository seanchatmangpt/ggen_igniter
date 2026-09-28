defmodule Mix.Tasks.GgenIgniter.Manifest.Dump do
  # Exit helpers end in `System.halt/1` by design (distinguishable 0/1/2).
  @dialyzer {:no_return, run: 1}
  @dialyzer {:no_return, halt_with: 2}

  @moduledoc """
  `mix ggen_igniter.manifest.dump [--path DIR] [--out FILE]`

  Emits the stable, sorted JSON export of `<DIR>/.ggen_igniter/manifest.json`
  plus `<DIR>/.ggen_igniter/receipts/*.jsonl` (see `GgenIgniter.ManifestExport`)
  to stdout, or to FILE with `--out`. Read-only; identical input yields
  byte-identical output.

  Exit codes: `0` exported; `1` typed refusal (missing/corrupt manifest or
  receipt, stderr `REFUSED:<TYPE> detail`); `2` invalid invocation (unknown
  flag, stray positional, unwritable `--out`).
  """

  use Igniter.Mix.Task

  @shortdoc "Dumps a stable JSON export of the manifest and receipts for third-party replay"
  @example "mix ggen_igniter.manifest.dump --path . --out manifest-export.json"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: @example,
      positional: [],
      schema: [path: :string, out: :string, help: :boolean],
      aliases: [h: :help]
    }
  end

  @impl Mix.Task
  def run(argv) do
    GgenIgniter.TaskShell.run_with_help(
      argv,
      fn ->
        IO.puts("""
        mix ggen_igniter.manifest.dump -- stable JSON export of manifest + receipts

        USAGE
            #{@example}

        FLAGS
            --path DIR   directory holding .ggen_igniter/ (default .)
            --out FILE   write the export to FILE instead of stdout
        """)

        System.halt(0)
      end,
      fn -> dump(argv) end,
      ["--help", "-h"]
    )
  end

  @impl Igniter.Mix.Task
  def igniter(igniter), do: igniter

  defp dump(argv) do
    case OptionParser.parse(argv, strict: [path: :string, out: :string]) do
      {opts, [], []} ->
        export(Keyword.get(opts, :path, "."), opts[:out])

      {_opts, positional, invalid} ->
        halt_with(2, "invalid invocation: #{inspect(invalid ++ positional)}\nusage: #{@example}")
    end
  end

  defp export(dir, out) do
    case GgenIgniter.ManifestExport.dump(dir) do
      {:ok, json} when is_nil(out) ->
        IO.write(json)
        System.halt(0)

      {:ok, json} ->
        case File.write(out, json) do
          :ok ->
            IO.puts("wrote #{out}")
            System.halt(0)

          {:error, reason} ->
            halt_with(2, "cannot write #{out}: #{inspect(reason)}")
        end

      {:error, {type, detail}} ->
        halt_with(1, "REFUSED:#{type |> Atom.to_string() |> String.upcase()} #{detail}")
    end
  end

  defp halt_with(code, message) do
    IO.puts(:stderr, message)
    System.halt(code)
  end
end
