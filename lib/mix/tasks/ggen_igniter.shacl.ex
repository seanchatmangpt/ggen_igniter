defmodule Mix.Tasks.GgenIgniter.Shacl do
  @dialyzer {:no_return, print_help: 0}
  @shortdoc "Validates any RDF data file against a SHACL shapes file (supported subset only)"

  @moduledoc """
  Standalone SHACL entry point over `GgenIgniter.SemanticJira.Shacl.validate_file/2`.

      mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--allow-unsupported]

  Supports only the SHACL subset documented in `GgenIgniter.SemanticJira.Shacl`;
  unsupported constructs are ALWAYS reported and FAIL CLOSED (exit `1`) unless
  `--allow-unsupported`. Exit `0` conforms, `1` violations or unsupported, `2`
  invocation (missing file, unsupported extension, no shapes in the shapes file).
  Accepted extensions: `.ttl`, `.nt`, `.nq` (datasets are merged into one graph).
  See `docs/reference/cli/shacl.md`.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.SemanticJira.Shacl

  @extensions [".ttl", ".nt", ".nq"]

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
        allow_unsupported: :boolean,
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

    json? = opts[:json] == true

    for key <- [:data, :shapes] do
      unless is_binary(opts[key]) and File.regular?(opts[key]) do
        refuse("--#{key} FILE is required and must exist", json?)
      end

      ext = opts[key] |> Path.extname() |> String.downcase()

      unless ext in @extensions do
        refuse(
          "--#{key} #{opts[key]}: unsupported extension #{inspect(ext)}; " <>
            "supported: #{Enum.join(@extensions, ", ")}",
          json?
        )
      end
    end

    if opts[:fail_on_unsupported] do
      Mix.shell().error(
        "ggen_igniter.shacl: --fail-on-unsupported is deprecated (now the default); " <>
          "use --allow-unsupported to opt out"
      )
    end

    data = load_graph(opts[:data], json?)
    shapes = load_graph(opts[:shapes], json?)
    report = Shacl.validate(data, shapes)

    if report.shapes_checked == [] do
      refuse("no SHACL shapes found in #{opts[:shapes]}", json?)
    end

    {unsupported, violations} =
      Enum.split_with(report.violations, &(&1.constraint == :unsupported_constraint))

    allow? = opts[:allow_unsupported] == true

    code =
      cond do
        violations != [] -> 1
        unsupported != [] and not allow? -> 1
        true -> 0
      end

    if json? do
      Mix.shell().info(json(report, violations, unsupported, code))
    else
      human(report, violations, unsupported)
    end

    if unsupported != [] and code == 1 and violations == [],
      do:
        Mix.shell().error(
          "ggen_igniter.shacl: UNSUPPORTED constructs present; failing closed (pass --allow-unsupported to override)"
        )

    if report.focus_node_count == 0,
      do: Mix.shell().error("ggen_igniter.shacl: warning: 0 focus nodes validated")

    System.halt(code)
  end

  defp load_graph(path, json?) do
    case GgenIgniter.Ontology.load!(path) do
      %RDF.Dataset{} = ds ->
        Enum.reduce(RDF.Dataset.graphs(ds), RDF.Graph.new(), &RDF.Graph.add(&2, &1))

      graph ->
        graph
    end
  rescue
    e -> refuse("cannot load #{path}: #{Exception.message(e)}", json?)
  end

  defp refuse(msg, json?) do
    Mix.shell().error("ggen_igniter.shacl: #{msg}")

    if json?,
      do:
        Mix.shell().info(
          Jason.encode!(%{schema_version: 1, error: msg, exit_code: 2, conforms: false})
        )

    System.halt(2)
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
    usage: mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--allow-unsupported]

    Exit 0 conforms, 1 violations or unsupported constructs (fail closed; --allow-unsupported
    to opt out), 2 invocation (bad/missing file, unsupported extension, no shapes).
    Supports only the SHACL subset documented in GgenIgniter.SemanticJira.Shacl.
    """)
  end
end
