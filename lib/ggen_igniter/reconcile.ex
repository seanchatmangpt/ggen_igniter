defmodule GgenIgniter.Reconcile do
  @moduledoc """
  The one real reconciliation pipeline implementation: `Ontology.load!/1` ->
  engine `prepare!/2` + `run/2` -> `Render.render/2` -> `Actuate.write_file!/3`
  (or `Actuate.eval_code!/2` under `mode: eval`).

  Extracted as a plain, `Mix.Task`/`Igniter`-free function specifically so it
  can be called by both a CLI entry point (`Mix.Tasks.GgenIgniter.Sync`) and a
  persistent in-process caller (`GgenIgniter.Controller`) without duplicating
  the ontology-load/engine-run/render/actuate logic in two places. This
  module is the shared implementation; `GgenIgniter.Controller` calls
  `run/1` directly and adds only in-process state around it.

  `Mix.Tasks.GgenIgniter.Sync` itself is left unchanged in this pass (a
  separate, concurrent effort owns wiring the CLI to delegate here) -- so for
  now this is a second entry point into the same real query engines/render/
  actuate modules `sync.ex` already uses, not yet the CLI's own call path.
  Once that wiring lands, `sync.ex`'s `igniter/1` and `GgenIgniter.Controller`
  will both terminate in this one function.

  ## Deliberately bounded relative to `Mix.Tasks.GgenIgniter.Sync`

  This is a bounded, real proof-of-concept slice covering exactly the spine
  named for it: ontology-load -> engine-run -> render -> actuate. It does
  NOT (yet) implement `Mix.Tasks.GgenIgniter.Sync`'s fuller surface:

    * No template frontmatter parsing (`GgenIgniter.Frontmatter`) -- a
      template's file content is used verbatim as the EEx body.
    * No `--for-each` multi-row fan-out -- exactly one render, exactly one
      actuation per `run/1` call.
    * No `inject: true` splice mode -- `mode: file` always dispatches to
      `Actuate.write_file!/3` (whole-file guarded write), never
      `Actuate.inject_content!/5`.

  The `--pack`/`--pack-dir` convention (`GgenIgniter.Pack`) IS supported,
  reused verbatim (not duplicated), since pack-shaped fixtures are the
  natural unit a reconciliation controller tracks by key.

  ## Options (`opts`, a plain keyword list)

  Mirrors the subset of `Mix.Tasks.GgenIgniter.Sync`'s own `--` flags this
  function's bounded scope covers:

    * `:ontology` -- path to the Turtle ontology file. Falls back to the
      pack's `ontology.ttl` when `:pack`/`:pack_dir` is given.
    * `:query` -- one `"name=path.rq"` string, or a list of them (repeatable
      `--query` equivalent). Merged with pack-discovered `gates/*.rq` queries
      when a pack is given (pack queries first, explicit `:query` entries
      override same-named pack queries -- same tie-break as `sync.ex`).
    * `:template` -- path to the EEx template file. Falls back to the pack's
      single auto-discovered template when `:pack`/`:pack_dir` is given.
    * `:pack` / `:pack_dir` -- see `GgenIgniter.Pack`.
    * `:engine` -- `"oxigraph"` (default), `"sparql"`, or `"qlever"`.
    * `:mode` -- `"file"` (default) or `"eval"`.
    * `:out` -- required for `mode: "file"`; EEx-rendered against the query
      bindings (a static path with no `<%= %>` round-trips unchanged).
    * `:unless_exists`, `:skip_if`, `:dry_run` -- forwarded to
      `Actuate.write_file!/3` unchanged.

  ## Return value

  `{:ok, result}` where `result` is a plain map (see `t:result/0`) describing
  what actually happened -- real engine name, real resolved paths, real row
  counts, and the real `Actuate` outcome/eval value. Raises on a real,
  unrecoverable pipeline failure (bad ontology path, missing template, engine
  error) -- this function is a faithful, un-defensive mirror of what the
  pipeline actually does; a caller that needs a non-raising boundary (e.g.
  `GgenIgniter.Controller`) wraps this call itself rather than this function
  hiding real failures behind a swallowed error tuple.
  """

  alias GgenIgniter.{Actuate, Engine, Ontology, Pack, Render}

  @type result :: %{
          engine: String.t(),
          ontology_path: String.t(),
          template_path: String.t(),
          query_count: non_neg_integer(),
          total_rows: non_neg_integer(),
          mode: :file | :eval,
          out_path: String.t() | nil,
          outcome: Actuate.outcome() | nil,
          value: term(),
          notice: String.t()
        }

  @doc """
  Runs the real reconciliation pipeline for one set of `opts` (see moduledoc
  for the accepted keys). Returns `{:ok, result()}`.
  """
  @spec run(keyword()) :: {:ok, result()}
  def run(opts) when is_list(opts) do
    engine_name = Keyword.get(opts, :engine, "oxigraph")
    engine_module = Engine.fetch!(engine_name)

    ontology_path = resolve_ontology!(opts)
    graph = Ontology.load!(ontology_path)

    template_path = resolve_template!(opts)
    template_string = File.read!(template_path)

    named_queries = resolve_named_queries!(opts)
    named_results = run_queries(engine_module, graph, opts, named_queries)
    total_rows = named_results |> Enum.map(fn {_name, rows} -> length(rows) end) |> Enum.sum()

    bindings = build_bindings(named_results)
    content = Render.render(template_string, bindings)

    mode = resolve_mode!(opts)
    {out_path, outcome, value, notice} = actuate!(mode, content, bindings, opts)

    {:ok,
     %{
       engine: engine_name,
       ontology_path: ontology_path,
       template_path: template_path,
       query_count: length(named_queries),
       total_rows: total_rows,
       mode: mode,
       out_path: out_path,
       outcome: outcome,
       value: value,
       notice: notice
     }}
  end

  defp actuate!(:file, content, bindings, opts) do
    out_template =
      Keyword.get(opts, :out) ||
        raise ArgumentError, ":out is required for mode: file"

    out_path = Render.render(out_template, bindings)

    write_opts = [
      unless_exists: Keyword.get(opts, :unless_exists, false),
      skip_if: Keyword.get(opts, :skip_if),
      dry_run: Keyword.get(opts, :dry_run, false)
    ]

    {:ok, outcome} = Actuate.write_file!(out_path, content, write_opts)
    {out_path, outcome, nil, "#{outcome_verb(outcome)} #{out_path}"}
  end

  defp actuate!(:eval, content, bindings, _opts) do
    {:ok, value} = Actuate.eval_code!(content, bindings)
    {nil, nil, value, "evaluated -> #{inspect(value)}"}
  end

  defp outcome_verb(:written), do: "wrote"
  defp outcome_verb(:unchanged), do: "unchanged (skipped, identical content):"
  defp outcome_verb(:skipped_exists), do: "skipped (unless_exists, already exists):"
  defp outcome_verb(:skipped_match), do: "skipped (skip_if matched):"

  defp resolve_mode!(opts) do
    case Keyword.get(opts, :mode, "file") do
      "file" -> :file
      "eval" -> :eval
      :file -> :file
      :eval -> :eval
      other -> raise ArgumentError, "mode must be \"file\" or \"eval\", got: #{inspect(other)}"
    end
  end

  defp pack_given?(opts), do: opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""]

  defp resolve_ontology!(opts) do
    cond do
      opts[:ontology] not in [nil, ""] ->
        opts[:ontology]

      pack_given?(opts) ->
        path = Pack.default_ontology(Pack.resolve_dir!(opts))

        unless File.exists?(path) do
          raise ArgumentError, "pack/pack_dir resolved ontology not found at #{path}"
        end

        path

      true ->
        raise ArgumentError, "ontology is required (directly, or via pack/pack_dir)"
    end
  end

  defp resolve_template!(opts) do
    cond do
      opts[:template] not in [nil, ""] ->
        opts[:template]

      pack_given?(opts) ->
        pack_dir = Pack.resolve_dir!(opts)

        case Pack.discover_template(pack_dir, opts[:pack_template_stem]) do
          {:ok, path} ->
            path

          {:error, :none} ->
            raise ArgumentError,
                  "no *.eex/*.tmpl template found in #{pack_dir}/templates/ -- pass :template explicitly"

          {:error, {:ambiguous, paths}} ->
            raise ArgumentError,
                  "multiple templates found in #{pack_dir}/templates/ (#{Enum.join(paths, ", ")}) -- pass :template explicitly"

          {:error, {:stem_not_found, stem, paths}} ->
            raise ArgumentError,
                  "pack template stem #{inspect(stem)} did not match any template in #{pack_dir}/templates/ " <>
                    "(available: #{Enum.join(paths, ", ")})"
        end

      true ->
        raise ArgumentError, "template is required (directly, or via pack/pack_dir)"
    end
  end

  defp resolve_named_queries!(opts) do
    explicit =
      opts
      |> Keyword.get_values(:query)
      |> Enum.map(&parse_named_query!/1)
      |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

    if pack_given?(opts) do
      pack_dir = Pack.resolve_dir!(opts)

      pack_queries =
        pack_dir
        |> Pack.discover_queries()
        |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

      if pack_queries == [] and explicit == [] do
        raise ArgumentError,
              "no *.rq files found in #{pack_dir}/gates/ and no explicit query given"
      end

      Enum.reduce(explicit, pack_queries, fn {name, text}, acc ->
        List.keystore(acc, name, 0, {name, text})
      end)
    else
      if explicit == [] do
        raise ArgumentError,
              "at least one query name=path.rq is required (or use pack/pack_dir)"
      end

      explicit
    end
  end

  defp parse_named_query!(arg) do
    case String.split(arg, "=", parts: 2) do
      [name, path] -> {name, path}
      [_no_name] -> raise ArgumentError, "each query must be name=path.rq, got: #{arg}"
    end
  end

  defp run_queries(engine_module, graph, opts, named_queries) do
    context = engine_module.prepare!(graph, opts)

    Enum.map(named_queries, fn {name, query_text} ->
      {name, engine_module.run(context, query_text)}
    end)
  end

  # Builds the EEx binding keyword list: every named query is bound as
  # `name: rows` (list of string-keyed maps), and any single-row query
  # additionally has its own columns flattened to top-level atom-keyed
  # bindings -- mirrors `Mix.Tasks.GgenIgniter.Sync.build_bindings/2`'s same
  # convention (this function's bounded scope has no `--for-each` row to
  # merge in last, so it is the single-clause case of that logic).
  @doc false
  @spec build_bindings([{String.t(), [map()]}]) :: keyword()
  def build_bindings(named_results) do
    list_bindings = Enum.map(named_results, fn {name, rows} -> {String.to_atom(name), rows} end)

    flattened =
      named_results
      |> Enum.filter(fn {_name, rows} -> length(rows) == 1 end)
      |> Enum.flat_map(fn {_name, [row]} -> row end)
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)

    Keyword.merge(list_bindings, flattened)
  end
end
