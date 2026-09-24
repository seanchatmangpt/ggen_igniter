defmodule GgenIgniter.SemanticJira.PackHealth do
  @moduledoc """
  Real, executing health probe for the shipped `semantic-jira-pack`
  (`priv/ggen/semantic-jira-pack/`), consumed by `mix ggen_igniter.doctor`'s
  always-run `semantic_jira_pack` check and directly unit-tested by
  `test/ggen_igniter_semantic_jira_pack_health_test.exs`.

  For the pack directory it is given, `check/1`:

  1. Loads the packaged `ontology.ttl` through the real loader.
  2. Executes EVERY gate query (`gates/*.rq`) through the same engine path
     `mix ggen_igniter.sync` uses by default (`Engine.fetch!/1` ->
     `prepare!/2` -> `run/2`, default engine `oxigraph` per ADR-0001 --
     real execution, not the parse-only check `--pack` mode already offers).
  3. Renders each template through the SAME resolution + binding path the
     sync pipeline uses (`resolve_named_queries!/2`, `build_bindings/2`,
     `Render.render/2`) on the template's FIRST and LAST real driver rows.
     That bound is deliberate and disclosed in the check's own summary:
     rendering all 500+ canonical driver rows costs ~30s because
     `Render.render/2` recompiles the EEx body per row (the exact cost a
     real sync pays per row), which would make doctor's default checklist
     unusably slow -- while the pack suite's subprocess runs
     (`test/ggen_igniter_semantic_jira_pack_test.exs`) already manufacture
     every row end-to-end on every CI run. A template-body defect or a
     broken binding convention surfaces on any real row, and a driver query
     resolving to ZERO rows still refuses outright (a pack that manufactures
     nothing is not healthy).

  Fail-closed contract: `check/1` never raises. Any failure anywhere in the
  pipeline -- missing ontology, Turtle syntax error, a gate that crashes the
  engine, a template with an undefined binding, a driver query resolving to
  zero rows -- becomes `{:error, detail}` naming the failing component, so a
  broken pack degrades to an honest doctor `:error` line instead of crashing
  the whole doctor run (the same rescue-at-the-check contract
  `check_oxigraph_smoke_test` in the doctor task follows).
  """

  @pack_name "semantic-jira-pack"

  # `mix ggen_igniter.sync`'s own default engine (ADR-0001): the gates are
  # exercised here exactly the way a plain `mix ggen_igniter.sync --pack
  # semantic-jira-pack` runs them. Not the `sparql` hex library, whose
  # disclosed ORDER BY defect (`GgenIgniter.Query`'s moduledoc) makes it the
  # wrong engine to certify gate health with.
  @engine "oxigraph"

  @doc """
  Runs the full health probe against the pack directory `pack_dir` (the
  directory holding `ontology.ttl`, `gates/`, and `templates/` -- i.e. what
  `GgenIgniter.Pack.resolve_dir!/1` resolves to).

  Returns `{:ok, summary}` when every gate executes clean and every template
  renders on sampled real driver rows, or `{:error, detail}` naming the first
  failing component. Never raises.
  """
  @spec check(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def check(pack_dir) do
    ontology_path = GgenIgniter.Pack.default_ontology(pack_dir)

    unless File.exists?(ontology_path) do
      raise ArgumentError, "ontology.ttl missing at #{ontology_path}"
    end

    graph = GgenIgniter.Ontology.load!(ontology_path)
    engine = GgenIgniter.Engine.fetch!(@engine)
    context = engine.prepare!(graph, [])

    gates = GgenIgniter.Pack.discover_queries(pack_dir)

    if gates == [] do
      raise ArgumentError, "no *.rq gate queries found in #{Path.join(pack_dir, "gates")}"
    end

    templates = template_paths(pack_dir)

    if templates == [] do
      raise ArgumentError,
            "no *.eex/*.tmpl templates found in #{Path.join(pack_dir, "templates")}"
    end

    # Phase 1: every gate EXECUTES clean, attributed to the gate itself --
    # a broken gate is reported as a broken gate, not wrapped in whichever
    # template happened to resolve it first.
    Enum.each(gates, fn {name, path} -> execute_gate!(engine, context, name, path) end)

    # Phase 2: every template renders through the sync pipeline's own binding
    # convention on sampled real driver rows (first + last -- the disclosed
    # bound; see the moduledoc for why all-row rendering stays in the
    # subprocess suite).
    rendered = Enum.map(templates, &render_template(&1, pack_dir, engine, context))
    total_rows = rendered |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    {:ok,
     "#{length(gates)} gate quer#{if length(gates) == 1, do: "y", else: "ies"} executed clean " <>
       "against the packaged ontology (engine #{@engine}); " <>
       "#{length(templates)} template#{if length(templates) == 1, do: "", else: "s"} rendered " <>
       "(first+last driver row sampled; #{total_rows} driver row#{if total_rows == 1, do: "", else: "s"} total): " <>
       Enum.map_join(rendered, ", ", fn {name, sampled, rows} -> "#{name} #{sampled}/#{rows}" end)}
  rescue
    error -> {:error, "#{@pack_name}: #{Exception.message(error)}"}
  end

  @doc """
  The pack directory this probe expects under the ggen_igniter root --
  `<root>/priv/ggen/semantic-jira-pack/`.
  """
  @spec pack_dir(String.t()) :: String.t()
  def pack_dir(root_dir), do: Path.join([root_dir, "priv", "ggen", @pack_name])

  # Phase 1's per-gate executor: runs one gate through the engine context and
  # re-raises any failure attributed to the gate itself (name + path), so a
  # broken gate is reported as a broken gate rather than as whichever
  # template's named-query merge happened to hit it first. The rescue lives
  # in the inner capture function; the component-attributed `raise` happens
  # outside it -- the original error's message is fully embedded in the
  # wrapper, and the original stacktrace is deliberately not part of a
  # health report (the message is the product).
  defp execute_gate!(engine, context, name, path) do
    case capture_gate_error(engine, context, path) do
      :ok ->
        :ok

      {:error, error} ->
        raise ArgumentError,
              "gate #{name} (#{path}) failed to execute against the packaged ontology: " <>
                "#{Exception.message(error)}"
    end
  end

  defp capture_gate_error(engine, context, path) do
    engine.run(context, File.read!(path))
    :ok
  rescue
    error -> {:error, error}
  end

  defp template_paths(pack_dir) do
    [
      Path.wildcard(Path.join(pack_dir, "templates/*.eex")),
      Path.wildcard(Path.join(pack_dir, "templates/*.tmpl"))
    ]
    |> List.flatten()
    |> Enum.sort()
  end

  # Renders ONE template: resolves its named queries exactly as the sync
  # pipeline does (`resolve_named_queries!/2` -- frontmatter inline `sparql:`
  # merged over pack-discovered gates), executes them all through the engine
  # context, and renders the body on the FIRST and LAST real driver rows (or
  # once, for a header-less/no-`for_each` template) with the pipeline's own
  # `build_bindings/2` convention. Returns `{basename, sampled, total_rows}`.
  # Same capture-then-attribute shape as `execute_gate!/4`: the rescue lives
  # in the inner capture function, the template-attributed `raise` outside it.
  defp render_template(path, pack_dir, engine, context) do
    case capture_template_error(path, pack_dir, engine, context) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise ArgumentError,
              "template #{Path.basename(path)} failed to render: #{Exception.message(error)}"
    end
  end

  defp capture_template_error(path, pack_dir, engine, context) do
    {frontmatter, _mode, body} = GgenIgniter.Frontmatter.split_template(File.read!(path))

    named_queries =
      Mix.Tasks.GgenIgniter.Sync.resolve_named_queries!([pack_dir: pack_dir], frontmatter)

    named_results =
      Enum.map(named_queries, fn {name, query_text} ->
        {name, engine.run(context, query_text)}
      end)

    rows = driver_rows!(frontmatter, named_results)
    sampled = sample_rows(rows)
    render_rows!(body, named_results, sampled)

    {:ok, {Path.basename(path), length(sampled), length(rows)}}
  rescue
    error -> {:error, error}
  end

  # The disclosed sampling bound: first + last real driver rows (a 1-row or
  # 2-row driver renders in full). Any real row exercises the whole template
  # body -- every row runs the same validated admission path -- so a render
  # defect cannot hide in the unsampled middle rows without also being a
  # data-dependent defect the subprocess suite's all-row runs would catch.
  defp sample_rows([row]), do: [row]
  defp sample_rows([first, last]), do: [first, last]
  defp sample_rows([first | rest]), do: [first, List.last(rest)]

  # The driver row list a template renders over. `nil` frontmatter (a
  # header-less template) and a frontmatter without `for_each` both render
  # exactly once with no `for_each_row` bindings -- the same shapes
  # `Mix.Tasks.GgenIgniter.Sync.build_bindings/2` already understands.
  defp driver_rows!(nil, _named_results), do: [nil]

  defp driver_rows!(%GgenIgniter.Frontmatter{for_each: nil}, _named_results), do: [nil]

  defp driver_rows!(%GgenIgniter.Frontmatter{for_each: name}, named_results) do
    case List.keyfind(named_results, name, 0) do
      {^name, []} ->
        raise ArgumentError,
              "--for-each #{inspect(name)} driver query resolved to 0 rows against the " <>
                "packaged ontology -- the pack would manufacture nothing"

      {^name, rows} ->
        rows

      nil ->
        known = Enum.map_join(named_results, ", ", &elem(&1, 0))

        raise ArgumentError,
              "--for-each #{inspect(name)} does not name a declared query result (known: #{known})"
    end
  end

  # Renders the body once per sampled row and refuses a blank render -- an
  # empty projection is a broken projection, not a healthy one.
  defp render_rows!(body, named_results, rows) do
    Enum.each(rows, fn row ->
      bytes =
        GgenIgniter.Render.render(
          body,
          Mix.Tasks.GgenIgniter.Sync.build_bindings(named_results, row)
        )

      if String.trim(bytes) == "" do
        raise ArgumentError, "template rendered blank output for row #{inspect(row)}"
      end
    end)
  end
end
