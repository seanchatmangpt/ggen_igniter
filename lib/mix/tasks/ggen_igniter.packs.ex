defmodule Mix.Tasks.GgenIgniter.Packs do
  @dialyzer {:no_return, print_help: 0}
  @shortdoc "Lists discoverable packs (name, version, ontology, gates, templates, hex-shipped)"

  @moduledoc """
  Pack discovery: replaces `ls priv/ggen` with structured output from
  `GgenIgniter.PackCatalog`.

      mix ggen_igniter.packs [--json] [--pack-dir DIR] [--name NAME]

  See `docs/reference/cli/packs-list.md`. Exit `0` on success, `2` on an unknown
  `--name` or bad invocation. Read-only.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.PackCatalog

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: "mix ggen_igniter.packs --json",
      positional: [],
      schema: [json: :boolean, pack_dir: :string, name: :string, help: :boolean],
      aliases: [h: :help],
      required: []
    }
  end

  @impl Mix.Task
  def run(argv) do
    GgenIgniter.TaskShell.run_with_help(
      argv,
      fn ->
        print_help()
        System.halt(0)
      end,
      fn -> super(argv) end
    )
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options

    if opts[:help] do
      print_help()
      System.halt(0)
    end

    if igniter.args.positional != %{} and map_size(igniter.args.positional) > 0 do
      bad("unexpected positional arguments")
    end

    packs = PackCatalog.list(pack_dir: opts[:pack_dir])

    packs =
      case opts[:name] do
        nil ->
          packs

        name ->
          case Enum.filter(packs, &(&1.name == name or Path.basename(&1.dir) == name)) do
            [] -> bad("unknown pack #{inspect(name)}")
            found -> found
          end
      end

    if opts[:json] do
      Mix.shell().info(Jason.encode!(%{schema_version: 1, packs: Enum.map(packs, &jsonable/1)}))
    else
      Enum.each(packs, &print_pack/1)
    end

    System.halt(0)
  end

  defp bad(msg) do
    Mix.shell().error("ggen_igniter.packs: #{msg}")
    System.halt(2)
  end

  # Stable sorted-key JSON: Jason encodes maps via Jason.OrderedObject when given
  # a keyword-ordered structure; we sort keys explicitly.
  defp jsonable(%{} = m) when not is_struct(m) do
    m
    |> Enum.map(fn {k, v} -> {to_string(k), jsonable(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)

  defp jsonable(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom),
    do: Atom.to_string(atom)

  defp jsonable(other), do: other

  defp print_pack(p) do
    Mix.shell().info(
      "#{p.name}  version=#{p.version || "-"}  hex_shipped=#{p.hex_shipped}  " <>
        "meta=#{p.metadata_source}  dir=#{p.dir}"
    )

    Mix.shell().info("  ontology: #{p.ontology || "-"}")
    Mix.shell().info("  gates: #{Enum.map_join(p.gates, ", ", & &1.name)}")

    Mix.shell().info(
      "  templates: " <>
        Enum.map_join(p.templates, ", ", &"#{&1.stem} -> #{&1.to || "?"}")
    )

    if p.required_flags != [],
      do: Mix.shell().info("  required flags: #{Enum.join(p.required_flags, "; ")}")
  end

  defp print_help do
    Mix.shell().info("""
    usage: mix ggen_igniter.packs [--json] [--pack-dir DIR] [--name NAME]

    Lists packs under priv/ggen (plus DIR when given). Exit 0 ok, 2 unknown --name/bad invocation.
    """)
  end
end
