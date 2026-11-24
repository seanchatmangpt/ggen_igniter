defmodule Mix.Tasks.GgenIgniter.Parity do
  @shortdoc "Diff ggen's Rust Frontmatter fields against igniter's (fail-closed)"

  @moduledoc """
  Prints the frontmatter parity table (`GgenIgniter.Parity`). Exit 0 = every Rust field is
  mirrored; exit 1 = a Rust field is missing; exit 0 with a `[SKIP]` line only when the ggen
  checkout is absent.

      mix ggen_igniter.parity [--ggen-dir ~/ggen]
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [ggen_dir: :string])
    popts = if opts[:ggen_dir], do: [ggen_dir: Path.expand(opts[:ggen_dir])], else: []

    case GgenIgniter.Parity.check(popts) do
      {:ok, rows} ->
        Mix.shell().info(GgenIgniter.Parity.render(rows))

      {:skip, why} ->
        Mix.shell().info("[SKIP] #{why}")

      {:error, rows} ->
        Mix.shell().error(GgenIgniter.Parity.render(rows))
        System.halt(1)
    end
  end
end
