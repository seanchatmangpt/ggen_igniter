defmodule GgenIgniter.PackFrontmatter.Sync do
  @moduledoc """
  Renders a ggen FRONTMATTER pack (`templates/*.tmpl` with `to`/`force`/`for_each`/`sparql:`
  headers and Tera bodies) with the existing ggen_igniter engine, producing the same bytes as
  `ggen sync run` for the supported subset (gap G1, v26.11.13).

  Pipeline (all pieces pre-existing except the Tera body renderer):

    1. ontology union: `<pack>/ontology.ttl` + sorted `<pack>/ontology.d/*.ttl` + each
       consumer ontology (`GgenIgniter.Ontology.load!/1`, merged with `RDF.Graph.add/2`)
    2. `GgenIgniter.Pack.admit_pack_manifest/2` (RFC-GPACK-001 identity admission)
    3. engine `GgenIgniter.Engine.fetch!("graphlaw")` -> `prepare!/2` -> `run/2`
    4. pack gates `<pack>/gates/*.rq`: a SELECT returning ANY row is a violation; the whole
       run is refused (`REFUSED:PACK_GATE_VIOLATED` (FM-PACK-013)) BEFORE any file is written
    5. per template: `GgenIgniter.Frontmatter.split_template/1`; each `sparql:` entry runs once;
       with `for_each: NAME` the template renders once per row of NAME (row columns are merged
       into the top-level bindings, named queries stay bound as full row lists; a query with
       exactly one row is also flattened, ggen convention); `to:` is itself Tera-rendered
    6. `GgenIgniter.PackFrontmatter.Tera.render/2` for body and `to`
    7. `GgenIgniter.Actuate.write_file!/3` (atomic, idempotent)

  ## Loud refusals (never silent)

  Frontmatter fields with no implementation here (`inject`, `construct`, `when`, `sh_before`,
  `sh_after`, `from`, `rdf`, `rdf_inline`, `shape`, `freeze_*`, `backup`, `skip_if`) raise
  `REFUSED:UNSUPPORTED_FRONTMATTER`; a non-`force` template whose target exists with different
  bytes raises `REFUSED:WRITE_WITHOUT_FORCE`; two renders targeting one path raise
  `REFUSED:DUPLICATE_OUTPUT`; a path resolving outside `:out_dir` raises
  `REFUSED:PATH_ESCAPE`.

  ## Options

    * `:pack_dir` (required), `:ontologies` (list of consumer ontology paths, required)
    * `:out_dir` (default `File.cwd!()`), `:dry_run` (default false)

  Returns `%{files: [%{path:, outcome:}], gates: [name]}`; `outcome` is `:written | :unchanged
  | :skipped_exists` (`:written` under `:dry_run` means "would write").

  Not implemented (disclosed): the reconciliation manifest / `--on-stale`, receipts, and
  `ggen.lock` (see `Mix.Tasks.GgenIgniter.PackSync` for `--lock/--relock`).
  """

  alias GgenIgniter.{Actuate, Engine, Frontmatter, Ontology, Pack}
  alias GgenIgniter.PackFrontmatter.Tera

  @unsupported ~w(inject construct sh_before sh_after from rdf rdf_inline shape
                  freeze_policy freeze_slots_dir backup skip_if before after at_line)a

  @spec run!(keyword()) :: %{files: [map()], gates: [String.t()]}
  def run!(opts) do
    pack_dir = Keyword.fetch!(opts, :pack_dir)
    ontologies = Keyword.fetch!(opts, :ontologies)
    out_dir = opts |> Keyword.get(:out_dir, File.cwd!()) |> Path.expand()
    dry_run = Keyword.get(opts, :dry_run, false)

    unless File.dir?(pack_dir),
      do: raise(ArgumentError, "pack directory #{pack_dir} does not exist")

    graph = load_union!(pack_dir, ontologies)
    admit!(pack_dir, graph)

    engine = Engine.fetch!(Engine.fixed())
    ctx = engine.prepare!(graph, [])

    gates = check_gates!(engine, ctx, pack_dir)
    renders = plan_renders!(engine, ctx, pack_dir, out_dir)
    assert_unique!(renders)

    files =
      Enum.map(renders, fn r ->
        %{path: r.path, outcome: write!(r, dry_run)}
      end)

    %{files: files, gates: gates}
  end

  @doc "True when `pack_dir` holds frontmatter `.tmpl`/`.tera` templates whose bodies use Tera syntax."
  @spec tera_pack?(String.t()) :: boolean()
  def tera_pack?(pack_dir) do
    templates(pack_dir) != [] and
      Enum.any?(templates(pack_dir), fn t ->
        body = File.read!(t)
        String.starts_with?(body, "---\n") and Regex.match?(~r/\{\{|\{%/, body)
      end)
  end

  # -- ontology ---------------------------------------------------------------

  defp load_union!(pack_dir, consumer) do
    paths =
      [
        Path.join(pack_dir, "ontology.ttl")
        | Enum.sort(Path.wildcard(Path.join(pack_dir, "ontology.d/*.ttl")))
      ] ++
        consumer

    Enum.reduce(paths, RDF.Graph.new(), fn path, acc ->
      unless File.exists?(path), do: raise(ArgumentError, "ontology #{path} does not exist")
      RDF.Graph.add(acc, Ontology.load!(path))
    end)
  end

  defp admit!(pack_dir, graph) do
    case Pack.admit_pack_manifest(pack_dir, graph) do
      :ok ->
        :ok

      {:refused, {code, diagnostic: d}} ->
        raise ArgumentError, "REFUSED:#{code |> to_string() |> String.upcase()} #{d}"
    end
  end

  # -- gates ------------------------------------------------------------------

  defp check_gates!(engine, ctx, pack_dir) do
    results =
      pack_dir
      |> Pack.discover_queries()
      |> Enum.map(fn {name, path} -> {name, engine.run(ctx, File.read!(path))} end)

    case Enum.filter(results, fn {_n, rows} -> rows != [] end) do
      [] ->
        Enum.map(results, &elem(&1, 0))

      bad ->
        detail =
          Enum.map_join(bad, "; ", fn {name, rows} ->
            "gate #{name}: #{length(rows)} violation(s) #{inspect(Enum.take(rows, 3))}"
          end)

        raise ArgumentError,
              "REFUSED:PACK_GATE_VIOLATED FM-PACK-013 pack gate violated -- #{detail}"
    end
  end

  # -- planning ---------------------------------------------------------------

  defp templates(pack_dir) do
    (Path.wildcard(Path.join(pack_dir, "templates/*.tmpl")) ++
       Path.wildcard(Path.join(pack_dir, "templates/*.tera")))
    |> Enum.sort()
  end

  defp plan_renders!(engine, ctx, pack_dir, out_dir) do
    pack_dir |> templates() |> Enum.flat_map(&plan_template!(&1, engine, ctx, out_dir))
  end

  defp plan_template!(template_path, engine, ctx, out_dir) do
    {fm, mode, body} = Frontmatter.split_template(File.read!(template_path))
    name = Path.basename(template_path)

    if fm == nil,
      do: raise(ArgumentError, "REFUSED:MISSING_FRONTMATTER #{name} has no --- header")

    if mode != :file,
      do: raise(ArgumentError, "REFUSED:UNSUPPORTED_FRONTMATTER #{name}: mode #{mode}")

    if when_holds?(fm.when, engine, ctx, name) do
      plan_enabled_template!(fm, body, name, engine, ctx, out_dir)
    else
      []
    end
  end

  # `when:` is a SPARQL ASK over the union graph: false => the template is skipped (no output),
  # as ggen does; true => planned normally. Only the ASK form is supported; anything else refuses.
  defp when_holds?(nil, _engine, _ctx, _name), do: true
  defp when_holds?("", _engine, _ctx, _name), do: true

  defp when_holds?(text, engine, ctx, name) when is_binary(text) do
    case Regex.run(~r/\A\s*ASK\s*(\{.*\})\s*\z/s, text) do
      [_, pattern] ->
        engine.run(ctx, "SELECT * WHERE " <> pattern <> " LIMIT 1") != []

      _ ->
        raise ArgumentError,
              "REFUSED:UNSUPPORTED_FRONTMATTER #{name}: when (only SPARQL ASK is supported)"
    end
  end

  defp plan_enabled_template!(fm, body, name, engine, ctx, out_dir) do
    set = Enum.filter(@unsupported, &truthy_field?(Map.fetch!(Map.from_struct(fm), &1)))

    if set != [],
      do: raise(ArgumentError, "REFUSED:UNSUPPORTED_FRONTMATTER #{name}: #{Enum.join(set, ", ")}")

    queries =
      Map.new(fm.sparql, fn {qname, text} -> {qname, engine.run(ctx, text)} end)

    base =
      Enum.reduce(Enum.sort(Map.keys(queries)), queries, fn qname, acc ->
        case Map.fetch!(queries, qname) do
          [row] -> Map.merge(acc, row)
          _ -> acc
        end
      end)

    rows =
      case fm.for_each do
        nil ->
          [%{}]

        each ->
          Map.get(queries, each) ||
            raise ArgumentError,
                  "REFUSED:UNKNOWN_FOR_EACH #{name}: for_each #{inspect(each)} names no sparql: query"
      end

    Enum.map(rows, fn row ->
      env = Map.merge(base, row)
      rel = env_render(fm.to, env, name)
      path = Path.expand(rel, out_dir)

      unless path == out_dir or String.starts_with?(path, out_dir <> "/"),
        do:
          raise(ArgumentError, "REFUSED:PATH_ESCAPE #{name}: #{rel} resolves outside #{out_dir}")

      %{
        template: name,
        path: path,
        content: Tera.render(body, env),
        force: fm.force,
        unless_exists: fm.unless_exists
      }
    end)
  end

  defp env_render(to, env, name) do
    to
    |> Tera.render(env)
    |> then(fn s ->
      if s == "", do: raise(ArgumentError, "#{name}: `to:` rendered empty"), else: s
    end)
  end

  defp truthy_field?(v) when v in [nil, false, [], %{}], do: false
  defp truthy_field?(_), do: true

  defp assert_unique!(renders) do
    dupes =
      renders
      |> Enum.group_by(& &1.path)
      |> Enum.filter(fn {_p, rs} -> length(rs) > 1 end)

    if dupes != [] do
      raise ArgumentError,
            "REFUSED:DUPLICATE_OUTPUT " <>
              Enum.map_join(dupes, "; ", fn {p, rs} ->
                "#{p} <- #{Enum.map_join(rs, ",", & &1.template)}"
              end)
    end
  end

  # -- actuation ----------------------------------------------------------------

  defp write!(r, dry_run) do
    if File.exists?(r.path) and not r.force and not r.unless_exists and
         File.read!(r.path) != r.content do
      raise ArgumentError,
            "REFUSED:WRITE_WITHOUT_FORCE #{r.path} exists with different bytes and #{r.template} sets no `force: true`"
    end

    {:ok, outcome} =
      Actuate.write_file!(r.path, r.content, unless_exists: r.unless_exists, dry_run: dry_run)

    outcome
  end
end
