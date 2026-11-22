defmodule GgenIgniter.BrandTheme do
  @moduledoc """
  Emits Tailwind CSS v4 `@theme` fluid spacing tokens from a DTCG-aligned
  `*.brand.toml` (Fourth Watch / mobile-ui-layout-pack).

  Sibling of `GgenIgniter.SpatialCourt` — Step-3 theme half (OI-15). This
  module never reads SHACL graphs and never writes into `spatial-court-pack`.

  Public paths:

    * `from_brand/1` — decode brand.toml, refuse when primitive.space is absent
      or a curly-brace `{token.path}` alias cannot be resolved
    * `render/2` — EEx-render `priv/ggen/brand-theme-pack/templates/theme_spacing.css.eex`
      (or an override `:template`) with resolved `@theme` entries + utility shell
    * `emit/2` — `render/2` then write `theme-spacing.css` (default name)

  Alias rule: `{primitive.space.0_5}` becomes `var(--spacing-0_5)` when the
  target is itself a theme entry; literals (`clamp(...)`, `8px`, `100dvh`)
  pass through. Never emits `@property` for cqi tokens.
  """

  @type token :: %{
          path: String.t(),
          css: String.t(),
          value: String.t(),
          description: String.t() | nil
        }

  @type brand :: %{
          meta: map(),
          tokens: [token()],
          theme_entries: [{String.t(), String.t()}],
          invariants: map(),
          source: String.t()
        }

  @doc "Pack-relative path of the shipped Tailwind `@theme` EEx template."
  @spec template_path() :: String.t()
  def template_path do
    Path.join([
      :code.priv_dir(:ggen_igniter) |> to_string(),
      "ggen",
      "brand-theme-pack",
      "templates",
      "theme_spacing.css.eex"
    ])
  end

  @doc """
  Load and normalize a DTCG brand.toml. Returns
  `{:error, {:brand_theme_refused, reason}}` on missing file, decode failure,
  absent primitive.space, or unresolved alias.
  """
  @spec from_brand(String.t()) :: {:ok, brand()} | {:error, term()}
  def from_brand(path) when is_binary(path) do
    cond do
      not File.regular?(path) ->
        {:error, {:brand_theme_refused, {:brand_missing, path}}}

      true ->
        with {:ok, raw} <- File.read(path),
             {:ok, table} <- decode_toml(raw),
             {:ok, brand} <- build_brand(table, path) do
          {:ok, brand}
        end
    end
  rescue
    e -> {:error, {:brand_theme_refused, {:brand_unreadable, path, Exception.message(e)}}}
  end

  def from_brand(_), do: {:error, {:brand_theme_refused, :not_a_string}}

  @doc """
  Render the Tailwind `@theme` CSS. Options:

    * `:template` — absolute path override (default `template_path/0`);
      YAML frontmatter (`---` … `---`) is stripped when present (marketplace `.tmpl`)
  """
  @spec render(brand(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(brand, opts \\ [])

  def render(%{theme_entries: entries, meta: meta} = brand, opts)
      when is_list(entries) and entries != [] do
    template = Keyword.get(opts, :template) || template_path()

    unless File.regular?(template) do
      {:error, {:brand_theme_refused, {:template_missing, template}}}
    else
      body =
        template
        |> File.read!()
        |> strip_frontmatter()
        |> GgenIgniter.Render.render(
          theme_entries: entries,
          meta: meta,
          brand_id: Map.get(meta, "id") || Map.get(meta, :id) || "brand",
          brand_name: Map.get(meta, "name") || Map.get(meta, :name) || "Brand",
          dtcg: Map.get(meta, "dtcg") || Map.get(meta, :dtcg) || "2025.10",
          source: brand.source,
          token_count: length(brand.tokens)
        )

      {:ok, body}
    end
  rescue
    e -> {:error, {:brand_theme_refused, {:render_failed, Exception.message(e)}}}
  end

  def render(_, _), do: {:error, {:brand_theme_refused, :empty_theme}}

  @doc """
  Render and write the theme CSS. `:out` is required (directory or `*.css` path).
  Returns `{:ok, path}` of the written file.
  """
  @spec emit(brand(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def emit(brand, opts) when is_list(opts) do
    with {:ok, out} <- resolve_out(brand, opts),
         {:ok, body} <- render(brand, opts) do
      File.mkdir_p!(Path.dirname(out))
      File.write!(out, body)
      {:ok, out}
    end
  end

  # --- brand.toml → theme model ---------------------------------------------

  defp decode_toml(raw) do
    case Toml.decode(raw) do
      {:ok, %{} = table} -> {:ok, table}
      {:ok, _} -> {:error, {:brand_theme_refused, :brand_not_a_table}}
      {:error, reason} -> {:error, {:brand_theme_refused, {:toml_decode, reason}}}
    end
  end

  defp build_brand(table, path) do
    meta = Map.get(table, "meta", %{})
    invariants = get_in(table, ["extensions", "ggen", "invariants"]) || %{}
    catalog = collect_dimension_tokens(table)
    prim = Map.get(catalog, "primitive.space") || %{}

    if map_size(prim) == 0 do
      {:error, {:brand_theme_refused, :no_primitive_space}}
    else
      case curated_theme_entries(table, catalog) do
        {:ok, entries, tokens} ->
          {:ok,
           %{
             meta: meta,
             tokens: tokens,
             theme_entries: entries,
             invariants: invariants,
             source: path
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  # Walk primitive / semantic / component for {$value} dimension leaves.
  defp collect_dimension_tokens(table) do
    Enum.reduce(["primitive", "semantic", "component"], %{}, fn layer, acc ->
      case Map.get(table, layer) do
        %{} = groups ->
          Enum.reduce(groups, acc, fn {group, nodes}, acc2 ->
            case nodes do
              %{} = n ->
                path_prefix = "#{layer}.#{group}"
                Map.put(acc2, path_prefix, leaf_tokens(n, path_prefix))

              _ ->
                acc2
            end
          end)

        _ ->
          acc
      end
    end)
  end

  defp leaf_tokens(nodes, path_prefix) do
    Enum.reduce(nodes, %{}, fn
      {key, %{"$value" => value} = node}, acc when is_binary(value) ->
        Map.put(acc, "#{path_prefix}.#{key}", %{
          path: "#{path_prefix}.#{key}",
          key: key,
          raw: value,
          description: Map.get(node, "$description")
        })

      {key, %{} = nested}, acc ->
        # Nested non-leaf (e.g. group-level $type/$description) — skip type-only keys
        if Map.has_key?(nested, "$value") do
          acc
        else
          Map.merge(acc, leaf_tokens(nested, "#{path_prefix}.#{key}"))
        end

      _, acc ->
        acc
    end)
  end

  # Curated emission order matching templates/110_theme_spacing_css.tmpl.
  defp curated_theme_entries(table, catalog) do
    specs = [
      {:group, "primitive.space", &spacing_css/1},
      {:group, "semantic.space", &spacing_css/1},
      {:alias, "component.card.padding", "--spacing-card"},
      {:alias, "semantic.touch.target_min", "--spacing-touch-min"},
      {:alias, "semantic.touch.target_comfortable", "--spacing-touch-comfortable"},
      {:alias, "semantic.touch.gap_min", "--spacing-touch-gap"},
      {:alias, "semantic.viewport.height", "--spacing-shell-height"},
      {:alias, "semantic.viewport.prose_max", "--spacing-prose-max"},
      {:alias, "semantic.viewport.container_max", "--spacing-container-max"}
    ]

    flat = flatten_catalog(catalog)

    case expand_specs(specs, flat, table) do
      {:ok, entries, tokens} -> {:ok, entries, tokens}
      {:error, _} = err -> err
    end
  end

  defp flatten_catalog(catalog) do
    Enum.reduce(catalog, %{}, fn {_group, leaves}, acc -> Map.merge(acc, leaves) end)
  end

  defp expand_specs(specs, flat, table) do
    Enum.reduce_while(specs, {:ok, [], []}, fn spec, {:ok, entries, tokens} ->
      case expand_spec(spec, flat, table) do
        {:ok, more_entries, more_tokens} ->
          {:cont, {:ok, entries ++ more_entries, tokens ++ more_tokens}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp expand_spec({:group, group_path, css_fun}, flat, _table) do
    leaves =
      flat
      |> Enum.filter(fn {path, _} -> String.starts_with?(path, group_path <> ".") end)
      |> Enum.sort_by(fn {path, leaf} -> group_sort_key(group_path, leaf.key, path) end)

    if leaves == [] do
      {:error, {:brand_theme_refused, {:missing_group, group_path}}}
    else
      reduce_leaves(leaves, css_fun, flat)
    end
  end

  defp expand_spec({:alias, path, css_name}, flat, table) do
    case lookup_leaf(path, flat, table) do
      {:ok, leaf} ->
        # Curated touch/viewport/card slots inline to literals (matches
        # marketplace 110_theme_spacing_css.tmpl: `--spacing-touch-min: 44px`).
        case resolve_literal(leaf.raw, flat) do
          {:ok, value} ->
            token = %{
              path: path,
              css: css_name,
              value: value,
              description: Map.get(leaf, :description)
            }

            {:ok, [{css_name, value}], [token]}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp reduce_leaves(leaves, css_fun, flat) do
    Enum.reduce_while(leaves, {:ok, [], []}, fn {path, leaf}, {:ok, entries, tokens} ->
      css = css_fun.(leaf.key)

      case resolve_value(leaf.raw, flat) do
        {:ok, value} ->
          token = %{
            path: path,
            css: css,
            value: value,
            description: Map.get(leaf, :description)
          }

          {:cont, {:ok, entries ++ [{css, value}], tokens ++ [token]}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp lookup_leaf(path, flat, table) do
    case Map.fetch(flat, path) do
      {:ok, leaf} ->
        {:ok, leaf}

      :error ->
        # Direct walk for paths not collected (should be rare)
        parts = String.split(path, ".")

        case get_in(table, parts) do
          %{"$value" => value} = node when is_binary(value) ->
            {:ok,
             %{
               path: path,
               key: List.last(parts),
               raw: value,
               description: Map.get(node, "$description")
             }}

          _ ->
            {:error, {:brand_theme_refused, {:token_missing, path}}}
        end
    end
  end

  # Space-ladder aliases → `var(--spacing-*)` (keeps Gestalt ladder linked).
  defp resolve_value(raw, flat) do
    case Regex.run(~r/^\{([a-zA-Z0-9_.]+)\}$/, String.trim(raw)) do
      [_, ref_path] ->
        case Map.fetch(flat, ref_path) do
          {:ok, target} ->
            css = css_name_for_path(ref_path, target.key)
            {:ok, "var(#{css})"}

          :error ->
            {:error, {:brand_theme_refused, {:unresolved_alias, raw}}}
        end

      nil ->
        {:ok, String.trim(raw)}
    end
  end

  # Fully expand `{token.path}` chains to a concrete CSS value.
  defp resolve_literal(raw, flat, depth \\ 0)
  defp resolve_literal(_raw, _flat, depth) when depth > 16,
    do: {:error, {:brand_theme_refused, :alias_cycle}}

  defp resolve_literal(raw, flat, depth) do
    case Regex.run(~r/^\{([a-zA-Z0-9_.]+)\}$/, String.trim(raw)) do
      [_, ref_path] ->
        case Map.fetch(flat, ref_path) do
          {:ok, target} -> resolve_literal(target.raw, flat, depth + 1)
          :error -> {:error, {:brand_theme_refused, {:unresolved_alias, raw}}}
        end

      nil ->
        {:ok, String.trim(raw)}
    end
  end

  defp css_name_for_path(path, key) do
    cond do
      String.starts_with?(path, "primitive.space.") -> spacing_css(key)
      String.starts_with?(path, "semantic.space.") -> spacing_css(key)
      path == "semantic.touch.target_min" -> "--spacing-touch-min"
      path == "semantic.touch.target_comfortable" -> "--spacing-touch-comfortable"
      path == "semantic.touch.gap_min" -> "--spacing-touch-gap"
      path == "primitive.touch.apple" -> "--spacing-touch-min"
      path == "primitive.touch.material" -> "--spacing-touch-comfortable"
      path == "primitive.touch.gap" -> "--spacing-touch-gap"
      true -> spacing_css(key)
    end
  end

  defp spacing_css(key) when is_binary(key) do
    suffix =
      if String.match?(key, ~r/^\d/) do
        key
      else
        String.replace(key, "_", "-")
      end

    "--spacing-#{suffix}"
  end

  # Primitive: 0, 0_5, 1, … — Semantic: Gestalt ladder then fluid (tmpl order).
  @semantic_space_order ~w(
    tight related grouped section topic
    margin_compact margin_medium pane_gap
    fluid_inset fluid_stack fluid_section
  )

  defp group_sort_key("primitive.space", key, path), do: {space_sort_key(key), path}

  defp group_sort_key("semantic.space", key, path) do
    idx =
      case Enum.find_index(@semantic_space_order, &(&1 == key)) do
        nil -> 1_000
        i -> i
      end

    {idx, path}
  end

  defp group_sort_key(_group, key, path), do: {space_sort_key(key), path}

  defp space_sort_key(key) do
    case Regex.run(~r/^(\d+)(?:_(\d+))?$/, key) do
      [_, a, b] -> {0, String.to_integer(a), String.to_integer(b)}
      [_, a] -> {0, String.to_integer(a), 0}
      _ -> {1, 0, 0}
    end
  end

  defp strip_frontmatter(body) do
    case String.split(body, ~r/^---\s*\n/m, parts: 3) do
      ["", _fm, rest] -> rest
      _ -> body
    end
  end

  defp resolve_out(%{meta: meta}, opts) do
    case Keyword.get(opts, :out) do
      path when is_binary(path) and path != "" ->
        out =
          if String.ends_with?(path, ".css") do
            path
          else
            id = Map.get(meta, "id") || Map.get(meta, :id) || "theme"
            Path.join(path, "#{slug(id)}-theme-spacing.css")
          end

        {:ok, out}

      _ ->
        {:error, {:brand_theme_refused, :missing_out}}
    end
  end

  defp slug(id) do
    id
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
