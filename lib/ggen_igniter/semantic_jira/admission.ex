defmodule GgenIgniter.SemanticJira.Admission do
  @moduledoc """
  Full-shape SHACL admission of candidate WorkOrders.

  `SemanticJira.admit_work_order/1` is the kernel court: it checks the
  representation of one map. This module is the second, independent court: it
  projects candidate WorkOrder maps into the ontology graph the pack's own
  shape file describes and runs the FULL shipped shape
  (`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`) over it through
  `GgenIgniter.SemanticJira.Shacl`. The shape file is not subsetted: every
  constraint in it is evaluated, and one the validator cannot evaluate refuses
  (see below). Cardinality, datatype, pattern, `sh:class`, and every
  `sh:sparql` constraint (identifier and replay-identity uniqueness, ALIVE
  receipt integrity, authority/lease/worker binding, dependency resolution)
  bite on the projected graph exactly as they do over the canonical ontology.

  One constraint is vacuous on this path: `sh:closed`. The projection emits
  only predicates the shape declares, so a map key outside the projection
  table (and outside the kernel's own vocabulary) can never surface as an
  undeclared predicate; the kernel court also ignores unknown keys. Closedness
  is proven over the ontology graph in
  `test/ggen_igniter_semantic_jira_shacl_test.exs`, not through this module.
  UNSUPPORTED(generator-capability): carrying unknown keys as undeclared
  predicates would refuse kernel-lawful keys (`expected_consequence`,
  `dimensions`, ...) that the shape does not declare.

  `admit/2` returns `{:ok, %Shacl{conforms: true}}` or
  `{:error, {:refused_work_order, {:shacl_violations, violations}}}`. The error
  carries the same `:refused_work_order` head as the kernel's refusals, so
  `Reconciler.reconcile/4` wraps both uniformly as `{:error, {:refused, _}}`.
  Violations whose focus node belongs to the candidate (the WorkOrder node,
  its dependency-edge nodes, its receipt node) refuse it; a malformed sibling
  in the context graph does not block an unrelated candidate, but a sibling
  that collides with the candidate (duplicate identifier / replay identity)
  produces a violation on the candidate's own node and does.

  Shape-level `:unsupported_constraint` violations (the validator meets an SHACL
  term it cannot evaluate, e.g. `sh:in`) carry no focus node and are never
  scoped away: they refuse every candidate, so a shape the validator cannot
  fully evaluate fails closed instead of admitting with a constraint unchecked.

  ## Projection contract (map key -> ontology term)

  The map is projected as submitted (not the kernel-normalized copy, so kernel
  defaults such as `authority_requirement: "NONE"` cannot mask an absent field):

  | map key | term |
  |---|---|
  | `identity` `title` `description` | `dcterms:identifier` `dcterms:title` `dcterms:description` |
  | `repository` `base_sha` `subject` `standing` | `sj:repository` `sj:baseSha` `sj:subject` `sj:standing` |
  | `evidence_ceiling` `authority_ceiling` `promotion_rule` `replay_identity` `authority_requirement` | `sj:evidenceCeiling` `sj:authorityCeiling` `sj:promotionRule` `sj:replayIdentity` `sj:authorityRequirement` |
  | `candidate_sha` `subject_sha` | `sj:candidateSha` `sj:subjectSha` |
  | `requires_git_ground_truth` | `sj:requiresGitGroundTruth` (kept as given; the shape demands a boolean) |
  | `path_scope` `required_receipt_classes` | `sj:pathScope` `sj:requiresReceiptClass` |
  | `required_courts` `required_evidence` `acceptance` `falsifiers` | `sj:requiresCourt` `sj:requiresEvidence` `sj:acceptance` `sj:falsifier` -> typed `sj:Court` / `sj:EvidenceRequirement` / `sj:AcceptanceCriterion` / `sj:Falsifier` nodes |
  | `projections` | `sj:projection` -> `sj:ProjectionSpec` nodes with `sj:authorityClaim "NONE"` |
  | `next_action` `next_checkpoint` | `sj:nextAction` `sj:nextCheckpoint` -> typed `sj:Action` / `sj:Checkpoint` nodes |
  | `dependencies` | `sj:dependsOn` -> `sj:DependencyEdge` (`dependencyType`, `upstreamWorkOrder`, `requiredStanding`, `requiredReceiptDigest`) |
  | `authority` `lease` `worker` | `sj:authority` `sj:lease` `sj:worker` (`authority: "NONE"` binds nothing) |
  | `receipt` (`%{"work_order_digest", "receipt_class"}`) | a typed `sj:Receipt` node bound via `sj:receipt` |

  `next_action` and `next_checkpoint` are required by the shape but are not
  kernel-required map fields; a candidate omitting them is refused here.

  ## Context

  `admit(work_order, work_orders: siblings)` projects the candidate together
  with `siblings` so cross-order constraints have something to bite on: an
  upstream a dependency names must be present or the dependency fails to
  resolve, and a sibling carrying the same identifier/replay identity refuses
  the candidate. A sibling with the same identity and the same
  `SemanticJira.definition_digest/1` as the candidate is the candidate itself
  and is collapsed (so callers may pass the whole graph, standing included).

  ## Generator status

  UNSUPPORTED(generator-capability): the WorkOrder-map -> RDF projection in
  this module is hand-written. No admitted ggen pack or framework generator
  manufactures a kernel-map-to-ontology-graph projection (the pack's gates go
  the other way, ontology -> maps). It is the irreducible residue; the shapes
  it is checked against are the generated/shipped ontology artifacts and are
  not duplicated here.
  """

  alias GgenIgniter.Digest
  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Shacl
  alias RDF.Graph

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms "http://purl.org/dc/terms/"
  @rdfs "http://www.w3.org/2000/01/rdf-schema#"
  @urn "urn:ggen-igniter:semantic-jira:"

  @scalar_terms [
    {"identity", @dcterms <> "identifier"},
    {"title", @dcterms <> "title"},
    {"description", @dcterms <> "description"},
    {"repository", @sj <> "repository"},
    {"base_sha", @sj <> "baseSha"},
    {"subject", @sj <> "subject"},
    {"standing", @sj <> "standing"},
    {"evidence_ceiling", @sj <> "evidenceCeiling"},
    {"authority_ceiling", @sj <> "authorityCeiling"},
    {"promotion_rule", @sj <> "promotionRule"},
    {"replay_identity", @sj <> "replayIdentity"},
    {"authority_requirement", @sj <> "authorityRequirement"},
    {"candidate_sha", @sj <> "candidateSha"},
    {"subject_sha", @sj <> "subjectSha"},
    {"requires_git_ground_truth", @sj <> "requiresGitGroundTruth"}
  ]

  @literal_list_terms [
    {"path_scope", @sj <> "pathScope"},
    {"required_receipt_classes", @sj <> "requiresReceiptClass"}
  ]

  # {map key, WorkOrder predicate, typed-node class, node-IRI segment}
  @typed_node_terms [
    {"required_courts", "requiresCourt", "Court", "court"},
    {"required_evidence", "requiresEvidence", "EvidenceRequirement", "evidence"},
    {"acceptance", "acceptance", "AcceptanceCriterion", "acceptance"},
    {"falsifiers", "falsifier", "Falsifier", "falsifier"},
    {"next_action", "nextAction", "Action", "action"},
    {"next_checkpoint", "nextCheckpoint", "Checkpoint", "checkpoint"}
  ]

  @bound_terms [
    {"authority", "authority", "authority"},
    {"lease", "lease", "lease"},
    {"worker", "worker", "worker"}
  ]

  @type violation :: map()
  @type result ::
          {:ok, Shacl.t()}
          | {:error, {:refused_work_order, {:shacl_violations, [violation()]}}}

  @doc "Absolute path of the pack's shipped WorkOrder shape file, resolved from the app's priv dir."
  @spec shapes_path() :: String.t()
  def shapes_path do
    Path.join([
      :code.priv_dir(:ggen_igniter) |> to_string(),
      "ggen",
      "semantic-jira-pack",
      "shapes",
      "work-order.shacl.ttl"
    ])
  end

  @doc """
  Runs the full shipped shape over `work_order` (plus optional `:work_orders`
  context) and admits or refuses the candidate.

  Options: `:work_orders` (sibling WorkOrder maps, default `[]`) and
  `:shapes_path` (default `shapes_path/0`).
  """
  @spec admit(map(), keyword()) :: result()
  def admit(work_order, opts \\ []) when is_map(work_order) do
    candidate = normalize(work_order)
    context = opts |> Keyword.get(:work_orders, []) |> orders_only()
    orders = Enum.reject(context, &same_definition?(&1, candidate)) ++ [candidate]

    shapes = opts |> Keyword.get(:shapes_path, shapes_path()) |> Ontology.load!()
    report = Shacl.validate(to_graph(orders), shapes)

    own = candidate_nodes(candidate, orders)

    case Enum.filter(report.violations, &refuses_candidate?(&1, own)) do
      [] -> {:ok, %{report | violations: [], conforms: true}}
      violations -> {:error, {:refused_work_order, {:shacl_violations, violations}}}
    end
  end

  # A violation refuses the candidate when its focus node is one of the
  # candidate's own nodes, or when it is a shape-level fail-closed report: the
  # validator emits `:unsupported_constraint` with `focus_node: nil` for a shape
  # term it cannot evaluate, and that must never be scoped away.
  defp refuses_candidate?(%{constraint: :unsupported_constraint}, _own), do: true
  defp refuses_candidate?(%{focus_node: nil}, _own), do: true
  defp refuses_candidate?(%{focus_node: focus}, own), do: to_string(focus) in own

  @doc """
  Projects WorkOrder maps into the ontology-shaped RDF graph described in the
  module doc. Pure and total over field values: a malformed or absent value
  (a map, a list of maps, a tuple, ...) yields no triple, or a wrongly-typed
  literal, which the shape then refuses; a non-scalar identity or upstream
  becomes a stable content-hash node segment so the node is still addressable.
  List entries that are not maps are skipped.
  """
  @spec to_graph([term()]) :: Graph.t()
  def to_graph(work_orders) when is_list(work_orders) do
    orders = orders_only(work_orders)
    iris = work_order_iris(orders)
    index = first_iri_by_identity(orders, iris)

    orders
    |> Enum.zip(iris)
    |> Enum.reduce(Graph.new(), fn {order, iri}, graph ->
      Graph.add(graph, order_statements(order, iri, index))
    end)
  end

  ## Node identity

  # One IRI per list position; the k-th occurrence of a repeated identity gets
  # a `~k` suffix so duplicates stay distinct nodes and trip the uniqueness
  # constraints instead of silently merging.
  defp work_order_iris(orders) do
    {iris, _} =
      Enum.map_reduce(orders, %{}, fn order, seen ->
        id = order["identity"]
        n = Map.get(seen, id, 0)
        suffix = if n == 0, do: "", else: "~#{n + 1}"
        {RDF.iri(@urn <> "work-order:" <> enc(id) <> suffix), Map.put(seen, id, n + 1)}
      end)

    iris
  end

  defp first_iri_by_identity(orders, iris) do
    orders
    |> Enum.zip(iris)
    |> Enum.reduce(%{}, fn {order, iri}, acc -> Map.put_new(acc, order["identity"], iri) end)
  end

  defp candidate_nodes(candidate, orders) do
    iris = work_order_iris(orders)
    iri = List.last(iris)

    edges =
      candidate
      |> dependencies()
      |> Enum.with_index()
      |> Enum.map(fn {_, i} -> edge_iri(iri, i) end)

    [iri, receipt_iri(iri) | edges] |> Enum.map(&to_string/1)
  end

  defp edge_iri(order_iri, i), do: RDF.iri("#{order_iri}:edge:#{i}")
  defp receipt_iri(order_iri), do: RDF.iri("#{order_iri}:receipt")

  defp same_definition?(sibling, candidate) do
    sibling["identity"] == candidate["identity"] and
      case {SemanticJira.definition_digest(sibling), SemanticJira.definition_digest(candidate)} do
        {{:ok, a}, {:ok, b}} -> a == b
        _ -> sibling == candidate
      end
  end

  ## Statements

  defp order_statements(order, iri, index) do
    [
      {iri, RDF.type(), sj("WorkOrder")}
      | scalar_statements(order, iri) ++
          literal_list_statements(order, iri) ++
          typed_node_statements(order, iri) ++
          projection_statements(order, iri) ++
          dependency_statements(order, iri, index) ++
          bound_statements(order, iri) ++
          receipt_statements(order, iri)
    ]
  end

  defp scalar_statements(order, iri) do
    for {key, term} <- @scalar_terms,
        literal = literal(order[key]),
        do: {iri, RDF.iri(term), literal}
  end

  defp literal_list_statements(order, iri) do
    for {key, term} <- @literal_list_terms,
        value <- listify(order[key]),
        literal = literal(value),
        do: {iri, RDF.iri(term), literal}
  end

  defp typed_node_statements(order, iri) do
    for {key, predicate, class, segment} <- @typed_node_terms,
        name <- names(order[key]),
        node = RDF.iri(@urn <> segment <> ":" <> enc(name)),
        statement <- [
          {iri, sj(predicate), node},
          {node, RDF.type(), sj(class)},
          {node, RDF.iri(@rdfs <> "label"), RDF.literal(name)}
        ],
        do: statement
  end

  defp projection_statements(order, iri) do
    for name <- names(order["projections"]),
        node = RDF.iri(@urn <> "projection:" <> enc(name)),
        statement <- [
          {iri, sj("projection"), node},
          {node, RDF.type(), sj("ProjectionSpec")},
          {node, sj("projectionType"), RDF.literal(name)},
          {node, sj("authorityClaim"), RDF.literal("NONE")}
        ],
        do: statement
  end

  defp dependency_statements(order, iri, index) do
    order
    |> dependencies()
    |> Enum.with_index()
    |> Enum.flat_map(fn {dep, i} ->
      edge = edge_iri(iri, i)
      upstream = Map.get(index, dep["upstream"]) || unresolved_iri(dep["upstream"])

      [
        {iri, sj("dependsOn"), edge},
        {edge, RDF.type(), sj("DependencyEdge")},
        {edge, sj("upstreamWorkOrder"), upstream}
      ] ++
        optional(edge, "dependencyType", dep["type"]) ++
        optional(edge, "requiredStanding", dep["required_standing"]) ++
        optional(edge, "requiredReceiptDigest", dep["required_receipt_digest"])
    end)
  end

  defp bound_statements(order, iri) do
    for {key, predicate, segment} <- @bound_terms,
        name = order[key],
        is_binary(name) and name != "" and name != "NONE",
        do: {iri, sj(predicate), RDF.iri(@urn <> segment <> ":" <> enc(name))}
  end

  defp receipt_statements(%{"receipt" => %{} = receipt} = order, iri) do
    node = receipt_iri(iri)

    [
      {iri, sj("receipt"), node},
      {node, RDF.type(), sj("Receipt")}
      | optional(node, "workOrderDigest", receipt["work_order_digest"]) ++
          optional(node, "receiptClass", receipt["receipt_class"]) ++
          optional(node, "repository", order["repository"]) ++
          optional(node, "baseSha", order["base_sha"]) ++
          optional(node, "subjectSha", order["subject_sha"]) ++
          optional(node, "replayIdentity", order["replay_identity"])
    ]
  end

  defp receipt_statements(_, _), do: []

  defp optional(node, term, value) do
    case literal(value) do
      nil -> []
      literal -> [{node, sj(term), literal}]
    end
  end

  ## Value coercion

  defp literal(nil), do: nil
  defp literal(v) when is_binary(v) or is_boolean(v) or is_number(v), do: RDF.literal(v)
  defp literal(_), do: nil

  defp listify(nil), do: []
  defp listify(list) when is_list(list), do: list
  defp listify(value), do: [value]

  defp names(value), do: value |> listify() |> Enum.filter(&(is_binary(&1) and &1 != ""))

  defp dependencies(order),
    do: order["dependencies"] |> listify() |> Enum.filter(&is_map/1) |> Enum.map(&stringify/1)

  defp unresolved_iri(nil), do: RDF.iri(@urn <> "work-order:unresolved")
  defp unresolved_iri(id), do: RDF.iri(@urn <> "work-order:" <> enc(id))

  defp sj(term), do: RDF.iri(@sj <> term)

  # Total over every term: scalars are percent-encoded; anything else (map,
  # list, tuple, pid, ...) has no faithful string form, so it becomes a stable
  # content-hash segment. Distinct non-scalars stay distinct nodes; nothing
  # here can raise, which is what keeps `to_graph/1` and `admit/2` typed.
  defp enc(value) when is_binary(value), do: URI.encode(value, &URI.char_unreserved?/1)
  defp enc(value) when is_atom(value) or is_number(value), do: enc(to_string(value))

  defp enc(value) do
    String.replace_prefix(Digest.sha256(:erlang.term_to_binary(value)), "sha256:", "x-")
  end

  # Keep only real maps (a struct or non-map context entry cannot be projected),
  # stringified; a struct candidate is flattened to its fields.
  defp orders_only(list) when is_list(list) do
    for entry <- list, is_map(entry), do: normalize(entry)
  end

  defp orders_only(_), do: []

  defp normalize(%_{} = struct), do: struct |> Map.from_struct() |> stringify()
  defp normalize(map) when is_map(map), do: stringify(map)

  defp stringify(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {key_string(k), stringify(x)} end)

  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v

  defp key_string(k) when is_binary(k), do: k
  defp key_string(k) when is_atom(k) or is_number(k), do: to_string(k)
  defp key_string(k), do: inspect(k)
end
