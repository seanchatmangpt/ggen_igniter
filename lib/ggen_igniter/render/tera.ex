defmodule GgenIgniter.Render.Tera do
  @moduledoc """
  A real, hand-rolled Tera-compatible template renderer.

  No actively maintained Tera-compatible template engine exists on hex.pm as of
  2026-08 (searched hex.pm's package index for "tera" and equivalents; the closest
  hit, `solid`, implements Liquid syntax -- different delimiters for filters
  (`{{ x | filter: arg }}` vs Tera's `{{ x | filter(attribute="x") }}`) and no
  `capitalize`/`filter(attribute=,value=)` semantics matching real ggen-marketplace
  templates). This module hand-rolls the subset of real Tera syntax actually used
  by marketplace templates (e.g. `ggen-combinatorial-maximalism-pack/templates/
  CMD_REPORT.md.tmpl`, `tcps-cli-pack/templates/kijun_rs.tmpl`):

    * `{{ var }}`, `{{ var.field }}`, `{{ list[0].field }}` -- interpolation with
      dotted / indexed access
    * `{% for x in list %}...{% endfor %}` -- loops
    * `{% if cond %}...{% else %}...{% endif %}` -- conditionals (else optional)
    * `{# comment #}` -- comments, stripped entirely
    * `{{ var | capitalize }}` -- capitalize filter
    * `{{ list | filter(attribute="x", value="y") }}` -- list filter by attribute

  This is `GgenIgniter.Render.Tera`, a separate, additional engine.
  `GgenIgniter.Render` (stdlib EEx) remains the default renderer and is
  unaffected by this module's existence.
  """

  @type bindings :: map()

  @doc """
  Renders `template_string` as a Tera-compatible template against `bindings`
  (a map; string or atom keys at the top level, string keys in nested maps as
  produced by JSON/SPARQL-result-style data).
  """
  @spec render(String.t(), bindings()) :: String.t()
  def render(template_string, bindings) when is_map(bindings) do
    bindings = normalize_top_level(bindings)

    template_string
    |> strip_comments()
    |> tokenize()
    |> parse()
    |> eval_nodes(bindings)
    |> IO.iodata_to_binary()
  end

  defp normalize_top_level(bindings) do
    Map.new(bindings, fn {k, v} -> {to_string(k), v} end)
  end

  # ---------------------------------------------------------------------------
  # Comments: {# ... #} stripped entirely before tokenizing.
  # ---------------------------------------------------------------------------

  defp strip_comments(str) do
    Regex.replace(~r/\{#.*?#\}/s, str, "")
  end

  # ---------------------------------------------------------------------------
  # Tokenizer: splits the template into a flat list of tokens:
  #   {:text, string}
  #   {:expr, "var.field | filter(...)"}
  #   {:tag, "for x in list"} | {:tag, "endfor"} | {:tag, "if cond"} |
  #   {:tag, "else"} | {:tag, "endif"}
  # ---------------------------------------------------------------------------

  @tag_re ~r/\{\%\s*(.*?)\s*\%\}|\{\{\s*(.*?)\s*\}\}/s

  defp tokenize(str) do
    parts = Regex.split(@tag_re, str, include_captures: true, trim: false)
    tokenize_parts(parts, [])
  end

  defp tokenize_parts([], acc), do: Enum.reverse(acc)

  defp tokenize_parts([piece | rest], acc) do
    cond do
      piece == "" ->
        tokenize_parts(rest, acc)

      match = Regex.run(~r/^\{\%\s*(.*?)\s*\%\}$/s, piece) ->
        [_, tag] = match
        tokenize_parts(rest, [{:tag, tag} | acc])

      match = Regex.run(~r/^\{\{\s*(.*?)\s*\}\}$/s, piece) ->
        [_, expr] = match
        tokenize_parts(rest, [{:expr, expr} | acc])

      true ->
        tokenize_parts(rest, [{:text, piece} | acc])
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: turns the flat token list into a tree of AST nodes:
  #   {:text, string}
  #   {:expr, expr_string}
  #   {:for, var_name, list_expr_string, body_nodes}
  #   {:if, cond_expr_string, then_nodes, else_nodes}
  # ---------------------------------------------------------------------------

  defp parse(tokens) do
    {nodes, []} = parse_nodes(tokens)
    nodes
  end

  defp parse_nodes(tokens), do: parse_nodes(tokens, [])

  defp parse_nodes([], acc), do: {Enum.reverse(acc), []}

  defp parse_nodes([{:tag, tag} | _] = tokens, acc) when tag in ["endfor", "endif", "else"] do
    {Enum.reverse(acc), tokens}
  end

  defp parse_nodes([{:text, t} | rest], acc) do
    parse_nodes(rest, [{:text, t} | acc])
  end

  defp parse_nodes([{:expr, e} | rest], acc) do
    parse_nodes(rest, [{:expr, e} | acc])
  end

  defp parse_nodes([{:tag, "for " <> for_spec} | rest], acc) do
    {var_name, list_expr} = parse_for_spec(for_spec)
    {body, rest2} = parse_nodes(rest)

    rest3 =
      case rest2 do
        [{:tag, "endfor"} | r] -> r
        _ -> raise "GgenIgniter.Render.Tera: missing {% endfor %} for {% for #{for_spec} %}"
      end

    parse_nodes(rest3, [{:for, var_name, list_expr, body} | acc])
  end

  defp parse_nodes([{:tag, "if " <> cond_expr} | rest], acc) do
    {then_nodes, rest2} = parse_nodes(rest)

    {else_nodes, rest3} =
      case rest2 do
        [{:tag, "else"} | r] -> parse_nodes(r)
        _ -> {[], rest2}
      end

    rest4 =
      case rest3 do
        [{:tag, "endif"} | r] -> r
        _ -> raise "GgenIgniter.Render.Tera: missing {% endif %} for {% if #{cond_expr} %}"
      end

    parse_nodes(rest4, [{:if, String.trim(cond_expr), then_nodes, else_nodes} | acc])
  end

  defp parse_nodes([{:tag, other} | _rest], _acc) do
    raise "GgenIgniter.Render.Tera: unsupported tag {% #{other} %}"
  end

  defp parse_for_spec(spec) do
    case Regex.run(~r/^(\S+)\s+in\s+(.+)$/s, String.trim(spec)) do
      [_, var_name, list_expr] -> {var_name, String.trim(list_expr)}
      nil -> raise "GgenIgniter.Render.Tera: malformed for-tag: for #{spec}"
    end
  end

  # ---------------------------------------------------------------------------
  # Evaluator
  # ---------------------------------------------------------------------------

  defp eval_nodes(nodes, scope) do
    Enum.map(nodes, &eval_node(&1, scope))
  end

  defp eval_node({:text, t}, _scope), do: t

  defp eval_node({:expr, expr}, scope) do
    expr
    |> eval_expr(scope)
    |> to_output_string()
  end

  defp eval_node({:for, var_name, list_expr, body}, scope) do
    list = eval_expr(list_expr, scope) || []

    Enum.map(list, fn item ->
      inner_scope = Map.put(scope, var_name, item)
      eval_nodes(body, inner_scope)
    end)
  end

  defp eval_node({:if, cond_expr, then_nodes, else_nodes}, scope) do
    if truthy?(eval_expr(cond_expr, scope)) do
      eval_nodes(then_nodes, scope)
    else
      eval_nodes(else_nodes, scope)
    end
  end

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(_), do: true

  defp to_output_string(nil), do: ""
  defp to_output_string(v) when is_binary(v), do: v
  defp to_output_string(v), do: to_string(v)

  # ---------------------------------------------------------------------------
  # Expression evaluation: `path.to.value | filter1 | filter2(arg="x")`
  # ---------------------------------------------------------------------------

  defp eval_expr(expr, scope) do
    [path_str | filter_strs] = String.split(expr, "|") |> Enum.map(&String.trim/1)

    value = eval_path(path_str, scope)

    Enum.reduce(filter_strs, value, fn filter_str, acc ->
      apply_filter(acc, filter_str)
    end)
  end

  # Parses and resolves a dotted/indexed access path against scope, e.g.
  # "list[0].field", "d.title", "candidate.authority".
  defp eval_path(path_str, scope) do
    segments = parse_path_segments(path_str)

    case segments do
      [] ->
        nil

      [root | rest] ->
        root_value = Map.get(scope, root)
        Enum.reduce(rest, root_value, &access(&2, &1))
    end
  end

  # Splits "list[0].field.sub" into ["list", {:index, 0}, "field", "sub"].
  defp parse_path_segments(path_str) do
    path_str
    |> String.split(".")
    |> Enum.flat_map(&split_index_accesses/1)
  end

  defp split_index_accesses(segment) do
    case Regex.run(~r/^([^\[\]]+)((?:\[\d+\])*)$/, segment) do
      [_, name, brackets] ->
        indices =
          ~r/\[(\d+)\]/
          |> Regex.scan(brackets)
          |> Enum.map(fn [_, n] -> {:index, String.to_integer(n)} end)

        [name | indices]

      nil ->
        [segment]
    end
  end

  defp access(nil, _seg), do: nil

  defp access(coll, {:index, i}) when is_list(coll) do
    Enum.at(coll, i)
  end

  defp access(map, seg) when is_map(map) and is_binary(seg) do
    Map.get(map, seg) || Map.get(map, safe_atom(seg))
  end

  defp access(_other, _seg), do: nil

  defp safe_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  # ---------------------------------------------------------------------------
  # Filters
  # ---------------------------------------------------------------------------

  defp apply_filter(value, "capitalize") do
    case value do
      v when is_binary(v) and v != "" ->
        String.upcase(String.slice(v, 0, 1)) <> String.slice(v, 1..-1//1)

      v ->
        v
    end
  end

  defp apply_filter(value, "filter(" <> rest) do
    args = parse_filter_args(String.trim_trailing(rest, ")"))
    attribute = Map.fetch!(args, "attribute")
    filter_value = Map.fetch!(args, "value")

    case value do
      list when is_list(list) ->
        Enum.filter(list, fn item -> access(item, attribute) == filter_value end)

      other ->
        other
    end
  end

  defp apply_filter(value, unknown) do
    raise "GgenIgniter.Render.Tera: unsupported filter `#{unknown}` (value: #{inspect(value)})"
  end

  # Parses `attribute="x", value="y"` into %{"attribute" => "x", "value" => "y"}.
  defp parse_filter_args(args_str) do
    ~r/(\w+)\s*=\s*"([^"]*)"/
    |> Regex.scan(args_str)
    |> Map.new(fn [_, k, v] -> {k, v} end)
  end
end
