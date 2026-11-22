defmodule GgenIgniter.SpatialCourt do
  @moduledoc """
  Emits a zero-mock Playwright Spatial Court from a SHACL `sh:PropertyGroup`
  graph — the Step-3 closing surface for mobile-first UI manufacture.

  Distinct from Semantic Jira courts (`GgenIgniter.SemanticJira.CourtMap` /
  `mix semantic_jira.court_map`): those mint acceptance/falsifier witness maps
  for work-order fabric receipts. This module never reads `sj:` witnesses and
  never writes into `semantic-jira-pack`.

  Public paths:

    * `from_ontology/1` — load Turtle/N-Triples/N-Quads via
      `GgenIgniter.Ontology.load!/1`, refuse when no `sh:PropertyGroup` is present
      or any group/member lacks a resolvable CSS selector
    * `from_graph/1` — same extraction over an already-loaded `RDF.Graph`
    * `render/2` — EEx-render `priv/ggen/spatial-court-pack/templates/spatial_court.spec.ts.eex`
      (or an override `:template`) with the court model + viewport / floor assigns
    * `emit/2` — `render/2` then write `*.spatial-court.spec.ts` (default name
      derived from the first PropertyGroup local name)

  Generated court embeds the 9-wide default viewport fallback
  `[320, 375, 393, 414, 600, 768, 840, 1024, 1280]`. Emitted Playwright
  prefers runtime CSV from `UI_LAYOUT_PLAYWRIGHT_VIEWPORTS` then
  `UI_LAYOUT_VIEWPORTS` (set by zcode-cli `ui-layout-court` spawn), falling
  back to that default. Asserts fail-closed: zero horizontal overflow
  (WCAG 1.4.10), basic rRLG-lite (no visible overlap / viewport protrusion),
  touch targets ≥ 44, edge gaps ≥ 8, optional Gestalt inter/intra proximity
  ratio helpers (default ratio 2.0).
  """

  alias GgenIgniter.Ontology

  @sh "http://www.w3.org/ns/shacl#"
  @rdfs "http://www.w3.org/2000/01/rdf-schema#"
  # Pack law: public shui: only (W3C SHACL-UI, trailing slash). Private sc:
  # (ggen-igniter.dev/ontology/spatial-court#) is refused — no secondary NS.
  @shui "http://www.w3.org/ns/shacl-ui/"

  # Default Playwright fallback only — runtime subjects read UI_LAYOUT_* env.
  @viewports [320, 375, 393, 414, 600, 768, 840, 1024, 1280]
  @min_touch 44
  @min_gap 8
  @gestalt_ratio 2.0
  @viewport_height 800

  @type member :: %{
          id: String.t(),
          selector: String.t(),
          order: number(),
          touch?: boolean()
        }

  @type group :: %{
          id: String.t(),
          label: String.t(),
          selector: String.t(),
          order: number(),
          members: [member()]
        }

  @type court :: %{
          groups: [group()],
          viewports: [pos_integer()],
          min_touch: pos_integer(),
          min_gap: pos_integer(),
          gestalt_ratio: float(),
          viewport_height: pos_integer()
        }

  @doc """
  Canonical 9-wide viewport fallback (CSS px). Emitted Playwright prefers
  `process.env.UI_LAYOUT_PLAYWRIGHT_VIEWPORTS || process.env.UI_LAYOUT_VIEWPORTS`
  (CSV) at runtime and only falls back to this list when env is unset/empty.
  """
  @spec viewports() :: [pos_integer()]
  def viewports, do: @viewports

  @doc "Pack-relative path of the shipped Playwright Spatial Court EEx template."
  @spec template_path() :: String.t()
  def template_path do
    Path.join([
      :code.priv_dir(:ggen_igniter) |> to_string(),
      "ggen",
      "spatial-court-pack",
      "templates",
      "spatial_court.spec.ts.eex"
    ])
  end

  @doc """
  Load `path` and extract a Spatial Court model. Returns
  `{:error, {:spatial_court_refused, reason}}` when the graph has no groups or
  a required selector cannot be resolved.
  """
  @spec from_ontology(String.t()) :: {:ok, court()} | {:error, term()}
  def from_ontology(path) when is_binary(path) do
    case File.regular?(path) do
      true ->
        case Ontology.load!(path) do
          %RDF.Graph{} = graph -> from_graph(graph)
          %RDF.Dataset{} = dataset -> from_graph(RDF.Dataset.default_graph(dataset))
        end

      false ->
        {:error, {:spatial_court_refused, {:ontology_missing, path}}}
    end
  rescue
    e -> {:error, {:spatial_court_refused, {:ontology_unreadable, path, Exception.message(e)}}}
  end

  def from_ontology(_), do: {:error, {:spatial_court_refused, :not_a_string}}

  @doc "Extract PropertyGroups + ordered members with CSS selectors from `graph`."
  @spec from_graph(RDF.Graph.t()) :: {:ok, court()} | {:error, term()}
  def from_graph(%RDF.Graph{} = graph) do
    groups =
      graph
      |> RDF.Graph.descriptions()
      |> Enum.filter(&typed?(&1, iri(@sh <> "PropertyGroup")))
      |> Enum.map(&group_model(&1, graph))
      # Empty parent trays (shui:parentGroup scaffolding only) are not court
      # subjects — drop :skip sentinels before the ok/error split.
      |> Enum.reject(&(&1 == :skip))

    case Enum.split_with(groups, &match?({:ok, _}, &1)) do
      {[], []} ->
        # No PropertyGroups, or every group was a skipped parent tray.
        {:error, {:spatial_court_refused, :no_property_groups}}

      {[], errs} ->
        # Every remaining group failed (e.g. ungrouped_or_empty) — keep typed
        # reasons; do not collapse to :no_property_groups.
        {:error,
         {:spatial_court_refused, {:group_errors, Enum.map(errs, fn {:error, r} -> r end)}}}

      {oks, []} ->
        court_groups =
          oks
          |> Enum.map(fn {:ok, g} -> g end)
          |> Enum.sort_by(& &1.order)

        {:ok,
         %{
           groups: court_groups,
           viewports: @viewports,
           min_touch: @min_touch,
           min_gap: @min_gap,
           gestalt_ratio: @gestalt_ratio,
           viewport_height: @viewport_height
         }}

      {_, errs} ->
        {:error,
         {:spatial_court_refused, {:group_errors, Enum.map(errs, fn {:error, r} -> r end)}}}
    end
  end

  def from_graph(_), do: {:error, {:spatial_court_refused, :not_a_graph}}

  @doc """
  Render the Spatial Court Playwright spec. Options:

    * `:template` — absolute path override (default `template_path/0`)
    * `:base_url` — Playwright navigation origin (default `http://127.0.0.1:4173`)
    * `:route` — path appended to base (default `/`)
    * `:suite` — `test.describe` title (default first group id)
    * `:gestalt` — when `false`, omit Gestalt ratio helper tests (default `true`)
    * `:text_spacing` — when `false`, omit WCAG 1.4.12 inject assert (default `true`)
  """
  @spec render(court(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(court, opts \\ [])

  def render(%{groups: groups} = court, opts) when is_list(groups) and groups != [] do
    template = Keyword.get(opts, :template) || template_path()

    unless File.regular?(template) do
      {:error, {:spatial_court_refused, {:template_missing, template}}}
    else
      suite = Keyword.get(opts, :suite) || hd(groups).id
      base_url = Keyword.get(opts, :base_url, "http://127.0.0.1:4173")
      route = Keyword.get(opts, :route, "/")

      groups_json =
        groups
        |> Enum.map(fn g ->
          %{
            "id" => g.id,
            "label" => g.label,
            "selector" => g.selector,
            "members" =>
              Enum.map(g.members, fn m ->
                %{"id" => m.id, "selector" => m.selector, "touch" => m.touch?}
              end)
          }
        end)
        |> Jason.encode!()

      bindings = [
        groups: groups,
        groups_json: groups_json,
        viewports: court.viewports,
        viewports_json: Jason.encode!(court.viewports),
        min_touch: court.min_touch,
        min_gap: court.min_gap,
        gestalt_ratio: court.gestalt_ratio,
        viewport_height: court.viewport_height,
        suite: suite,
        suite_json: Jason.encode!(suite),
        base_url: base_url,
        base_url_json: Jason.encode!(base_url),
        route: route,
        route_json: Jason.encode!(route),
        gestalt?: Keyword.get(opts, :gestalt, true) != false,
        text_spacing?: Keyword.get(opts, :text_spacing, true) != false
      ]

      body = template |> File.read!() |> GgenIgniter.Render.render(bindings)
      {:ok, body}
    end
  rescue
    e -> {:error, {:spatial_court_refused, {:render_failed, Exception.message(e)}}}
  end

  def render(_, _), do: {:error, {:spatial_court_refused, :empty_court}}

  @doc """
  Render and write the Spatial Court. `:out` is required (directory or
  `*.spatial-court.spec.ts` path). Returns `{:ok, path}` of the written file.
  """
  @spec emit(court(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def emit(court, opts) when is_list(opts) do
    with {:ok, out} <- resolve_out(court, opts),
         {:ok, body} <- render(court, opts) do
      File.mkdir_p!(Path.dirname(out))
      File.write!(out, body)
      {:ok, out}
    end
  end

  defp resolve_out(%{groups: [first | _]}, opts) do
    case Keyword.get(opts, :out) do
      path when is_binary(path) and path != "" ->
        out =
          if String.ends_with?(path, ".ts") or String.ends_with?(path, ".spec.ts") do
            path
          else
            Path.join(path, "#{slug(first.id)}.spatial-court.spec.ts")
          end

        {:ok, out}

      _ ->
        {:error, {:spatial_court_refused, :missing_out}}
    end
  end

  # --- PropertyGroup extraction ----------------------------------------------

  defp group_model(description, graph) do
    subject = description.subject
    id = term_id(subject)

    with {:ok, selector} <- group_selector(description, id),
         {:ok, members} <- members_for(graph, subject) do
      cond do
        # Option A: empty trays that only nest via shui:parentGroup are
        # scaffolding, not court subjects.
        members == [] and parent_tray?(graph, subject) ->
          :skip

        members == [] ->
          {:error, {:ungrouped_or_empty, term_id(subject)}}

        true ->
          {:ok,
           %{
             id: id,
             label: literal_or(description, iri(@rdfs <> "label"), id),
             selector: selector,
             order: numeric_or(description, iri(@sh <> "order"), 0),
             members: members
           }}
      end
    end
  end

  defp group_selector(description, id) do
    case first_literal(description, selector_predicates()) do
      nil -> {:ok, "[data-spatial-group=\"#{css_escape(id)}\"]"}
      sel -> {:ok, sel}
    end
  end

  # True when some other PropertyGroup declares shui:parentGroup pointing here.
  defp parent_tray?(graph, group_iri) do
    parent_pred = iri(@shui <> "parentGroup")
    group_class = iri(@sh <> "PropertyGroup")

    graph
    |> RDF.Graph.descriptions()
    |> Enum.any?(fn desc ->
      typed?(desc, group_class) and
        group_iri in RDF.Description.get(desc, parent_pred, [])
    end)
  end

  defp members_for(graph, group_iri) do
    group_pred = iri(@sh <> "group")

    results =
      graph
      |> RDF.Graph.descriptions()
      |> Enum.filter(fn desc ->
        group_iri in RDF.Description.get(desc, group_pred, [])
      end)
      |> Enum.map(&member_model/1)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        members =
          oks
          |> Enum.map(fn {:ok, m} -> m end)
          |> Enum.sort_by(& &1.order)

        {:ok, members}

      {_, errs} ->
        {:error, {:member_errors, Enum.map(errs, fn {:error, r} -> r end)}}
    end
  end

  defp member_model(description) do
    subject = description.subject
    id = term_id(subject)

    case member_selector(description, id) do
      {:ok, selector} ->
        {:ok,
         %{
           id: id,
           selector: selector,
           order: numeric_or(description, iri(@sh <> "order"), 0),
           touch?: touch?(description)
         }}

      {:error, _} = err ->
        err
    end
  end

  defp member_selector(description, id) do
    case first_literal(description, selector_predicates()) do
      nil ->
        if blank?(description.subject) do
          {:error, {:selector_required, id}}
        else
          {:ok, "[data-testid=\"#{css_escape(id)}\"]"}
        end

      sel ->
        {:ok, sel}
    end
  end

  defp selector_predicates do
    [iri(@shui <> "selector")]
  end

  defp touch?(description) do
    case first_literal(description, [
           iri(@shui <> "role"),
           iri(@shui <> "touchTarget")
         ]) do
      "touch" ->
        true

      "true" ->
        true

      "interactive" ->
        true

      _ ->
        case first_literal(description, [iri(@shui <> "interactive")]) do
          "true" -> true
          _ -> false
        end
    end
  end

  # --- RDF helpers -----------------------------------------------------------

  defp typed?(description, class),
    do: class in RDF.Description.get(description, RDF.type(), [])

  defp iri(string), do: RDF.iri(string)

  defp first_literal(description, predicates) do
    Enum.find_value(predicates, fn pred ->
      case RDF.Description.first(description, pred) do
        %RDF.Literal{} = lit -> RDF.Literal.value(lit) |> to_string()
        _ -> nil
      end
    end)
  end

  defp literal_or(description, pred, default) do
    case RDF.Description.first(description, pred) do
      %RDF.Literal{} = lit -> RDF.Literal.value(lit) |> to_string()
      _ -> default
    end
  end

  defp numeric_or(description, pred, default) do
    case RDF.Description.first(description, pred) do
      %RDF.Literal{} = lit ->
        case RDF.Literal.value(lit) do
          n when is_number(n) ->
            n

          s when is_binary(s) ->
            case Float.parse(s) do
              {n, _} -> n
              :error -> default
            end

          _ ->
            default
        end

      _ ->
        default
    end
  end

  defp term_id(%RDF.IRI{} = i) do
    s = RDF.IRI.to_string(i)

    cond do
      String.contains?(s, "#") -> s |> String.split("#") |> List.last()
      String.contains?(s, "/") -> s |> String.split("/") |> List.last()
      true -> s
    end
  end

  defp term_id(%RDF.BlankNode{} = b),
    do: "bnode-" <> String.replace(to_string(b), ~r/[^A-Za-z0-9_-]/, "")

  defp term_id(other), do: slug(inspect(other))

  defp blank?(%RDF.BlankNode{}), do: true
  defp blank?(_), do: false

  defp slug(id) do
    id
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp css_escape(id), do: String.replace(to_string(id), "\"", "\\\"")
end
