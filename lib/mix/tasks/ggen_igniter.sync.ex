defmodule Mix.Tasks.GgenIgniter.Sync do
  @moduledoc """
  CLI entrypoint: `mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable) --template path.eex --out path.ex`.

  Wires `Ontology.load!/1` -> `Query.run/2` (once per `--query`) -> `Render.render/2` ->
  `Actuate.write_new_file!/2` in sequence.

  Each `--query name=path.rq` result is bound in the EEx template under `name` as the
  full list of result rows (string-keyed maps). Additionally, mirroring ggen's own
  single-row-flattening convention (found live this session working with the Rust
  `ggen` tool): a query whose result has EXACTLY ONE row also has that row's own
  columns merged directly into the top-level bindings, atom-keyed, so a single-row
  query like `spec` can be referenced as bare `module_name`/`package_name` instead of
  `hd(spec)["module_name"]`. Later `--query` flags win on key collisions in the
  flattened namespace -- pass queries in the order you want that tie-break to resolve.

  ## Engines

  `--engine sparql` (default) runs every query in-process against the loaded
  `%RDF.Graph{}` via `GgenIgniter.Query.run/2` (the `sparql` hex package).

  `--engine qlever` runs every query instead against a real, already-running
  QLever SPARQL endpoint via `GgenIgniter.Query.Qlever.run/2` (`gno` + real
  HTTP, no in-process SPARQL evaluation). `--ontology` is then still read as a
  `%RDF.Graph{}` (via the same `Ontology.load!/1`), but only to look up the
  `gnoa:Qlever`-typed store resource named by `--store-id` -- the query text
  itself never touches this graph's data, it runs on the remote QLever store.
  `--store-id` is required when `--engine qlever` is given.

  ## Example (default sparql engine)

      mix ggen_igniter.sync \\
        --ontology test/fixtures/audit_trail_ontology.ttl \\
        --query spec=test/fixtures/spec.rq \\
        --query sections=test/fixtures/sections.rq \\
        --query entities=test/fixtures/entities.rq \\
        --query fields=test/fixtures/fields.rq \\
        --template test/fixtures/extension.ex.eex \\
        --out tmp_out/probe.ex

  ## Example (qlever engine)

      mix ggen_igniter.sync \\
        --engine qlever \\
        --ontology config/gno/test/store.ttl \\
        --store-id http://example.com/Qlever \\
        --query spec=priv/ggen/some-pack/gates/010.rq \\
        --template priv/ggen/some-pack/templates/out.ex.eex \\
        --out lib/generated.ex
  """
  use Igniter.Mix.Task

  alias GgenIgniter.{Ontology, Query, Render, Actuate}
  alias GgenIgniter.Query.Qlever, as: QleverQuery

  @valid_engines ~w[sparql qlever]

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example:
        "mix ggen_igniter.sync --ontology spec.ttl --query spec=rows.rq --query entities=entities.rq --template out.ex.eex --out lib/generated.ex",
      positional: [],
      schema: [
        ontology: :string,
        query: [:string, :keep],
        template: :string,
        out: :string,
        engine: :string,
        store_id: :string
      ],
      required: [:ontology, :query, :template, :out]
    }
  end

  @doc "Reads --ontology/--query(N)/--template/--out/--engine/--store-id options and runs the pipeline."
  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    engine = validate_engine!(opts[:engine] || "sparql")

    graph = Ontology.load!(opts[:ontology])

    named_queries =
      opts
      |> Keyword.get_values(:query)
      |> Enum.map(&parse_named_query!/1)

    named_results = run_queries(engine, graph, opts, named_queries)

    bindings = build_bindings(named_results)

    content = Render.render(File.read!(opts[:template]), bindings)
    :ok = Actuate.write_new_file!(opts[:out], content)

    total_rows = named_results |> Enum.map(fn {_name, rows} -> length(rows) end) |> Enum.sum()

    Igniter.add_notice(
      igniter,
      "ggen_igniter: wrote #{opts[:out]} (engine: #{engine}, #{length(named_queries)} quer#{if length(named_queries) == 1, do: "y", else: "ies"}, #{total_rows} total row(s))"
    )
  end

  defp validate_engine!(engine) when engine in @valid_engines, do: engine

  defp validate_engine!(engine) do
    raise ArgumentError,
          "invalid --engine #{inspect(engine)}, must be one of: #{Enum.join(@valid_engines, ", ")}"
  end

  defp run_queries("sparql", graph, _opts, named_queries) do
    Enum.map(named_queries, fn {name, path} ->
      {name, Query.run(graph, File.read!(path))}
    end)
  end

  defp run_queries("qlever", graph, opts, named_queries) do
    store_id =
      opts[:store_id] ||
        raise ArgumentError, "--store-id is required when --engine qlever is given"

    # Igniter tasks don't boot the full OTP application tree (they operate on
    # ASTs, not a running app), so ensure the real HTTP client stack this
    # engine needs is up, idempotently, right before using it.
    {:ok, _} = Application.ensure_all_started(:tesla)
    unless Process.whereis(GgenIgniter.Finch), do: {:ok, _} = Finch.start_link(name: GgenIgniter.Finch)

    store = QleverQuery.load_store!(graph, store_id)

    Enum.map(named_queries, fn {name, path} ->
      {name, QleverQuery.run(store, File.read!(path))}
    end)
  end

  defp parse_named_query!(arg) do
    case String.split(arg, "=", parts: 2) do
      [name, path] -> {name, path}
      [_no_name] -> raise ArgumentError, "each --query must be name=path.rq, got: #{arg}"
    end
  end

  # Builds the EEx binding keyword list: every named query is bound as `name: rows`
  # (list of string-keyed maps), and any single-row query additionally has its own
  # columns flattened to top-level atom-keyed bindings -- mirroring ggen's own
  # single-row-query flattening behavior.
  defp build_bindings(named_results) do
    list_bindings =
      Enum.map(named_results, fn {name, rows} -> {String.to_atom(name), rows} end)

    flattened =
      named_results
      |> Enum.filter(fn {_name, rows} -> length(rows) == 1 end)
      |> Enum.flat_map(fn {_name, [row]} -> row end)
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)

    Keyword.merge(list_bindings, flattened)
  end
end
