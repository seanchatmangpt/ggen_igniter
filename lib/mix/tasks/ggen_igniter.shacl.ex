defmodule Mix.Tasks.GgenIgniter.Shacl do
  @dialyzer {:no_return, print_help: 0}
  @shortdoc "Validates any RDF data file against a SHACL shapes file (supported subset only)"

  @moduledoc """
  Standalone SHACL entry point over `GgenIgniter.SemanticJira.Shacl.validate_file/2`.

      mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--fail-on-unsupported]

  Supports only the SHACL subset documented in `GgenIgniter.SemanticJira.Shacl`;
  unsupported constructs are ALWAYS reported (never silently ignored). Exit `0`
  conforms, `1` violations (or unsupported constructs with `--fail-on-unsupported`),
  `2` invocation. See `docs/reference/cli/shacl.md`.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.SemanticJira.Shacl

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: "mix ggen_igniter.shacl --data data.ttl --shapes shapes.ttl",
      positional: [],
      schema: [
        data: :string,
        shapes: :string,
        json: :boolean,
        fail_on_unsupported: :boolean,
        help: :boolean
      ],
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

    for key <- [:data, :shapes] do
      unless is_binary(opts[key]) and File.regular?(opts[key]) do
        Mix.shell().error("ggen_igniter.shacl: --#{key} FILE is required and must exist")
        System.halt(2)
      end
    end

    report =
      try do
        Shacl.validate_file(opts[:data], opts[:shapes])
      rescue
        e ->
          Mix.shell().error("ggen_igniter.shacl: cannot load input: #{Exception.message(e)}")
          System.halt(2)
      end

    {unsupported, violations} =
      Enum.split_with(report.violations, &(&1.constraint == :unsupported_constraint))

    code =
      cond do
        violations != [] -> 1
        unsupported != [] and opts[:fail_on_unsupported] -> 1
        true -> 0
      end

    if opts[:json] do
      Mix.shell().info(json(report, violations, unsupported, code))
    else
      human(report, violations, unsupported)
    end

    System.halt(code)
  end

  defp json(report, violations, unsupported, code) do
    Jason.encode!(%{
      schema_version: 1,
      conforms: violations == [] and unsupported == [],
      exit_code: code,
      shapes_checked: report.shapes_checked,
      focus_node_count: report.focus_node_count,
      violations: Enum.map(violations, &clean/1),
      unsupported: Enum.map(unsupported, &clean/1)
    })
  end

  defp clean(v),
    do: v |> Map.update!(:constraint, &to_string/1) |> Map.update(:value, nil, &stringify/1)

  defp stringify(nil), do: nil
  defp stringify(v) when is_binary(v) or is_number(v) or is_boolean(v), do: v
  defp stringify(v), do: inspect(v)

  defp human(report, violations, unsupported) do
    Mix.shell().info(
      "shapes checked: #{Enum.join(report.shapes_checked, ", ")} (#{report.focus_node_count} focus nodes)"
    )

    for v <- violations do
      Mix.shell().info(
        "VIOLATION shape=#{v.shape} focus=#{v.focus_node} path=#{v.path || "-"} " <>
          "constraint=#{v.constraint} #{v.message || ""}"
      )
    end

    for u <- unsupported do
      Mix.shell().info(
        "UNSUPPORTED shape=#{u.shape} focus=#{u.focus_node || "-"} #{u.message || ""}"
      )
    end

    if violations == [] and unsupported == [], do: Mix.shell().info("CONFORMS")
  end

  defp print_help do
    Mix.shell().info("""
    usage: mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--fail-on-unsupported]

    Exit 0 conforms, 1 violations (or unsupported with --fail-on-unsupported), 2 invocation.
    Supports only the SHACL subset documented in GgenIgniter.SemanticJira.Shacl.
    """)
  end
end
