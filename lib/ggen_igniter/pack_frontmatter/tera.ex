defmodule GgenIgniter.PackFrontmatter.Tera do
  @moduledoc """
  Interpreter for the Tera subset ggen frontmatter packs actually use.

  `GgenIgniter.Render` is EEx; ggen packs (`ash-a2a-app-pack`, ...) write bodies in Tera
  (`{{ x }}`, `{% for %}`, `{% set %}`, filters). This module parses and evaluates that
  subset directly (no EEx translation, so whitespace control matches Tera by construction).

  ## Supported

    * `{{ expr }}`, `{% set n = expr %}`, `{% for v in expr %}...{% endfor %}`,
      `{% if %}/{% elif %}/{% else %}/{% endif %}`, `{# comment #}`
    * whitespace control: `{{-`, `-}}`, `{%-`, `-%}`, `{#-`, `-#}` (trims ALL adjacent
      whitespace including newlines, as Tera does)
    * `{% macro name(a, b) %}...{% endmacro name %}` (positional params, no defaults) called as
      `{{ self::name(a=x, b=y) }}`; macro bodies see only their arguments (Tera isolation)
    * `{% set_global n = expr %}` (survives `for` scopes), `{% for k, v in map %}`
    * arithmetic `+ - * / %` and string concat `~`
    * tests `is defined|starting_with(s)|ending_with(s)|containing(s)|matching(re)` (and `is not`)
    * literals (`"s"`, `'s'`, integers, floats, `true`/`false`), paths (`a.b`, `a[0]`,
      `a[expr]`), `loop.index|index0|first|last`
    * operators `== != < > <= >= and or not`
    * filters: `length default(value=) split(pat=) filter(attribute=,value=) first last
      group_by(attribute=) trim_start_matches(pat=) trim_end_matches(pat=)
      json_encode safe upper lower trim join(sep=) replace(from=,to=)`

  Anything else raises `ArgumentError` naming the construct (never a silent pass-through).
  Bodies are NOT HTML-autoescaped (Tera only escapes `.html/.htm/.xml` template names; pack
  templates are `.tmpl`). The template's trailing newline is preserved.

  Bindings are string-keyed maps (SPARQL rows are string-keyed); referencing an undefined
  variable in `{{ }}` raises, in `if`/filters it is falsy/undefined (Tera semantics).
  """

  @type bindings :: %{optional(String.t()) => term()}

  @doc "Renders `template` against string-keyed `bindings`."
  @spec render(String.t(), bindings()) :: String.t()
  def render(template, bindings) when is_binary(template) and is_map(bindings) do
    nodes = template |> tokenize() |> parse()
    {macros, nodes} = hoist_macros(nodes)
    env = bindings |> Map.put(:__macros__, macros) |> Map.put(:__globals__, %{})
    {out, _env} = render_nodes(nodes, env)
    IO.iodata_to_binary(out)
  end

  # Tera macros are file-level: collect top-level `{% macro %}` definitions (usable before and
  # after their definition site) and drop them from the render tree.
  defp hoist_macros(nodes) do
    {defs, rest} = Enum.split_with(nodes, &match?({:macro, _, _, _}, &1))
    {Map.new(defs, fn {:macro, name, params, body} -> {name, {params, body}} end), rest}
  end

  # -- tokenizer ---------------------------------------------------------------

  defp tokenize(src), do: src |> scan([]) |> apply_trim()

  defp scan("", acc), do: Enum.reverse(acc)

  defp scan(src, acc) do
    case next_open(src) do
      nil ->
        Enum.reverse([{:text, src} | acc])

      {idx, kind} ->
        {text, rest} = String.split_at(src, idx)
        acc = if text == "", do: acc, else: [{:text, text} | acc]
        {tok, rest} = read_tag(rest, kind)
        scan(rest, [tok | acc])
    end
  end

  # earliest of `{{`, `{%`, `{#`
  defp next_open(src) do
    [{"{{", :var}, {"{%", :tag}, {"{#", :comment}]
    |> Enum.flat_map(fn {pat, kind} ->
      case :binary.match(src, pat) do
        {pos, _} -> [{pos, kind}]
        :nomatch -> []
      end
    end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
  end

  defp read_tag(<<_::binary-size(2), rest::binary>>, kind) do
    close =
      case kind do
        :var -> "}}"
        :tag -> "%}"
        :comment -> "#}"
      end

    case :binary.match(rest, close) do
      :nomatch ->
        raise ArgumentError,
              "tera: unterminated #{kind} tag near #{inspect(String.slice(rest, 0, 40))}"

      {pos, _} ->
        inner = binary_part(rest, 0, pos)
        after_close = binary_part(rest, pos + 2, byte_size(rest) - pos - 2)
        {trim_l, inner} = strip_marker_l(inner)
        {trim_r, inner} = strip_marker_r(inner)
        {{kind, String.trim(inner), trim_l, trim_r}, after_close}
    end
  end

  defp strip_marker_l("-" <> rest), do: {true, rest}
  defp strip_marker_l(s), do: {false, s}

  defp strip_marker_r(s) do
    if String.ends_with?(s, "-"),
      do: {true, binary_part(s, 0, byte_size(s) - 1)},
      else: {false, s}
  end

  defp apply_trim(tokens), do: do_trim(tokens, [], false)

  defp do_trim([], acc, _trim_next), do: Enum.reverse(acc)

  defp do_trim([{:text, t} | rest], acc, trim_next) do
    t = if trim_next, do: String.trim_leading(t), else: t
    do_trim(rest, [{:text, t} | acc], false)
  end

  defp do_trim([{kind, body, trim_l, trim_r} | rest], acc, _trim_next) do
    acc =
      if trim_l do
        case acc do
          [{:text, t} | tail] -> [{:text, String.trim_trailing(t)} | tail]
          other -> other
        end
      else
        acc
      end

    do_trim(rest, [{kind, body} | acc], trim_r)
  end

  # -- block parser ------------------------------------------------------------

  defp parse(tokens) do
    {nodes, rest} = parse_block(tokens, [])

    case rest do
      [] -> nodes
      [{:tag, t} | _] -> raise ArgumentError, "tera: unexpected {% #{t} %}"
    end
  end

  # returns {nodes, remaining_tokens_starting_at_terminator_or_empty}
  defp parse_block([], acc), do: {Enum.reverse(acc), []}
  defp parse_block([{:text, t} | rest], acc), do: parse_block(rest, [{:text, t} | acc])
  defp parse_block([{:comment, _} | rest], acc), do: parse_block(rest, acc)
  defp parse_block([{:var, e} | rest], acc), do: parse_block(rest, [{:out, parse_expr(e)} | acc])

  defp parse_block([{:tag, body} = tok | rest], acc),
    do: parse_tag(head(body), body, tok, rest, acc)

  defp parse_tag("set", body, _tok, rest, acc) do
    [_, name, expr] = Regex.run(~r/^set\s+([A-Za-z_]\w*)\s*=\s*(.+)$/s, body) || bad_tag(body)
    parse_block(rest, [{:set, name, parse_expr(expr)} | acc])
  end

  defp parse_tag("set_global", body, _tok, rest, acc) do
    [_, name, expr] =
      Regex.run(~r/^set_global\s+([A-Za-z_]\w*)\s*=\s*(.+)$/s, body) || bad_tag(body)

    parse_block(rest, [{:set_global, name, parse_expr(expr)} | acc])
  end

  defp parse_tag("macro", body, _tok, rest, acc) do
    [_, name, params] =
      Regex.run(~r/^macro\s+([A-Za-z_]\w*)\s*\((.*)\)$/s, body) || bad_tag(body)

    params = parse_params(params, body)
    {inner, rest} = parse_block(rest, [])
    rest = expect_end(rest, "endmacro")
    parse_block(rest, [{:macro, name, params, inner} | acc])
  end

  defp parse_tag("for", body, _tok, rest, acc) do
    [_, var, var2, expr] =
      Regex.run(~r/^for\s+([A-Za-z_]\w*)(?:\s*,\s*([A-Za-z_]\w*))?\s+in\s+(.+)$/s, body) ||
        bad_tag(body)

    {inner, rest} = parse_block(rest, [])
    rest = expect_end(rest, "endfor")

    parse_block(rest, [
      {:for, var, if(var2 == "", do: nil, else: var2), parse_expr(expr), inner} | acc
    ])
  end

  defp parse_tag("if", body, _tok, rest, acc) do
    cond_src = String.replace_prefix(body, "if", "")
    {node, rest} = parse_if(parse_expr(cond_src), rest)
    parse_block(rest, [node | acc])
  end

  defp parse_tag(t, _body, tok, rest, acc)
       when t in ["elif", "else", "endif", "endfor", "endmacro"],
       do: {Enum.reverse(acc), [tok | rest]}

  defp parse_tag(_other, body, _tok, _rest, _acc), do: bad_tag(body)

  defp parse_if(first_cond, rest) do
    {body, rest} = parse_block(rest, [])
    parse_if_branches([{first_cond, body}], rest)
  end

  defp parse_if_branches(branches, [{:tag, body} | rest]) do
    case head(body) do
      "elif" ->
        c = parse_expr(String.replace_prefix(body, "elif", ""))
        {b, rest} = parse_block(rest, [])
        parse_if_branches([{c, b} | branches], rest)

      "else" ->
        {b, rest} = parse_block(rest, [])
        rest = expect_end(rest, "endif")
        {{:if, Enum.reverse(branches), b}, rest}

      "endif" ->
        {{:if, Enum.reverse(branches), []}, rest}

      other ->
        raise ArgumentError, "tera: unexpected {% #{other} %} inside if"
    end
  end

  defp parse_if_branches(_branches, []), do: raise(ArgumentError, "tera: missing {% endif %}")

  defp expect_end([{:tag, body} | rest], name) do
    if head(body) == name,
      do: rest,
      else: raise(ArgumentError, "tera: expected {% #{name} %}, got {% #{body} %}")
  end

  defp expect_end([], name), do: raise(ArgumentError, "tera: missing {% #{name} %}")

  defp parse_params("", _body), do: []

  defp parse_params(params, body) do
    params
    |> String.split(",")
    |> Enum.map(fn p ->
      p = String.trim(p)
      if Regex.match?(~r/^[A-Za-z_]\w*$/, p), do: p, else: bad_tag(body)
    end)
  end

  defp head(body), do: body |> String.split(~r/\s+/, parts: 2) |> hd()
  defp bad_tag(body), do: raise(ArgumentError, "tera: unsupported or malformed tag {% #{body} %}")

  # -- expression parser -------------------------------------------------------

  defp parse_expr(src) do
    {ast, rest} = src |> lex_expr([]) |> p_or()

    case rest do
      [] ->
        ast

      _ ->
        raise ArgumentError,
              "tera: trailing tokens in expression #{inspect(src)}: #{inspect(rest)}"
    end
  end

  @punct [
    "==",
    "!=",
    ">=",
    "<=",
    "::",
    ">",
    "<",
    "|",
    "(",
    ")",
    "[",
    "]",
    ",",
    ".",
    "=",
    "~",
    "+",
    "-",
    "*",
    "/",
    "%"
  ]

  defp lex_expr(src, acc) do
    src = String.trim_leading(src)

    cond do
      src == "" ->
        Enum.reverse(acc)

      match = Regex.run(~r/^"((?:[^"\\]|\\.)*)"/s, src) ->
        [full, s] = match
        lex_expr(rest_after(src, full), [{:str, unescape(s)} | acc])

      match = Regex.run(~r/^'((?:[^'\\]|\\.)*)'/s, src) ->
        [full, s] = match
        lex_expr(rest_after(src, full), [{:str, unescape(s)} | acc])

      match = Regex.run(~r/^-?\d+\.\d+/, src) ->
        [full] = match
        lex_expr(rest_after(src, full), [{:num, String.to_float(full)} | acc])

      match = Regex.run(~r/^-?\d+/, src) ->
        [full] = match
        lex_expr(rest_after(src, full), [{:num, String.to_integer(full)} | acc])

      match = Regex.run(~r/^[A-Za-z_]\w*/, src) ->
        [full] = match
        lex_expr(rest_after(src, full), [ident_token(full) | acc])

      p = Enum.find(@punct, &String.starts_with?(src, &1)) ->
        lex_expr(rest_after(src, p), [{:p, p} | acc])

      true ->
        raise ArgumentError,
              "tera: cannot lex expression near #{inspect(String.slice(src, 0, 20))}"
    end
  end

  defp rest_after(src, prefix),
    do: binary_part(src, byte_size(prefix), byte_size(src) - byte_size(prefix))

  defp unescape(s),
    do:
      s
      |> String.replace("\\\"", "\"")
      |> String.replace("\\'", "'")
      |> String.replace("\\n", "\n")
      |> String.replace("\\\\", "\\")

  defp ident_token("true"), do: {:bool, true}
  defp ident_token("false"), do: {:bool, false}
  defp ident_token(w) when w in ["and", "or", "not"], do: {:kw, w}
  defp ident_token(w), do: {:id, w}

  defp p_or(toks) do
    {l, toks} = p_and(toks)
    loop_bin(toks, l, "or", &p_and/1, :or)
  end

  defp p_and(toks) do
    {l, toks} = p_not(toks)
    loop_bin(toks, l, "and", &p_not/1, :and)
  end

  defp loop_bin([{:kw, kw} | toks], l, kw, next, tag) do
    {r, toks} = next.(toks)
    loop_bin(toks, {tag, l, r}, kw, next, tag)
  end

  defp loop_bin(toks, l, _kw, _next, _tag), do: {l, toks}

  defp p_not([{:kw, "not"} | toks]) do
    {e, toks} = p_not(toks)
    {{:not, e}, toks}
  end

  defp p_not(toks), do: p_cmp(toks)

  defp p_cmp(toks) do
    {l, toks} = p_sum(toks)

    case toks do
      [{:p, op} | rest] when op in ["==", "!=", ">", "<", ">=", "<="] ->
        {r, rest} = p_sum(rest)
        {{:cmp, op, l, r}, rest}

      [{:id, "is"}, {:kw, "not"}, {:id, name} | rest] ->
        p_test(l, name, true, rest)

      [{:id, "is"}, {:id, name} | rest] ->
        p_test(l, name, false, rest)

      _ ->
        {l, toks}
    end
  end

  defp p_test(subject, name, negate, toks) do
    {args, toks} =
      case toks do
        [{:p, "("} | rest] -> p_pos_args(rest, [])
        _ -> {[], toks}
      end

    {{:test, name, negate, subject, args}, toks}
  end

  defp p_pos_args([{:p, ")"} | rest], acc), do: {Enum.reverse(acc), rest}
  defp p_pos_args([{:p, ","} | rest], acc), do: p_pos_args(rest, acc)

  defp p_pos_args(toks, acc) do
    {e, toks} = p_or(toks)
    p_pos_args(toks, [e | acc])
  end

  defp p_sum(toks) do
    {l, toks} = p_prod(toks)
    p_sum_loop(l, toks)
  end

  defp p_sum_loop(l, [{:p, op} | toks]) when op in ["+", "-", "~"] do
    {r, toks} = p_prod(toks)
    p_sum_loop({:bin, op, l, r}, toks)
  end

  defp p_sum_loop(l, toks), do: {l, toks}

  defp p_prod(toks) do
    {l, toks} = p_filtered(toks)
    p_prod_loop(l, toks)
  end

  defp p_prod_loop(l, [{:p, op} | toks]) when op in ["*", "/", "%"] do
    {r, toks} = p_filtered(toks)
    p_prod_loop({:bin, op, l, r}, toks)
  end

  defp p_prod_loop(l, toks), do: {l, toks}

  defp p_filtered(toks) do
    {base, toks} = p_primary(toks)
    p_filters(base, toks)
  end

  defp p_filters(base, [{:p, "|"}, {:id, name} | toks]) do
    {args, toks} =
      case toks do
        [{:p, "("} | rest] -> p_args(rest, [])
        _ -> {[], toks}
      end

    p_filters({:filter, name, base, args}, toks)
  end

  defp p_filters(base, toks), do: {base, toks}

  defp p_args([{:p, ")"} | rest], acc), do: {Enum.reverse(acc), rest}
  defp p_args([{:p, ","} | rest], acc), do: p_args(rest, acc)

  defp p_args([{:id, k}, {:p, "="} | rest], acc) do
    {v, rest} = p_or(rest)
    p_args(rest, [{k, v} | acc])
  end

  defp p_args(toks, _),
    do: raise(ArgumentError, "tera: bad filter args near #{inspect(Enum.take(toks, 3))}")

  defp p_primary([{:str, s} | t]), do: {{:lit, s}, t}
  defp p_primary([{:num, n} | t]), do: {{:lit, n}, t}
  defp p_primary([{:bool, b} | t]), do: {{:lit, b}, t}

  defp p_primary([{:p, "("} | t]) do
    {e, t} = p_or(t)

    case t do
      [{:p, ")"} | t] -> {e, t}
      _ -> raise ArgumentError, "tera: missing )"
    end
  end

  defp p_primary([{:id, "self"}, {:p, "::"}, {:id, name}, {:p, "("} | t]) do
    {args, t} = p_args(t, [])
    p_path({:call, name, args}, t)
  end

  defp p_primary([{:id, _}, {:p, "::"} | _] = toks),
    do:
      raise(
        ArgumentError,
        "tera: unsupported macro namespace call near #{inspect(Enum.take(toks, 4))} (only self:: is supported)"
      )

  defp p_primary([{:id, name} | t]), do: p_path({:var, name}, t)

  defp p_primary(toks),
    do: raise(ArgumentError, "tera: unexpected token #{inspect(Enum.take(toks, 2))}")

  defp p_path(base, [{:p, "."}, {:id, f} | t]), do: p_path({:get, base, {:lit, f}}, t)

  defp p_path(base, [{:p, "."}, {:num, n} | t]) when is_integer(n),
    do: p_path({:get, base, {:lit, n}}, t)

  defp p_path(base, [{:p, "["} | t]) do
    {idx, t} = p_or(t)

    case t do
      [{:p, "]"} | t] -> p_path({:get, base, idx}, t)
      _ -> raise ArgumentError, "tera: missing ]"
    end
  end

  defp p_path(base, t), do: {base, t}

  # -- evaluator ---------------------------------------------------------------

  defp render_nodes(nodes, env) do
    Enum.reduce(nodes, {[], env}, fn node, {out, env} ->
      {piece, env} = render_node(node, env)
      {[out, piece], env}
    end)
  end

  defp render_node({:text, t}, env), do: {t, env}

  defp render_node({:out, expr}, env) do
    {stringify(eval(expr, env, :strict), expr), env}
  end

  defp render_node({:set, name, expr}, env), do: {"", Map.put(env, name, eval(expr, env, :lax))}

  defp render_node({:set_global, name, expr}, env) do
    v = eval(expr, env, :lax)
    {"", env |> Map.put(name, v) |> Map.update(:__globals__, %{name => v}, &Map.put(&1, name, v))}
  end

  defp render_node({:macro, _, _, _}, env), do: {"", env}

  defp render_node({:for, var, var2, expr, body}, env) do
    items =
      case {eval(expr, env, :lax), var2} do
        {m, v2} when is_map(m) and v2 != nil ->
          Enum.sort_by(m, &elem(&1, 0))

        {_, v2} when v2 != nil ->
          raise ArgumentError, "tera: for #{var}, #{var2} requires an object"

        {l, nil} when is_list(l) ->
          l

        {nil, _} ->
          []

        {other, _} ->
          raise ArgumentError, "tera: cannot iterate over #{inspect(other)}"
      end

    n = length(items)

    {out, globals} =
      items
      |> Enum.with_index()
      |> Enum.map_reduce(Map.get(env, :__globals__, %{}), fn {item, i}, globals ->
        loop = %{"index" => i + 1, "index0" => i, "first" => i == 0, "last" => i == n - 1}

        base =
          env
          |> Map.merge(globals)
          |> Map.put(:__globals__, globals)
          |> Map.put("loop", loop)

        scoped =
          case {var2, item} do
            {nil, _} -> Map.put(base, var, item)
            {_, {k, v}} -> base |> Map.put(var, k) |> Map.put(var2, v)
          end

        {piece, env_after} = render_nodes(body, scoped)
        {piece, Map.get(env_after, :__globals__, globals)}
      end)

    {out, env |> Map.merge(globals) |> Map.put(:__globals__, globals)}
  end

  defp render_node({:if, branches, else_body}, env) do
    chosen =
      Enum.find_value(branches, else_body, fn {c, body} ->
        if truthy?(eval(c, env, :lax)), do: body
      end)

    # `set` inside an if-branch stays in the enclosing scope (Tera has no if-scope).
    render_nodes(chosen, env)
  end

  defp eval({:lit, v}, _env, _m), do: v

  defp eval({:var, name}, env, mode) do
    case Map.fetch(env, name) do
      {:ok, v} ->
        v

      :error when mode == :strict ->
        raise ArgumentError, "tera: variable #{inspect(name)} is not defined"

      :error ->
        nil
    end
  end

  defp eval({:get, base, key}, env, mode) do
    b = eval(base, env, if(mode == :strict, do: :strict, else: :lax))
    k = eval(key, env, :lax)
    get(b, k)
  end

  defp eval({:call, name, args}, env, _mode) do
    {params, body} =
      case Map.fetch(Map.get(env, :__macros__, %{}), name) do
        {:ok, definition} -> definition
        :error -> raise ArgumentError, "tera: unknown macro #{inspect(name)}"
      end

    argv = Map.new(args, fn {k, e} -> {k, eval(e, env, :lax)} end)

    case Map.keys(argv) -- params do
      [] ->
        :ok

      extra ->
        raise ArgumentError, "tera: macro #{name} got unexpected arguments #{inspect(extra)}"
    end

    menv =
      Enum.reduce(params, %{__macros__: Map.get(env, :__macros__, %{}), __globals__: %{}}, fn p,
                                                                                              acc ->
        Map.put(acc, p, Map.get(argv, p))
      end)

    {out, _} = render_nodes(body, menv)
    IO.iodata_to_binary(out)
  end

  defp eval({:bin, "~", a, b}, env, _) do
    strict_str(eval(a, env, :lax)) <> strict_str(eval(b, env, :lax))
  end

  defp eval({:bin, op, a, b}, env, _) do
    x = arith_num(eval(a, env, :lax), op)
    y = arith_num(eval(b, env, :lax), op)

    case op do
      "+" -> x + y
      "-" -> x - y
      "*" -> x * y
      "/" -> x / y
      "%" when is_integer(x) and is_integer(y) -> rem(x, y)
      "%" -> :math.fmod(x, y)
    end
  end

  defp eval({:test, name, negate, subject, args}, env, _) do
    v = eval(subject, env, :lax)
    argv = Enum.map(args, &eval(&1, env, :lax))
    r = run_test(name, v, argv)
    if negate, do: not r, else: r
  end

  defp eval({:not, e}, env, _), do: not truthy?(eval(e, env, :lax))
  defp eval({:and, a, b}, env, _), do: truthy?(eval(a, env, :lax)) and truthy?(eval(b, env, :lax))
  defp eval({:or, a, b}, env, _), do: truthy?(eval(a, env, :lax)) or truthy?(eval(b, env, :lax))

  defp eval({:cmp, op, a, b}, env, _), do: compare(op, eval(a, env, :lax), eval(b, env, :lax))

  defp eval({:filter, name, base, args}, env, _mode) do
    v = eval(base, env, :lax)
    argv = Map.new(args, fn {k, e} -> {k, eval(e, env, :lax)} end)
    apply_filter(name, v, argv)
  end

  defp strict_str(nil), do: raise(ArgumentError, "tera: `~` applied to undefined value")
  defp strict_str(v) when is_binary(v), do: v
  defp strict_str(v) when is_number(v) or is_boolean(v), do: to_string(v)
  defp strict_str(v), do: raise(ArgumentError, "tera: cannot concatenate #{inspect(v)}")

  defp arith_num(v, op) do
    case num(v) do
      n when is_number(n) -> n
      _ -> raise ArgumentError, "tera: operator #{op} applied to non-number #{inspect(v)}"
    end
  end

  defp run_test("defined", v, []), do: v != nil

  defp run_test(t, nil, [_]) when t in ["starting_with", "ending_with", "containing", "matching"],
    do: false

  defp run_test("starting_with", v, [p]) when is_binary(v) and is_binary(p),
    do: String.starts_with?(v, p)

  defp run_test("ending_with", v, [p]) when is_binary(v) and is_binary(p),
    do: String.ends_with?(v, p)

  defp run_test("containing", v, [p]) when is_binary(v) and is_binary(p),
    do: String.contains?(v, p)

  defp run_test("containing", v, [p]) when is_list(v), do: Enum.any?(v, &(norm(&1) == norm(p)))

  defp run_test("matching", v, [re]) when is_binary(v) and is_binary(re),
    do: Regex.match?(Regex.compile!(re), v)

  defp run_test(name, v, args),
    do:
      raise(
        ArgumentError,
        "tera: unsupported test #{inspect(name)} on #{inspect(v)} with #{inspect(args)}"
      )

  defp get(m, k) when is_map(m) and is_binary(k), do: Map.get(m, k)
  defp get(l, i) when is_list(l) and is_integer(i), do: Enum.at(l, i)
  defp get(_, _), do: nil

  defp truthy?(v) when v in [nil, false, "", 0, []], do: false
  defp truthy?(v) when is_map(v), do: map_size(v) > 0
  defp truthy?(v) when is_float(v), do: v != 0.0
  defp truthy?(_), do: true

  defp norm(v) when is_binary(v), do: v
  defp norm(v) when is_integer(v) or is_float(v) or is_boolean(v), do: to_string(v)
  defp norm(v), do: v

  defp compare("==", a, b), do: norm(a) == norm(b)
  defp compare("!=", a, b), do: norm(a) != norm(b)

  defp compare(op, a, b) do
    case {num(a), num(b)} do
      {x, y} when is_number(x) and is_number(y) ->
        apply(Kernel, String.to_atom(op), [x, y])

      _ ->
        apply(Kernel, String.to_atom(op), [to_string(norm(a)), to_string(norm(b))])
    end
  end

  defp num(v) when is_number(v), do: v

  defp num(v) when is_binary(v) do
    case Float.parse(v) do
      {f, ""} -> if String.contains?(v, "."), do: f, else: trunc(f)
      _ -> nil
    end
  end

  defp num(_), do: nil

  defp stringify(nil, expr),
    do: raise(ArgumentError, "tera: {{ }} rendered undefined value for #{inspect(expr)}")

  defp stringify(v, _) when is_binary(v), do: v
  defp stringify(v, _) when is_integer(v) or is_float(v) or is_boolean(v), do: to_string(v)

  defp stringify(v, expr),
    do: raise(ArgumentError, "tera: cannot render #{inspect(v)} for #{inspect(expr)}")

  # -- filters -----------------------------------------------------------------

  defp apply_filter("length", v, _) when is_list(v), do: length(v)
  defp apply_filter("length", v, _) when is_binary(v), do: String.length(v)
  defp apply_filter("length", v, _) when is_map(v), do: map_size(v)
  defp apply_filter("length", nil, _), do: 0

  defp apply_filter("default", nil, %{"value" => d}), do: d
  defp apply_filter("default", v, _), do: v

  defp apply_filter("split", v, %{"pat" => pat}) when is_binary(v), do: String.split(v, pat)
  defp apply_filter("split", nil, %{"pat" => _}), do: []

  defp apply_filter("filter", v, %{"attribute" => attr, "value" => val}) when is_list(v) do
    Enum.filter(v, fn row -> is_map(row) and norm(Map.get(row, attr)) == norm(val) end)
  end

  defp apply_filter("filter", v, %{"attribute" => attr}) when is_list(v) do
    Enum.filter(v, fn row -> is_map(row) and Map.get(row, attr) != nil end)
  end

  defp apply_filter("filter", nil, _), do: []

  defp apply_filter("group_by", v, %{"attribute" => attr}) when is_list(v) do
    v
    |> Enum.filter(&(is_map(&1) and Map.get(&1, attr) != nil))
    |> Enum.group_by(&to_string(norm(Map.get(&1, attr))))
  end

  defp apply_filter("group_by", nil, _), do: %{}

  defp apply_filter("trim_start_matches", v, %{"pat" => p}) when is_binary(v) and p != "",
    do: trim_matches(v, p, :start)

  defp apply_filter("trim_end_matches", v, %{"pat" => p}) when is_binary(v) and p != "",
    do: trim_matches(v, p, :end)

  defp apply_filter("first", [h | _], _), do: h
  defp apply_filter("first", [], _), do: nil
  defp apply_filter("last", l, _) when is_list(l), do: List.last(l)
  defp apply_filter("json_encode", v, _), do: Jason.encode!(v)
  defp apply_filter("safe", v, _), do: v
  defp apply_filter("upper", v, _) when is_binary(v), do: String.upcase(v)
  defp apply_filter("lower", v, _) when is_binary(v), do: String.downcase(v)
  defp apply_filter("trim", v, _) when is_binary(v), do: String.trim(v)

  defp apply_filter("join", v, args) when is_list(v),
    do: Enum.map_join(v, Map.get(args, "sep", ""), &to_string(norm(&1)))

  defp apply_filter("replace", v, %{"from" => f, "to" => t}) when is_binary(v),
    do: String.replace(v, f, t)

  defp apply_filter(name, v, args),
    do:
      raise(
        ArgumentError,
        "tera: unsupported filter #{inspect(name)} on #{inspect(v)} with #{inspect(args)}"
      )

  defp trim_matches(v, p, :start) do
    if String.starts_with?(v, p),
      do: trim_matches(binary_part(v, byte_size(p), byte_size(v) - byte_size(p)), p, :start),
      else: v
  end

  defp trim_matches(v, p, :end) do
    if String.ends_with?(v, p),
      do: trim_matches(binary_part(v, 0, byte_size(v) - byte_size(p)), p, :end),
      else: v
  end
end
