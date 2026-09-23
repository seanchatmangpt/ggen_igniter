defmodule GgenIgniter.SemanticJira.Shacl do
  @moduledoc """
  SHACL admission court for semantic-jira-pack: a real, executing SHACL-core
  validator over the pack's own shape file
  (`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`), built directly
  on the RDF/SPARQL libraries this repo already admits (`rdf ~> 3.0`,
  `sparql ~> 0.3`). No hex SHACL package exists (hex.pm `shacl` returns 404,
  verified 2026-09-19), so the court compiles the shipped shapes into checks
  itself instead of renaming SPARQL/template checks as SHACL.

  Supported SHACL-core surface:

    * targeting: `sh:targetClass`, `sh:targetNode`, `sh:targetSubjectsOf`,
      `sh:targetObjectsOf` (`sh:targetClass` follows `rdfs:subClassOf*`)
    * property constraints: `sh:minCount`, `sh:maxCount`, `sh:nodeKind`,
      `sh:datatype`, `sh:pattern` (flag `i`), `sh:minLength`,
      `sh:maxLength`, `sh:hasValue`, `sh:class`
    * node-level: `sh:closed` with `sh:ignoredProperties`, `sh:property`,
      `sh:deactivated`
    * SPARQL-based constraints: `sh:sparql` with `sh:select`/`sh:message`.

  `$this` is bound by injecting `BIND(<focus> AS ?this)` at the head of the
  WHERE group and renaming `$this` to `?this` -- `sparql` 0.3.12 offers no
  pre-binding API and silently ignores both inline and trailing `VALUES`
  (measured this session: a `VALUES`-filtered query returned unfiltered rows),
  while `BIND` filters correctly. A row returned by a constraint's SELECT is
  one violation for that focus node, per the SPARQL-constraint component spec;
  a row that binds `?path` to an IRI reports that IRI as the violation's
  `path` (the spec's `sh:resultPath` mapping), which is how the Friday tuple
  constraints (`sj:FridayWorkOrderShape`) name the refused field.

  UNSUPPORTED (never silently skipped -- encountering any of these is itself a
  violation, so an unknown construct fails closed instead of passing):

    * `sh:qualifiedValueShape`/`sh:qualifiedMinCount`/`sh:qualifiedMaxCount`
    * `sh:node`, `sh:not`, `sh:and`, `sh:or`, `sh:xone`
    * `sh:in`, `sh:languageIn`, `sh:uniqueLang`, non-`i` `sh:flags`
    * non-simple property paths (sequence/alternative/inverse paths)
    * `sh:severity`, `sh:name`, `sh:description`, `sh:order`, `sh:group` are
      tolerated as annotations but not evaluated.

  Results mirror `GgenIgniter.GateVerify`: `run/2` returns
  `{:ok, [{shape_name, :pass}]}` when the data graph conforms and
  `{:error, {:shacl_violations, violations}}` naming each violated shape,
  focus node, and constraint path when it does not. `validate/2` returns the
  full conformance report for callers that need per-shape detail.
  """

  alias GgenIgniter.Ontology

  @sh "http://www.w3.org/ns/shacl#"
  @rdf "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  @rdf_type RDF.type()
  @rdfs_sub_class_of RDF.iri("http://www.w3.org/2000/01/rdf-schema#subClassOf")

  # SHACL's own always-ignored properties: rdf:type, rdf:first, rdf:rest.
  @spec_always_ignored [@rdf_type, RDF.iri(@rdf <> "first"), RDF.iri(@rdf <> "rest")]

  @annotation_terms ~w(message name description severity order group)

  @property_constraints ~w(minCount maxCount nodeKind datatype pattern flags minLength maxLength hasValue class)
  @property_allowed @property_constraints ++ ~w(path) ++ @annotation_terms

  @node_allowed ~w(targetClass targetNode targetSubjectsOf targetObjectsOf property closed ignoredProperties sparql deactivated) ++
                  @annotation_terms

  @node_kinds %{
    "IRI" => RDF.IRI,
    "Literal" => RDF.Literal,
    "BlankNode" => RDF.BlankNode
  }

  @enforce_keys [:conforms, :shapes_checked, :focus_node_count, :violations]
  defstruct conforms: true, shapes_checked: [], focus_node_count: 0, violations: []

  @type shape_name :: String.t()

  @type t :: %__MODULE__{
          conforms: boolean(),
          shapes_checked: [shape_name()],
          focus_node_count: non_neg_integer(),
          violations: [map()]
        }

  @doc "Path of the pack's own SHACL shape file, relative to the repo root."
  @spec pack_shapes_path() :: String.t()
  def pack_shapes_path, do: "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"

  @doc """
  Gate-shaped entry: validates the ontology at `ontology_path` against
  `<pack_dir>/shapes/work-order.shacl.ttl` and reports per-shape results in
  the same `{:ok, [{name, :pass}]}` shape `GgenIgniter.GateVerify` uses for
  `gates/*.rq`.
  """
  @spec run(String.t(), String.t()) ::
          {:ok, [{shape_name(), :pass}]} | {:error, {:shacl_violations, [map()]}}
  def run(pack_dir, ontology_path) when is_binary(pack_dir) and is_binary(ontology_path) do
    report = validate_file(ontology_path, Path.join(pack_dir, "shapes/work-order.shacl.ttl"))

    if report.conforms do
      {:ok, Enum.map(report.shapes_checked, &{&1, :pass})}
    else
      {:error, {:shacl_violations, report.violations}}
    end
  end

  @doc "Validates a data graph (or ontology file path) against the pack's own shapes."
  @spec validate_file(RDF.Graph.t() | String.t(), String.t()) :: t()
  def validate_file(data, shapes_path \\ pack_shapes_path())

  def validate_file(%RDF.Graph{} = data, shapes_path) when is_binary(shapes_path),
    do: validate(data, Ontology.load!(shapes_path))

  def validate_file(data_path, shapes_path) when is_binary(data_path) and is_binary(shapes_path),
    do: validate_file(Ontology.load!(data_path), shapes_path)

  @doc "Validates `data` against `shapes` and returns the full conformance report."
  @spec validate(RDF.Graph.t(), RDF.Graph.t()) :: t()
  def validate(%RDF.Graph{} = data, %RDF.Graph{} = shapes) do
    node_shapes = node_shapes(shapes)

    {shape_violations, focus_node_count} =
      Enum.map_reduce(node_shapes, 0, fn {subject, description}, count ->
        {violations, focus_count} = validate_node_shape(subject, description, data, shapes)
        {violations, count + focus_count}
      end)

    violations = List.flatten(shape_violations)

    %__MODULE__{
      conforms: violations == [],
      shapes_checked: Enum.map(node_shapes, fn {subject, _} -> shape_name(subject) end),
      focus_node_count: focus_node_count,
      violations: violations
    }
  end

  ## Node-shape discovery and targeting

  defp node_shapes(shapes) do
    shapes
    |> RDF.Graph.subjects()
    |> Enum.filter(&node_shape?(shapes, &1))
    |> Enum.map(&{&1, RDF.Graph.get(shapes, &1)})
  end

  defp node_shape?(shapes, subject) do
    case RDF.Graph.get(shapes, subject) do
      nil -> false
      description -> sh("NodeShape") in RDF.Description.get(description, @rdf_type, [])
    end
  end

  defp validate_node_shape(subject, description, data, shapes) do
    if deactivated?(description) do
      {[], 0}
    else
      focus_nodes = targets(description, data)

      violations =
        List.flatten([
          unsupported_terms(subject, description, @node_allowed),
          Enum.flat_map(property_shapes(description, shapes), fn property_shape ->
            property_shape_violations(subject, property_shape, focus_nodes, data, shapes)
          end),
          Enum.flat_map(focus_nodes, &closed_violations(subject, &1, description, data, shapes)),
          Enum.flat_map(focus_nodes, &sparql_violations(subject, &1, description, shapes, data))
        ])

      {violations, length(focus_nodes)}
    end
  end

  defp deactivated?(description) do
    case RDF.Description.first(description, sh("deactivated")) do
      nil -> false
      value -> RDF.Term.equal?(value, RDF.literal(true))
    end
  end

  defp property_shapes(description, shapes) do
    description
    |> RDF.Description.get(sh("property"), [])
    |> Enum.map(&RDF.Graph.get(shapes, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp targets(description, data) do
    class_targets =
      description
      |> RDF.Description.get(sh("targetClass"), [])
      |> Enum.flat_map(&instances_of(data, &1))

    node_targets = RDF.Description.get(description, sh("targetNode"), [])

    subject_targets =
      description
      |> RDF.Description.get(sh("targetSubjectsOf"), [])
      |> Enum.flat_map(fn predicate ->
        # RDF.Description.include?/3 (rdf 3.0.1) takes a statement, not a
        # bare predicate: it raised FunctionClauseError the first time a shipped
        # shape used sh:targetSubjectsOf (sj:FridayWorkOrderShape, v26.9.22).
        data
        |> RDF.Graph.descriptions()
        |> Enum.filter(&(RDF.Description.first(&1, predicate) != nil))
        |> Enum.map(& &1.subject)
      end)

    object_targets =
      description
      |> RDF.Description.get(sh("targetObjectsOf"), [])
      |> Enum.flat_map(fn predicate ->
        data
        |> RDF.Graph.descriptions()
        |> Enum.flat_map(&RDF.Description.get(&1, predicate, []))
      end)

    (class_targets ++ node_targets ++ subject_targets ++ object_targets)
    |> Enum.uniq()
  end

  # SHACL instances of `class`: every node typed `class` or one of its
  # transitive rdfs:subClassOf subclasses in the data graph.
  defp instances_of(data, class) do
    data
    |> RDF.Graph.descriptions()
    |> Enum.filter(fn description ->
      RDF.Description.get(description, @rdf_type, [])
      |> Enum.any?(&(&1 == class or &1 in subclass_closure(data, class)))
    end)
    |> Enum.map(& &1.subject)
  end

  defp subclass_closure(data, class) do
    data
    |> RDF.Graph.descriptions()
    |> Enum.flat_map(fn description ->
      if class in RDF.Description.get(description, @rdfs_sub_class_of, []) do
        [description.subject | subclass_closure(data, description.subject)]
      else
        []
      end
    end)
  end

  ## Property-shape constraint evaluation

  defp property_shape_violations(shape_subject, property_shape, focus_nodes, data, _shapes) do
    path = RDF.Description.first(property_shape, sh("path"))

    if match?(%RDF.IRI{}, path) do
      Enum.flat_map(focus_nodes, fn focus ->
        constraint_violations(shape_subject, property_shape, path, focus, data)
      end)
      |> Kernel.++(unsupported_terms(shape_subject, property_shape, @property_allowed))
    else
      Enum.map(focus_nodes, fn focus ->
        violation(shape_subject, focus, nil, :unsupported_constraint,
          message: "property shape uses a non-simple sh:path; only IRI paths are supported",
          value: term_string(path)
        )
      end)
    end
  end

  defp constraint_violations(shape_subject, property_shape, path, focus, data) do
    values = value_nodes(data, focus, path)

    checks = [
      count_check(property_shape, sh("minCount"), :min_count, values, &>/2),
      count_check(property_shape, sh("maxCount"), :max_count, values, &</2),
      has_value_check(property_shape, values),
      node_kind_check(property_shape, values),
      datatype_check(property_shape, values),
      pattern_check(property_shape, values),
      length_check(property_shape, sh("minLength"), :min_length, values),
      length_check(property_shape, sh("maxLength"), :max_length, values),
      class_check(property_shape, values, data)
    ]

    Enum.map(List.flatten(checks), fn {constraint, message, value} ->
      violation(shape_subject, focus, path, constraint, message: message, value: value)
    end)
  end

  defp value_nodes(data, focus, path) do
    case RDF.Graph.get(data, focus) do
      nil -> []
      description -> RDF.Description.get(description, path, [])
    end
  end

  defp count_check(property_shape, term, constraint, values, violated?) do
    case integer_param(property_shape, term) do
      nil ->
        []

      limit ->
        if violated?.(limit, length(values)) do
          [{constraint, "#{local(term)} #{limit} violated (#{length(values)} values)", nil}]
        else
          []
        end
    end
  end

  defp has_value_check(property_shape, values) do
    case RDF.Description.first(property_shape, sh("hasValue")) do
      nil ->
        []

      expected ->
        if Enum.any?(values, &RDF.Term.equal?(&1, expected)) do
          []
        else
          [{:has_value, "sh:hasValue #{term_string(expected)} is required", nil}]
        end
    end
  end

  defp node_kind_check(property_shape, values) do
    case RDF.Description.first(property_shape, sh("nodeKind")) do
      nil ->
        []

      %RDF.IRI{} = kind ->
        node_kind_values(local(kind), values)

      _other ->
        [{:unsupported_constraint, "sh:nodeKind must be an IRI", nil}]
    end
  end

  defp node_kind_values(local_name, values) do
    cond do
      local_name == "IRIOrLiteral" ->
        Enum.flat_map(values, &iri_or_literal_violation/1)

      Map.has_key?(@node_kinds, local_name) ->
        kind = Map.fetch!(@node_kinds, local_name)

        Enum.flat_map(values, &node_kind_violation(&1, local_name, kind))

      true ->
        [{:unsupported_constraint, "unsupported sh:nodeKind #{local_name}", nil}]
    end
  end

  defp iri_or_literal_violation(value) do
    if match?(%RDF.IRI{}, value) or match?(%RDF.Literal{}, value),
      do: [],
      else: [{:node_kind, "value is not sh:IRIOrLiteral", term_string(value)}]
  end

  defp node_kind_violation(value, local_name, kind) do
    if is_struct(value, kind),
      do: [],
      else: [{:node_kind, "value is not sh:#{local_name}", term_string(value)}]
  end

  defp datatype_check(property_shape, values) do
    case RDF.Description.first(property_shape, sh("datatype")) do
      nil ->
        []

      %RDF.IRI{} = datatype ->
        Enum.flat_map(values, &datatype_violation(&1, RDF.IRI.to_string(datatype)))

      _other ->
        [{:unsupported_constraint, "sh:datatype must be an IRI", nil}]
    end
  end

  defp datatype_violation(value, datatype_id) do
    case literal_datatype(value) |> datatype_iri_string() do
      ^datatype_id ->
        []

      nil ->
        [{:datatype, "value is not a literal of #{datatype_id}", term_string(value)}]

      actual ->
        [{:datatype, "datatype #{actual} is not #{datatype_id}", term_string(value)}]
    end
  end

  defp literal_datatype(%RDF.Literal{} = literal), do: RDF.Literal.datatype_id(literal)
  defp literal_datatype(_), do: nil

  # rdf 3.0.1's RDF.Literal.datatype_id/1 returns an %RDF.IRI{}; normalize so
  # datatype comparisons are string-on-string.
  defp datatype_iri_string(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp datatype_iri_string(id) when is_binary(id), do: id
  defp datatype_iri_string(nil), do: nil

  defp pattern_check(property_shape, values) do
    case RDF.Description.first(property_shape, sh("pattern")) do
      nil ->
        []

      %RDF.Literal{} = pattern_literal ->
        pattern_values(property_shape, values, RDF.Literal.value(pattern_literal))

      _other ->
        [{:unsupported_constraint, "sh:pattern must be a string literal", nil}]
    end
  end

  defp pattern_values(property_shape, values, pattern) do
    with :ok <- flags_supported?(property_shape),
         {:ok, regex} <- compile_pattern(pattern, flags(property_shape)) do
      Enum.flat_map(values, &pattern_violation(&1, regex, pattern))
    else
      {:error, message} -> [{:unsupported_constraint, message, nil}]
    end
  end

  defp pattern_violation(value, regex, pattern) do
    if match?(%RDF.Literal{}, value) and Regex.match?(regex, lexical_form(value)),
      do: [],
      else: [{:pattern, "value does not match pattern #{inspect(pattern)}", term_string(value)}]
  end

  defp flags(property_shape) do
    case RDF.Description.first(property_shape, sh("flags")) do
      nil -> ""
      literal -> RDF.Literal.value(literal) || ""
    end
  end

  defp flags_supported?(property_shape) do
    if flags(property_shape) in ["", "i"],
      do: :ok,
      else: {:error, "unsupported sh:flags #{inspect(flags(property_shape))}"}
  end

  defp compile_pattern(pattern, "i"), do: Regex.compile(pattern, "i")
  defp compile_pattern(pattern, ""), do: Regex.compile(pattern)

  defp length_check(property_shape, term, constraint, values) do
    case integer_param(property_shape, term) do
      nil ->
        []

      limit ->
        Enum.flat_map(values, fn value ->
          length_violation(constraint, local(term), limit, value)
        end)
    end
  end

  defp length_violation(constraint, term_name, limit, value) do
    if match?(%RDF.Literal{}, value) do
      length = String.length(lexical_form(value))

      violated? =
        case constraint do
          :min_length -> length < limit
          :max_length -> length > limit
        end

      if violated? do
        [{constraint, "#{term_name} #{limit} violated (length #{length})", lexical_form(value)}]
      else
        []
      end
    else
      [{constraint, "value is not a literal; #{term_name} not applicable", term_string(value)}]
    end
  end

  defp class_check(property_shape, values, data) do
    case RDF.Description.first(property_shape, sh("class")) do
      nil ->
        []

      class ->
        Enum.flat_map(values, &class_violation(data, &1, class))
    end
  end

  defp class_violation(data, value, class) do
    if shacl_instance_of?(data, value, class),
      do: [],
      else: [{:class, "value is not an instance of #{term_string(class)}", term_string(value)}]
  end

  defp shacl_instance_of?(data, value, class) do
    value == class or value in subclass_closure(data, class) or
      (resource?(value) and
         case RDF.Graph.get(data, value) do
           nil -> false
           description -> typed_as?(description, class, data)
         end)
  end

  defp resource?(%RDF.IRI{}), do: true
  defp resource?(%RDF.BlankNode{}), do: true
  defp resource?(_), do: false

  defp typed_as?(description, class, data) do
    RDF.Description.get(description, @rdf_type, [])
    |> Enum.any?(&(&1 == class or &1 in subclass_closure(data, class)))
  end

  ## Node-shape-level constraints: closed and sparql

  defp closed_violations(shape_subject, focus, description, data, shapes) do
    case RDF.Description.first(description, sh("closed")) do
      nil ->
        []

      closed ->
        if RDF.Term.equal?(closed, RDF.literal(true)) do
          closed_predicate_violations(
            shape_subject,
            focus,
            allowed_predicates(description, data, shapes),
            data
          )
          |> Kernel.++(unsupported_terms(shape_subject, description, @node_allowed))
        else
          []
        end
    end
  end

  defp allowed_predicates(description, _data, shapes) do
    declared =
      property_shapes(description, shapes)
      |> Enum.map(&RDF.Description.first(&1, sh("path")))
      |> Enum.reject(&is_nil/1)

    description
    |> RDF.Description.get(sh("ignoredProperties"), [])
    |> ignored_property_values(shapes)
    |> Kernel.++(declared)
    |> Kernel.++(@spec_always_ignored)
    |> MapSet.new()
  end

  defp closed_predicate_violations(shape_subject, focus, allowed, data) do
    case RDF.Graph.get(data, focus) do
      nil ->
        []

      focus_description ->
        focus_description
        |> RDF.Description.predicates()
        |> MapSet.new()
        |> MapSet.difference(allowed)
        |> Enum.map(fn predicate ->
          violation(shape_subject, focus, predicate, :closed,
            message: "predicate is not allowed by the closed shape",
            value: nil
          )
        end)
    end
  end

  defp ignored_property_values([], _shapes), do: []

  defp ignored_property_values([list_head | _], shapes) do
    case RDF.List.new(list_head, shapes) do
      nil -> []
      list -> RDF.List.values(list)
    end
  end

  defp sparql_violations(shape_subject, focus, description, shapes, data) do
    description
    |> RDF.Description.get(sh("sparql"), [])
    |> Enum.flat_map(fn constraint ->
      case RDF.Graph.get(shapes, constraint) do
        nil ->
          []

        constraint_description ->
          sparql_constraint_violations(shape_subject, focus, constraint_description, data)
      end
    end)
  end

  defp sparql_constraint_violations(shape_subject, focus, constraint, data) do
    query = RDF.Description.first(constraint, sh("select"))
    message = message_for(constraint, "SPARQL constraint violated")

    cond do
      is_nil(query) ->
        [
          violation(shape_subject, focus, nil, :unsupported_constraint,
            message: "sh:sparql constraint has no sh:select",
            value: nil
          )
        ]

      match?(%RDF.BlankNode{}, focus) ->
        [
          violation(shape_subject, focus, nil, :unsupported_constraint,
            message: "$this cannot be bound for a blank-node focus node",
            value: nil
          )
        ]

      true ->
        rows = execute_focus_query(data, RDF.Literal.value(query), focus)

        Enum.map(rows, fn row ->
          violation(shape_subject, focus, result_path(row), :sparql, message: message, value: nil)
        end)
    end
  end

  # SHACL-SPARQL result path: a solution binding ?path to an IRI names the
  # violated property (sh:resultPath); any other binding, or none, is no path.
  defp result_path(%{"path" => %RDF.IRI{} = path}), do: path
  defp result_path(_row), do: nil

  # Binds $this by renaming it to ?this and injecting BIND(<focus> AS ?this)
  # at the head of the WHERE group. sparql 0.3.12 has no pre-binding API and
  # silently ignores VALUES clauses (measured), while BIND filters correctly.
  defp execute_focus_query(data, query, %RDF.IRI{} = focus) do
    renamed = String.replace(query, "$this", "?this")

    bound =
      Regex.replace(
        ~r/WHERE\s*\{/i,
        renamed,
        "WHERE { BIND(<#{RDF.IRI.to_string(focus)}> AS ?this) ",
        global: false
      )

    if bound == query do
      raise ArgumentError,
            "sh:sparql constraint query has no WHERE { ... } group to bind $this into: " <>
              inspect(query)
    end

    case SPARQL.execute_query(data, bound) do
      %SPARQL.Query.Result{results: rows} ->
        rows

      {:error, reason} ->
        raise ArgumentError, "sh:sparql constraint failed to execute: #{inspect(reason)}"
    end
  end

  ## Fail-closed unknown-term census

  defp unsupported_terms(shape_subject, description, allowed) do
    allowed_set = MapSet.new(allowed, &sh/1)

    description
    |> RDF.Description.predicates()
    |> Enum.filter(fn predicate ->
      match?(%RDF.IRI{}, predicate) and
        String.starts_with?(RDF.IRI.to_string(predicate), @sh) and
        predicate not in allowed_set
    end)
    |> Enum.map(fn predicate ->
      violation(shape_subject, nil, nil, :unsupported_constraint,
        message: "unsupported SHACL term #{RDF.IRI.to_string(predicate)}; failing closed",
        value: nil
      )
    end)
  end

  ## Term helpers

  defp integer_param(description, term) do
    case RDF.Description.first(description, term) do
      %RDF.Literal{} = literal -> integer_value(literal)
      _ -> nil
    end
  end

  defp integer_value(literal) do
    value = RDF.Literal.value(literal)

    if is_integer(value), do: value, else: nil
  end

  defp lexical_form(literal) do
    RDF.Literal.lexical(literal) ||
      literal |> RDF.Literal.canonical() |> RDF.Literal.lexical() ||
      RDF.Literal.value(literal) |> to_string()
  end

  defp message_for(description, default) do
    case RDF.Description.first(description, sh("message")) do
      nil -> default
      literal -> RDF.Literal.value(literal)
    end
  end

  defp violation(shape_subject, focus, path, constraint, opts) do
    %{
      shape: shape_name(shape_subject),
      focus_node: term_string(focus),
      path: term_string(path),
      constraint: constraint,
      message: Keyword.get(opts, :message),
      value: Keyword.get(opts, :value)
    }
  end

  defp term_string(nil), do: nil

  defp term_string(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp term_string(%RDF.BlankNode{} = node), do: to_string(node)
  defp term_string(%RDF.Literal{} = literal), do: lexical_form(literal)
  defp term_string(other), do: inspect(other)

  defp shape_name(%RDF.IRI{} = subject) do
    subject
    |> RDF.IRI.to_string()
    |> String.split(["#", "/"])
    |> List.last()
    |> Macro.underscore()
  end

  defp shape_name(subject), do: to_string(subject)

  defp sh(term), do: RDF.iri(@sh <> term)

  defp local(%RDF.IRI{} = iri) do
    iri |> RDF.IRI.to_string() |> String.split(["#", "/"]) |> List.last()
  end

  defp local(term) when is_atom(term), do: Atom.to_string(term)
end
