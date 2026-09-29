defmodule Mix.Tasks.GgenIgniter.Sa2aDiataxis do
  use Mix.Task

  @shortdoc "Project machine-native SA2A Diátaxis from an admitted manifest"

  @impl Mix.Task
  def run(argv) do
    {opts, _, invalid} =
      OptionParser.parse(argv,
        strict: [manifest: :string, root: :string],
        aliases: [m: :manifest, r: :root]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    manifest_path = opts[:manifest] || Mix.raise("--manifest is required")
    root = opts[:root] || "."

    manifest = manifest_path |> File.read!() |> Jason.decode!()

    case GgenIgniter.SA2ADiataxis.write(manifest, root) do
      {:ok, paths} -> Enum.each(paths, &Mix.shell().info/1)
      {:error, reason} -> Mix.raise("SA2A Diátaxis projection refused: #{inspect(reason)}")
    end
  end
end
