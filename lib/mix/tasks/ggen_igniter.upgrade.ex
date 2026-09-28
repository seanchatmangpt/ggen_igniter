defmodule Mix.Tasks.GgenIgniter.Upgrade do
  @moduledoc """
  Runs ggen_igniter's version-keyed consumer upgraders. Invoked by
  `mix igniter.upgrade ggen_igniter` as `ggen_igniter.upgrade FROM TO`; may also be run
  directly. Dispatch and range selection live in `GgenIgniter.Upgrades`.

  A downgrade (`TO < FROM`) or an unparseable version is a typed refusal
  (an Igniter issue; nothing is written). `FROM == TO` is a no-op.
  """

  use Igniter.Mix.Task

  @example "mix ggen_igniter.upgrade 26.9.24 26.9.28"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: @example,
      positional: [:from, :to],
      schema: [help: :boolean],
      aliases: [h: :help]
    }
  end

  @impl Mix.Task
  def run(argv) do
    GgenIgniter.TaskShell.run_with_help(
      argv,
      fn ->
        IO.puts("""
        mix ggen_igniter.upgrade -- runs version-keyed consumer upgraders

        USAGE
            #{@example}
        """)

        System.halt(0)
      end,
      fn -> super(argv) end,
      ["--help", "-h"]
    )
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    %{from: from, to: to} = igniter.args.positional

    case GgenIgniter.Upgrades.select(from, to) do
      {:ok, mods} ->
        Enum.reduce(mods, igniter, fn mod, ig -> mod.upgrade(ig, igniter.args.options) end)

      {:error, {:invalid_version, v}} ->
        Igniter.add_issue(igniter, "REFUSED:UPGRADE_INVALID_VERSION #{v}")

      {:error, {:downgrade, f, t}} ->
        Igniter.add_issue(igniter, "REFUSED:UPGRADE_DOWNGRADE #{f} -> #{t}")
    end
  end
end
