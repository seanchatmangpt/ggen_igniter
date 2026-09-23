defmodule GgenIgniter.SemanticJira.KernelDifferential do
  @moduledoc """
  One-kernel probe (work order GGEN_IGNITER-26922-19, DfCM composition C14):
  differential admission of a Semantic Jira work graph through two
  independent SHACL kernels fed byte-identical inputs.

  The probe is kernel-agnostic. A kernel is `{name, fun}` where `fun` takes
  `%{data_ttl, shapes_ttl, data_graph, shapes_graph}` -- the graphs are parsed
  once by the orchestrator from exactly the same bytes as the `*_ttl` strings
  -- and returns a `t:verdict/0`. `shacl_kernel/0` is this repository's own
  court (`GgenIgniter.SemanticJira.Shacl`); the second kernel (the vendored
  `praxis_graphlaw.wasm`, executed in-BEAM through
  `AshA2A.GraphLaw.WasmexHost`) is bound by the caller, because `ash_a2a` is
  a dev/test-only dependency of this repository and no `lib/` module may
  reference it.

  ## What is compared

    * the whole work graph against the pack shapes;
    * every work order, with the shapes' targets restricted (`sh:targetClass`
      replaced by `sh:targetNode`) to that order's own closure -- the order
      node plus the nodes it owns through `owned_predicates/0` -- while the
      data graph stays whole, so uniqueness and dependency-resolution
      constraints still see every order;
    * a fixed mutation set (`mutation_ids/0`), each operator built to break
      exactly one documented admission rule, plus an identity mutation that
      must change nothing; each mutation is also run unmutated under the same
      focused shapes, so per-kernel `DETECTED`/`NOT_DETECTED` separates a
      refusal caused by the mutation from one the base already had;
    * `calibration_cases/0`: minimal single-construct cases with their
      SHACL-spec verdict, run through both kernels (`calibrate/1`).

  ## Typed diffs

  Every case is classified by `classify/1`. A disagreement is never a bare
  mismatch: `localize/7` re-runs both kernels on single-constraint slices of
  the shapes (`slices/1`, organised by `slice_tree/1` into node shape ->
  component group -> leaf) and names each leaf on which the kernels differ.
  A disagreement that no single leaf reproduces is typed
  `NON_COMPOSITIONAL`, never left untyped. Each localized leaf is then
  attributed to the calibration cases of its constraint component on which a
  kernel is off-spec (`CALIBRATED`), or typed `UNCALIBRATED`. `probe/1` runs
  the whole thing and `encode/1` renders the report with sorted keys.

  Hand-written residue: `orders.json` -> `sj:WorkOrder` projection
  (`work_graph/3`) has no generator in semantic-jira-pack (the pack renders
  TTL -> projections, not JSON -> TTL); UNSUPPORTED(generator-capability).

  Nothing here admits, authorizes or actuates. Both kernels produce
  observations; the report is evidence for a court, not a court.
  """

  alias GgenIgniter.SemanticJira.Shacl

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @sh "http://www.w3.org/ns/shacl#"
  @rdf "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  @rdfs "http://www.w3.org/2000/01/rdf-schema#"
  @dcterms "http://purl.org/dc/terms/"

  @release "v26.9.22"

  @prefixes [
    a2a: "https://ggen-igniter.dev/ontology/a2a#",
    dcterms: "http://purl.org/dc/terms/",
    gi: "https://ggen-igniter.dev/ontology/ggen-igniter#",
    rdf: "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    rdfs: "http://www.w3.org/2000/01/rdf-schema#",
    sh: "http://www.w3.org/ns/shacl#",
    sj: "https://ggen-igniter.dev/ontology/semantic-jira#",
    xsd: "http://www.w3.org/2001/XMLSchema#"
  ]

  @owned ~w(dependsOn requiresCourt acceptance falsifier nextAction nextCheckpoint receipt)
  @target_terms ~w(targetClass targetNode targetSubjectsOf targetObjectsOf)
  @property_skip ~w(path flags message name description severity order group)

  @promotion_rule "Standing may advance only from an independent exact-head court receipt " <>
                    "binding candidateSha, subjectSha and a durable receipt for this subject; " <>
                    "a passing test log alone, a generated ticket, or an upstream standing is " <>
                    "not promotion."

  @typedoc "One kernel's observation of one (data, shapes) pair."
  @type verdict :: %{
          status: :conforms | :refused | :error,
          violations: non_neg_integer() | nil,
          detail: String.t()
        }

  @typedoc "The byte-identical input handed to every kernel."
  @type input :: %{
          data_ttl: String.t(),
          shapes_ttl: String.t(),
          data_graph: RDF.Graph.t(),
          shapes_graph: RDF.Graph.t()
        }

  @type kernel :: {String.t(), (input() -> verdict())}

  ## Kernels

  @doc "This repository's SHACL court as a differential kernel."
  @spec shacl_kernel() :: kernel()
  def shacl_kernel do
    {"ggen_igniter.semantic_jira.shacl",
     fn %{data_graph: data, shapes_graph: shapes} ->
       try do
         report = Shacl.validate(data, shapes)
         count = length(report.violations)

         %{
           status: if(report.conforms, do: :conforms, else: :refused),
           violations: count,
           detail: "Report: #{count} violations",
           findings: findings(report.violations)
         }
       rescue
         e -> %{status: :error, violations: nil, detail: Exception.message(e)}
       end
     end}
  end

  # `<shape>/<constraint>@<path> xN`, sorted: the per-constraint breakdown
  # this court can report and the wasm kernel's validate_all/5 cannot.
  defp findings(violations) do
    violations
    |> Enum.frequencies_by(fn v ->
      path = if v.path, do: "@" <> curie(RDF.iri(v.path)), else: ""
      "#{v.shape}/#{v.constraint}#{path}"
    end)
    |> Enum.map(fn {key, n} -> "#{key} x#{n}" end)
    |> Enum.sort()
  end

  ## Work graph projection

  @doc """
  Projects a v26.9.22 `orders.json` (`%{repo => %{"orders" => [...]}}`) and
  its captured repo identities into an `sj:WorkOrder` graph, following the
  v26.9.21 `work-orders.ttl` convention.

  Fields `orders.json` does not carry are projected as explicit, uniform
  defaults (standing `UNKNOWN`, authority ceiling `CONSTRUCT`, one court,
  one acceptance node holding the acceptance text, one vacuity falsifier).
  Order `tokens` (human gates such as "publish authority") become
  `sj:authorityRequirement`; an order without tokens requires `NONE`.
  A repo without an observed origin slug gets no `sj:repository` triple --
  no slug is invented, so admission refuses it.
  """
  @spec work_graph(map(), map(), RDF.Graph.t()) :: RDF.Graph.t()
  def work_graph(orders_by_repo, repos, %RDF.Graph{} = vocabulary)
      when is_map(orders_by_repo) and is_map(repos) do
    orders_by_repo
    |> Enum.sort_by(fn {repo, _} -> repo end)
    |> Enum.flat_map(fn {repo, %{"orders" => orders}} ->
      repo_identity = Map.get(repos, repo, %{})
      Enum.flat_map(orders, &order_triples(&1, repo, repo_identity))
    end)
    |> RDF.Graph.new()
    |> RDF.Graph.add(vocabulary)
  end

  @doc """
  The shared vocabulary individuals (`sj:EvidenceRequirement` and
  `sj:ProjectionSpec` nodes) copied verbatim from the pack ontology.
  """
  @spec vocabulary(RDF.Graph.t()) :: RDF.Graph.t()
  def vocabulary(%RDF.Graph{} = pack_ontology) do
    classes = [sj("EvidenceRequirement"), sj("ProjectionSpec")]

    pack_ontology
    |> RDF.Graph.descriptions()
    |> Enum.filter(fn description ->
      description |> RDF.Description.get(RDF.type(), []) |> Enum.any?(&(&1 in classes))
    end)
    |> RDF.Graph.new()
  end

  defp order_triples(%{"id" => id, "title" => title} = order, repo, repo_identity) do
    wo = order_iri(id)
    local = wo_local(id)
    court = sj("court-" <> local)
    acc = sj("acc-" <> local)
    fal = sj("fal-" <> local)
    action = sj("run-court-" <> local)
    checkpoint = sj("cp-" <> local)
    tokens = Map.get(order, "tokens", [])

    requirement = if tokens == [], do: "NONE", else: Enum.join(tokens, "; ")

    edges =
      order
      |> Map.get("deps", [])
      |> Enum.flat_map(fn dep ->
        edge = sj("edge-#{local}-on-#{wo_local(dep)}")

        [
          {wo, sj("dependsOn"), edge},
          {edge, RDF.type(), sj("DependencyEdge")},
          {edge, rdfs("label"), RDF.literal("#{id} depends on #{dep}")},
          {edge, sj("dependencyType"), RDF.literal("requiresReceipt")},
          {edge, sj("upstreamWorkOrder"), order_iri(dep)}
        ]
      end)

    repository =
      case Map.get(repo_identity, "repository") do
        slug when is_binary(slug) -> [{wo, sj("repository"), RDF.literal(slug)}]
        _ -> []
      end

    base_sha =
      case Map.get(repo_identity, "base_sha") do
        sha when is_binary(sha) -> [{wo, sj("baseSha"), RDF.literal(sha)}]
        _ -> []
      end

    [
      {wo, RDF.type(), sj("WorkOrder")},
      {wo, rdfs("label"), RDF.literal("#{id}: #{title}")},
      {wo, dcterms("identifier"), RDF.literal(id)},
      {wo, dcterms("title"), RDF.literal(title)},
      {wo, dcterms("description"), RDF.literal(title)},
      {wo, sj("subject"), RDF.literal("#{repo}:release/#{@release}")},
      {wo, sj("standing"), RDF.literal("UNKNOWN")},
      {wo, sj("evidenceCeiling"), RDF.literal("UNVERIFIED")},
      {wo, sj("authorityCeiling"), RDF.literal("CONSTRUCT")},
      {wo, sj("authorityRequirement"), RDF.literal(requirement)},
      {wo, sj("promotionRule"), RDF.literal(@promotion_rule)},
      {wo, sj("replayIdentity"), RDF.literal("semantic-jira:#{@release}:#{id}")},
      {wo, sj("pathScope"), RDF.literal(".")},
      {wo, sj("requiresReceiptClass"), RDF.literal("verification")},
      {wo, sj("requiresCourt"), court},
      {wo, sj("requiresEvidence"), sj("local-execution-evidence")},
      {wo, sj("requiresEvidence"), sj("receipt-evidence")},
      {wo, sj("acceptance"), acc},
      {wo, sj("falsifier"), fal},
      {wo, sj("projection"), sj("projection-jira")},
      {wo, sj("nextAction"), action},
      {wo, sj("nextCheckpoint"), checkpoint},
      {court, RDF.type(), sj("Court")},
      {court, rdfs("label"), RDF.literal("#{id} exact-subject court")},
      {acc, RDF.type(), sj("AcceptanceCriterion")},
      {acc, dcterms("description"), RDF.literal(Map.get(order, "acceptance", ""))},
      {fal, RDF.type(), sj("Falsifier")},
      {fal, dcterms("description"),
       RDF.literal("The acceptance still passes on the reverted subject (vacuous admission).")},
      {action, RDF.type(), sj("Action")},
      {action, rdfs("label"), RDF.literal("Run the #{id} court")},
      {checkpoint, RDF.type(), sj("Checkpoint")},
      {checkpoint, rdfs("label"), RDF.literal("#{id} checkpoint")}
    ] ++ repository ++ base_sha ++ edges
  end

  @doc "The IRI a work-order id projects to."
  @spec order_iri(String.t()) :: RDF.IRI.t()
  def order_iri(id) when is_binary(id), do: sj(wo_local(id))

  defp wo_local(id), do: String.downcase(id)

  ## Closures and target restriction

  @doc "Predicates whose objects are owned by (and so targeted with) their work order."
  @spec owned_predicates() :: [String.t()]
  def owned_predicates, do: @owned

  @doc "Every `sj:WorkOrder` subject of `data`, sorted by IRI."
  @spec order_iris(RDF.Graph.t()) :: [RDF.IRI.t()]
  def order_iris(%RDF.Graph{} = data) do
    data
    |> RDF.Graph.descriptions()
    |> Enum.filter(&(sj("WorkOrder") in RDF.Description.get(&1, RDF.type(), [])))
    |> Enum.map(& &1.subject)
    |> Enum.sort_by(&RDF.IRI.to_string/1)
  end

  @doc "The order node plus every node it owns through `owned_predicates/0`."
  @spec closure(RDF.Graph.t(), RDF.IRI.t()) :: MapSet.t()
  def closure(%RDF.Graph{} = data, order) do
    owned =
      case RDF.Graph.get(data, order) do
        nil ->
          []

        description ->
          Enum.flat_map(@owned, &RDF.Description.get(description, sj(&1), []))
      end

    MapSet.new([order | owned])
  end

  @doc """
  Rewrites every node shape's targets into `sh:targetNode` triples naming only
  the members of `focus` that the original targets select in `data`.
  A node shape none of whose targets hits `focus` is left with no target.
  """
  @spec restrict_targets(RDF.Graph.t(), RDF.Graph.t(), MapSet.t()) :: RDF.Graph.t()
  def restrict_targets(%RDF.Graph{} = shapes, %RDF.Graph{} = data, %MapSet{} = focus) do
    Enum.reduce(node_shapes(shapes), shapes, fn node_shape, acc ->
      description = RDF.Graph.get(shapes, node_shape)
      selected = selected_targets(description, data, focus)

      removed =
        Enum.reduce(@target_terms, acc, fn term, graph ->
          RDF.Graph.delete(
            graph,
            Enum.map(RDF.Description.get(description, sh(term), []), &{node_shape, sh(term), &1})
          )
        end)

      RDF.Graph.add(removed, Enum.map(selected, &{node_shape, sh("targetNode"), &1}))
    end)
  end

  defp selected_targets(description, data, focus) do
    class_hits =
      description
      |> RDF.Description.get(sh("targetClass"), [])
      |> Enum.flat_map(fn class -> Enum.filter(focus, &typed?(data, &1, class)) end)

    node_hits =
      Enum.filter(RDF.Description.get(description, sh("targetNode"), []), &(&1 in focus))

    subject_hits =
      description
      |> RDF.Description.get(sh("targetSubjectsOf"), [])
      |> Enum.flat_map(fn predicate ->
        Enum.filter(focus, fn node -> has_predicate?(data, node, predicate) end)
      end)

    object_hits =
      description
      |> RDF.Description.get(sh("targetObjectsOf"), [])
      |> Enum.flat_map(fn predicate ->
        data
        |> RDF.Graph.descriptions()
        |> Enum.flat_map(&RDF.Description.get(&1, predicate, []))
        |> Enum.filter(&(&1 in focus))
      end)

    (class_hits ++ node_hits ++ subject_hits ++ object_hits)
    |> Enum.uniq()
    |> Enum.sort_by(&to_string/1)
  end

  defp typed?(data, node, class) do
    case RDF.Graph.get(data, node) do
      nil -> false
      description -> class in RDF.Description.get(description, RDF.type(), [])
    end
  end

  defp has_predicate?(data, node, predicate) do
    case RDF.Graph.get(data, node) do
      nil -> false
      # RDF.Description.include?/3 takes a statement, not a bare predicate
      # (FunctionClauseError under rdf 3.0.1 on the first sh:targetSubjectsOf).
      description -> RDF.Description.first(description, predicate) != nil
    end
  end

  ## Single-constraint slices (localization)

  @typedoc "A leaf slice: `{leaf_id, group_id, node_shape_id, shapes_graph}`."
  @type leaf :: {String.t(), String.t(), String.t(), RDF.Graph.t()}

  @doc """
  Splits `shapes` into single-constraint shape graphs (leaves): one per
  property-shape constraint component (`<shape>/<component>@<path>`), one for
  each node shape's `sh:closed` (with every declared path kept so the
  allowed-predicate set is unchanged), and one per `sh:sparql` constraint
  (`<shape>/sparql:<n>`, numbered by message order). Each leaf keeps its node
  shape's targets and reuses the original property-shape node, so the union of
  a node shape's leaves is that node shape minus its annotations.
  """
  @spec slices(RDF.Graph.t()) :: [leaf()]
  def slices(%RDF.Graph{} = shapes) do
    shapes
    |> node_shapes()
    |> Enum.flat_map(&node_shape_slices(shapes, &1))
  end

  @doc """
  The three-level localization tree over `slices/1`: node shape -> component
  group (`<shape>/<component>`) -> leaf. Every level carries the union graph
  of the leaves below it.
  """
  @spec slice_tree(RDF.Graph.t()) :: [map()]
  def slice_tree(%RDF.Graph{} = shapes) do
    shapes
    |> slices()
    |> Enum.group_by(&elem(&1, 2))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {node_shape_id, leaves} ->
      groups =
        leaves
        |> Enum.group_by(&elem(&1, 1))
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {group_id, group_leaves} ->
          %{
            id: group_id,
            graph: union(group_leaves),
            leaves: Enum.map(group_leaves, fn {id, _, _, graph} -> {id, graph} end)
          }
        end)

      %{id: node_shape_id, graph: union(leaves), groups: groups}
    end)
  end

  defp union(leaves),
    do: Enum.reduce(leaves, RDF.Graph.new(), fn {_, _, _, g}, acc -> RDF.Graph.add(acc, g) end)

  defp node_shape_slices(shapes, node_shape) do
    description = RDF.Graph.get(shapes, node_shape)
    name = shape_name(node_shape)

    header =
      [{node_shape, RDF.type(), sh("NodeShape")}] ++
        Enum.flat_map(@target_terms, fn term ->
          Enum.map(RDF.Description.get(description, sh(term), []), &{node_shape, sh(term), &1})
        end)

    property_shapes =
      description
      |> RDF.Description.get(sh("property"), [])
      |> Enum.map(&{&1, RDF.Graph.get(shapes, &1)})
      |> Enum.reject(fn {_, d} -> is_nil(d) end)

    property_slices =
      Enum.flat_map(property_shapes, fn {ps, psd} ->
        property_constraint_slices(name, node_shape, header, ps, psd)
      end)

    closed_slices = closed_slice(name, node_shape, description, header, property_shapes, shapes)

    sparql_slices =
      description
      |> RDF.Description.get(sh("sparql"), [])
      |> Enum.map(&{&1, RDF.Graph.get(shapes, &1)})
      |> Enum.reject(fn {_, d} -> is_nil(d) end)
      |> Enum.sort_by(fn {_, d} -> d |> RDF.Description.first(sh("message")) |> to_string() end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{constraint, cd}, index} ->
        id = "#{name}/sparql:#{index}"

        {id, id, name,
         RDF.Graph.new(header ++ [{node_shape, sh("sparql"), constraint}]) |> RDF.Graph.add(cd)}
      end)

    (property_slices ++ closed_slices ++ sparql_slices)
    |> Enum.sort_by(&elem(&1, 0))
    |> dedupe_ids()
  end

  defp property_constraint_slices(name, node_shape, header, ps, psd) do
    path = RDF.Description.first(psd, sh("path"))
    flags = RDF.Description.get(psd, sh("flags"), [])

    context = %{name: name, node_shape: node_shape, header: header, ps: ps, path: path}

    psd
    |> RDF.Description.predicates()
    |> Enum.filter(&sh_term?/1)
    |> Enum.reject(&(local(&1) in @property_skip))
    |> Enum.flat_map(fn component ->
      psd
      |> RDF.Description.get(component, [])
      |> Enum.map(&property_leaf(context, component, &1, flags))
    end)
  end

  defp property_leaf(context, component, value, flags) do
    %{name: name, node_shape: node_shape, header: header, ps: ps, path: path} = context

    flag_triples =
      if local(component) == "pattern", do: Enum.map(flags, &{ps, sh("flags"), &1}), else: []

    group = "#{name}/#{local(component)}"

    {"#{group}@#{curie(path)}", group, name,
     RDF.Graph.new(
       header ++
         [{node_shape, sh("property"), ps}, {ps, sh("path"), path}, {ps, component, value}] ++
         flag_triples
     )}
  end

  defp closed_slice(name, node_shape, description, header, property_shapes, shapes) do
    case RDF.Description.first(description, sh("closed")) do
      nil ->
        []

      closed ->
        ignored =
          description
          |> RDF.Description.get(sh("ignoredProperties"), [])
          |> Enum.flat_map(fn head ->
            [{node_shape, sh("ignoredProperties"), head} | list_triples(shapes, head)]
          end)

        paths =
          Enum.flat_map(property_shapes, fn {ps, psd} ->
            [
              {node_shape, sh("property"), ps},
              {ps, sh("path"), RDF.Description.first(psd, sh("path"))}
            ]
          end)

        id = "#{name}/closed"

        [
          {id, id, name,
           RDF.Graph.new(header ++ [{node_shape, sh("closed"), closed}] ++ ignored ++ paths)}
        ]
    end
  end

  defp list_triples(shapes, node) do
    case RDF.Graph.get(shapes, node) do
      nil ->
        []

      description ->
        first = RDF.Description.get(description, RDF.iri(@rdf <> "first"), [])
        rest = RDF.Description.get(description, RDF.iri(@rdf <> "rest"), [])

        Enum.map(first, &{node, RDF.iri(@rdf <> "first"), &1}) ++
          Enum.flat_map(rest, fn next ->
            [{node, RDF.iri(@rdf <> "rest"), next} | list_triples(shapes, next)]
          end)
    end
  end

  defp dedupe_ids(leaves) do
    leaves
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      {_id, [single]} ->
        [single]

      {id, many} ->
        many
        |> Enum.with_index(1)
        |> Enum.map(fn {{_, group, name, g}, i} -> {"#{id}##{i}", group, name, g} end)
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  ## Mutations

  @doc "Stable ids of the mutation operators, `m00_identity` first."
  @spec mutation_ids() :: [String.t()]
  def mutation_ids, do: Enum.map(mutation_specs(), &elem(&1, 0))

  @doc """
  Applies every mutation operator to `data`. `target` is the mutated order;
  `other` is a second order used by the cross-order operators (duplicate
  identifier / replay identity). Returns `[%{id, rule, touched, graph}]`
  where `touched` is the set of subjects whose triples changed (added to the
  per-mutation focus).
  """
  @spec mutate(RDF.Graph.t(), RDF.IRI.t(), RDF.IRI.t()) :: [map()]
  def mutate(%RDF.Graph{} = data, target, other) do
    Enum.map(mutation_specs(), fn {id, rule, fun} ->
      {removed, added} = fun.(data, target, other)
      graph = data |> RDF.Graph.delete(removed) |> RDF.Graph.add(added)
      touched = MapSet.new(removed ++ added, fn {s, _, _} -> s end)
      %{id: id, rule: rule, touched: touched, graph: graph}
    end)
  end

  defp mutation_specs do
    [
      {"m00_identity", "no change: both kernels must reproduce the unmutated verdict",
       fn _d, _t, _o -> {[], []} end},
      {"m01_drop_base_sha", "sh:minCount 1 on sj:baseSha", drop_value(sj("baseSha"))},
      {"m02_base_sha_not_sha", "sh:pattern ^[0-9a-f]{40}$ on sj:baseSha",
       set_value(sj("baseSha"), RDF.literal("main"))},
      {"m03_standing_invalid", "sh:pattern on sj:standing",
       set_value(sj("standing"), RDF.literal("alive"))},
      {"m04_authority_ceiling_do", "sh:pattern OBSERVE|SELECT|CONSTRUCT on sj:authorityCeiling",
       set_value(sj("authorityCeiling"), RDF.literal("DO"))},
      {"m05_identifier_lowercase", "sh:pattern on dcterms:identifier",
       set_value(dcterms("identifier"), RDF.literal("lowercase-id"))},
      {"m06_title_not_string", "sh:datatype xsd:string on dcterms:title",
       set_value(dcterms("title"), RDF.literal(42))},
      {"m07_second_title", "sh:maxCount 1 on dcterms:title",
       fn _d, t, _o -> {[], [{t, dcterms("title"), RDF.literal("a second title")}]} end},
      {"m08_empty_description", "sh:minLength 1 on dcterms:description",
       set_value(dcterms("description"), RDF.literal(""))},
      {"m09_closed_extra_predicate", "sh:closed on sj:WorkOrderShape",
       fn _d, t, _o -> {[], [{t, sj("undeclaredPredicate"), RDF.literal("x")}]} end},
      {"m10_court_untyped", "sh:class sj:Court on sj:requiresCourt",
       set_value(sj("requiresCourt"), sj("not-a-court"))},
      {"m11_alive_without_receipt", "sh:sparql ALIVE requires exact SHAs and a durable receipt",
       set_value(sj("standing"), RDF.literal("ALIVE"))},
      {"m12_authority_unbound", "sh:sparql authority-requiring work binds authority/lease/worker",
       set_value(sj("authorityRequirement"), RDF.literal("publish authority"))},
      {"m13_duplicate_identifier", "sh:sparql work order identifiers unique",
       &copy_value(&1, &2, &3, dcterms("identifier"))},
      {"m14_duplicate_replay_identity", "sh:sparql replay identities unique",
       &copy_value(&1, &2, &3, sj("replayIdentity"))},
      {"m15_dangling_dependency", "sh:sparql dependency identities resolve to WorkOrders",
       &dangle_dependency/3},
      {"m16_projection_claims_authority",
       "sh:hasValue NONE on sj:authorityClaim (ProjectionSpec)",
       fn d, _t, _o ->
         replace(d, sj("projection-jira"), sj("authorityClaim"), RDF.literal("SELECT"))
       end},
      {"m17_repository_pattern", "sh:pattern owner/name on sj:repository",
       set_value(sj("repository"), RDF.literal("no-slash"))}
    ]
  end

  defp current(data, subject, predicate) do
    case RDF.Graph.get(data, subject) do
      nil -> []
      description -> RDF.Description.get(description, predicate, [])
    end
  end

  defp drop_value(predicate), do: fn data, target, _other -> drop(data, target, predicate) end

  defp set_value(predicate, value),
    do: fn data, target, _other -> replace(data, target, predicate, value) end

  defp drop(data, subject, predicate),
    do: {Enum.map(current(data, subject, predicate), &{subject, predicate, &1}), []}

  defp replace(data, subject, predicate, value) do
    {removed, _} = drop(data, subject, predicate)
    {removed, [{subject, predicate, value}]}
  end

  defp copy_value(data, target, other, predicate) do
    case current(data, other, predicate) do
      [value | _] -> replace(data, target, predicate, value)
      [] -> {[], []}
    end
  end

  defp dangle_dependency(_data, target, _other) do
    edge = sj("edge-#{local(target)}-on-dangling")

    {[],
     [
       {target, sj("dependsOn"), edge},
       {edge, RDF.type(), sj("DependencyEdge")},
       {edge, sj("dependencyType"), RDF.literal("requiresReceipt")},
       {edge, sj("upstreamWorkOrder"), sj("no-such-work-order")}
     ]}
  end

  ## Serialization, evaluation and classification

  @doc """
  Serializes a graph as Turtle under a fixed prefix map. RDF.ex's Turtle
  encoder orders output by term, so for a graph without blank nodes the bytes
  depend only on the graph -- the same graph built in a different insertion
  order yields the same bytes. Blank-node labels come from a VM-global
  generator, so a graph with blank nodes (every shapes graph) is first
  relabelled by RDF Dataset Canonicalization (`RDF.Graph.canonicalize/1`,
  RDFC-1.0) to keep its bytes, and so its recorded sha256, replay-stable.
  """
  @spec to_turtle(RDF.Graph.t()) :: String.t()
  def to_turtle(%RDF.Graph{} = graph) do
    graph
    |> then(&if(blank_nodes?(&1), do: RDF.Graph.canonicalize(&1), else: &1))
    |> RDF.Turtle.write_string!(prefixes: @prefixes)
  end

  defp blank_nodes?(graph) do
    graph
    |> RDF.Graph.triples()
    |> Enum.any?(fn {s, _, o} -> is_struct(s, RDF.BlankNode) or is_struct(o, RDF.BlankNode) end)
  end

  @doc "sha256 hex of a binary, as recorded for every kernel input in the report."
  @spec sha256(binary()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc """
  Serializes `data` once and parses those exact bytes once, for reuse across
  every case evaluated against the same data graph.
  """
  @spec prepare(RDF.Graph.t()) :: map()
  def prepare(%RDF.Graph{} = data) do
    ttl = to_turtle(data)
    %{graph: data, ttl: ttl, parsed: RDF.Turtle.read_string!(ttl), sha256: sha256(ttl)}
  end

  @doc "Runs every kernel on one input; returns `%{kernel_name => verdict}`."
  @spec evaluate([kernel()], input()) :: %{String.t() => verdict()}
  def evaluate(kernels, input) do
    Map.new(kernels, fn {name, fun} -> {name, fun.(input)} end)
  end

  @doc """
  Evaluates `shapes` (targets restricted to `focus` unless `focus` is nil)
  against prepared data with every kernel. Returns the verdicts, their
  classification and the sha256 of the shapes bytes the kernels received.
  """
  @spec evaluate_shapes([kernel()], map(), RDF.Graph.t(), MapSet.t() | nil) :: map()
  def evaluate_shapes(kernels, prepared, %RDF.Graph{} = shapes, focus) do
    shapes = if focus, do: restrict_targets(shapes, prepared.graph, focus), else: shapes
    shapes_ttl = to_turtle(shapes)

    input = %{
      data_ttl: prepared.ttl,
      data_graph: prepared.parsed,
      shapes_ttl: shapes_ttl,
      shapes_graph: RDF.Turtle.read_string!(shapes_ttl)
    }

    verdicts = evaluate(kernels, input)

    %{
      verdicts: verdicts,
      classification: classify(verdicts),
      data_sha256: prepared.sha256,
      shapes_sha256: sha256(shapes_ttl)
    }
  end

  @doc """
  Classifies one case's verdicts (kernels ordered by name):

    * `AGREE_ADMIT` / `AGREE_REFUSE` -- same admission verdict and, for a
      refusal, the same violation count;
    * `AGREE_REFUSE_COUNT_DIFF` -- both refuse, counts differ;
    * `DISAGREE` -- one admits what the other refuses (`stricter` names the
      refusing kernel);
    * `KERNEL_ERROR` -- a kernel did not produce a verdict (`errored` names it).
  """
  @spec classify(%{String.t() => verdict()}) :: map()
  def classify(verdicts) when map_size(verdicts) == 2 do
    [{a, va}, {b, vb}] = Enum.sort_by(verdicts, &elem(&1, 0))

    case for({k, %{status: :error}} <- [{a, va}, {b, vb}], do: k) do
      [] -> compare({a, va}, {b, vb})
      errored -> %{class: "KERNEL_ERROR", errored: errored}
    end
  end

  defp compare({a, %{status: status} = va}, {b, %{status: status} = vb}) do
    cond do
      status == :conforms ->
        %{class: "AGREE_ADMIT"}

      va.violations == vb.violations ->
        %{class: "AGREE_REFUSE"}

      true ->
        %{class: "AGREE_REFUSE_COUNT_DIFF", counts: %{a => va.violations, b => vb.violations}}
    end
  end

  defp compare({a, va}, {b, _vb}),
    do: %{class: "DISAGREE", stricter: if(va.status == :refused, do: a, else: b)}

  @doc "True when the classification is anything but full agreement."
  @spec differs?(map()) :: boolean()
  def differs?(%{class: class}), do: class not in ["AGREE_ADMIT", "AGREE_REFUSE"]

  @doc """
  Localizes a differing case to single-constraint leaves.

  With `candidates` (leaf ids), those leaves are tried first; when at least
  one differs the explanation is `method: "candidate"`. Otherwise (or with no
  candidates) the tree from `slice_tree/1` is descended level by level --
  node shapes, then component groups inside each differing node shape, then
  leaves inside each differing group -- `method: "hierarchical"`.

  `type` is `SLICE_LOCALIZED` when every differing node shape/group resolved to
  differing leaves, `SLICE_LOCALIZED_WITH_RESIDUE` when some leaves differ but
  a differing node shape or group has no differing child (listed in
  `residue`), and `NON_COMPOSITIONAL` when no leaf reproduces the difference.
  """
  @spec localize([kernel()], map(), [map()], map(), MapSet.t() | nil, [String.t()], keyword()) ::
          map()
  def localize(kernels, prepared, tree, leaf_index, focus, candidates, opts \\ []) do
    eval = fn graph -> evaluate_shapes(kernels, prepared, graph, focus) end

    candidate_hits =
      candidates
      |> Enum.filter(&Map.has_key?(leaf_index, &1))
      |> pmap(fn id -> {id, eval.(Map.fetch!(leaf_index, id))} end, opts)
      |> Enum.filter(fn {_, result} -> differs?(result.classification) end)

    if candidate_hits == [] do
      hierarchical(tree, eval, opts)
    else
      explanation("candidate", Enum.map(candidate_hits, &leaf_diff/1), [])
    end
  end

  defp hierarchical(tree, eval, opts) do
    node_hits =
      tree
      |> pmap(fn node -> {node, eval.(node.graph)} end, opts)
      |> Enum.filter(fn {_, result} -> differs?(result.classification) end)

    group_results =
      node_hits
      |> Enum.flat_map(fn {node, node_result} ->
        Enum.map(node.groups, &{node, node_result, &1})
      end)
      |> pmap(
        fn {node, node_result, group} -> {node, node_result, group, eval.(group.graph)} end,
        opts
      )

    group_hits = Enum.filter(group_results, fn {_, _, _, r} -> differs?(r.classification) end)

    node_residue =
      node_hits
      |> Enum.reject(fn {node, _} ->
        Enum.any?(group_hits, fn {n, _, _, _} -> n.id == node.id end)
      end)
      |> Enum.map(fn {node, result} -> residue("node_shape", node.id, result) end)

    leaf_results =
      group_hits
      |> Enum.flat_map(fn {_, _, group, group_result} ->
        Enum.map(group.leaves, &{group, group_result, &1})
      end)
      |> pmap(
        fn {group, group_result, {id, graph}} -> {group, group_result, id, eval.(graph)} end,
        opts
      )

    leaf_hits = Enum.filter(leaf_results, fn {_, _, _, r} -> differs?(r.classification) end)

    group_residue =
      group_hits
      |> Enum.reject(fn {_, _, group, _} ->
        Enum.any?(leaf_hits, fn {g, _, _, _} -> g.id == group.id end)
      end)
      |> Enum.map(fn {_, _, group, result} -> residue("group", group.id, result) end)

    explanation(
      "hierarchical",
      Enum.map(leaf_hits, fn {_, _, id, result} -> leaf_diff({id, result}) end),
      node_residue ++ group_residue
    )
  end

  defp explanation(method, leaf_diffs, residue) do
    type =
      cond do
        leaf_diffs == [] -> "NON_COMPOSITIONAL"
        residue == [] -> "SLICE_LOCALIZED"
        true -> "SLICE_LOCALIZED_WITH_RESIDUE"
      end

    %{
      type: type,
      method: method,
      slices: Enum.sort_by(leaf_diffs, & &1.slice),
      residue: Enum.sort_by(residue, & &1.id)
    }
  end

  defp leaf_diff({id, result}),
    do: %{
      slice: id,
      classification: result.classification,
      verdicts: result.verdicts,
      shapes_sha256: result.shapes_sha256
    }

  defp residue(level, id, result),
    do: %{level: level, id: id, classification: result.classification, verdicts: result.verdicts}

  ## Calibration (construct-level root cause)

  @calibration_prefix """
  @prefix ex: <http://example.org/kd#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  """

  @doc """
  Minimal single-construct cases with their SHACL-spec verdict (W3C SHACL
  Core / SHACL-SPARQL). `probe/1` runs them through both kernels and attributes
  every localized leaf diff to the calibration cases of the same constraint
  component on which a kernel departs from the spec -- the construct-level
  cause behind a slice-level diff.
  """
  @spec calibration_cases() :: [map()]
  def calibration_cases do
    [
      cal(
        "c01_min_count",
        "minCount",
        :refused,
        1,
        "ex:a a ex:C .",
        "sh:property [ sh:path ex:p ; sh:minCount 1 ]"
      ),
      cal(
        "c02_max_count",
        "maxCount",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x", "y" .),
        "sh:property [ sh:path ex:p ; sh:maxCount 1 ]"
      ),
      cal(
        "c03_pattern",
        "pattern",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "main" .),
        ~s(sh:property [ sh:path ex:p ; sh:pattern "^[0-9a-f]{40}$" ])
      ),
      cal(
        "c04_datatype",
        "datatype",
        :refused,
        1,
        "ex:a a ex:C ; ex:p 42 .",
        "sh:property [ sh:path ex:p ; sh:datatype xsd:string ]"
      ),
      cal(
        "c05_min_length",
        "minLength",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "" .),
        "sh:property [ sh:path ex:p ; sh:minLength 1 ]"
      ),
      cal(
        "c06_class",
        "class",
        :refused,
        1,
        "ex:a a ex:C ; ex:p ex:b .",
        "sh:property [ sh:path ex:p ; sh:class ex:D ]"
      ),
      cal(
        "c07_node_kind",
        "nodeKind",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "lit" .),
        "sh:property [ sh:path ex:p ; sh:nodeKind sh:IRI ]"
      ),
      cal(
        "c08_closed",
        "closed",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x" ; ex:q "y" .),
        "sh:closed true ; sh:ignoredProperties ( rdf:type ) ; sh:property [ sh:path ex:p ]"
      ),
      # SHACL 4.8.1: rdf:type is not implicitly ignored by sh:closed.
      cal(
        "c08b_closed_rdf_type_not_implicit",
        "closed",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x" .),
        "sh:closed true ; sh:property [ sh:path ex:p ]"
      ),
      cal(
        "c09_has_value_string_conforming",
        "hasValue",
        :conforms,
        0,
        ~s(ex:a a ex:C ; ex:p "NONE" .),
        ~s(sh:property [ sh:path ex:p ; sh:hasValue "NONE" ])
      ),
      cal(
        "c10_has_value_string_violating",
        "hasValue",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "SELECT" .),
        ~s(sh:property [ sh:path ex:p ; sh:hasValue "NONE" ])
      ),
      cal(
        "c11_has_value_boolean_conforming",
        "hasValue",
        :conforms,
        0,
        "ex:a a ex:C ; ex:p true .",
        "sh:property [ sh:path ex:p ; sh:hasValue true ]"
      ),
      cal(
        "c12_has_value_iri_conforming",
        "hasValue",
        :conforms,
        0,
        "ex:a a ex:C ; ex:p ex:v .",
        "sh:property [ sh:path ex:p ; sh:hasValue ex:v ]"
      ),
      cal(
        "c13_sparql_select_this",
        "sparql",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x" .),
        sparql("SELECT $this WHERE { $this <http://example.org/kd#p> ?v . }")
      ),
      cal(
        "c14_sparql_prefixed",
        "sparql",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x" .),
        sparql("PREFIX ex: <http://example.org/kd#>\nSELECT $this WHERE { $this ex:p ?v . }")
      ),
      cal(
        "c15_sparql_optional_unbound",
        "sparql",
        :refused,
        1,
        ~s(ex:a a ex:C ; ex:p "x" .),
        sparql(
          "SELECT $this WHERE { $this <http://example.org/kd#p> ?v . " <>
            "OPTIONAL { $this <http://example.org/kd#q> ?w . } FILTER(!BOUND(?w)) }"
        )
      ),
      cal(
        "c16_sparql_self_join",
        "sparql",
        :refused,
        2,
        ~s(ex:a a ex:C ; ex:id "X" .\nex:b a ex:C ; ex:id "X" .),
        sparql(
          "SELECT $this WHERE { $this <http://example.org/kd#id> ?id . " <>
            "?other a <http://example.org/kd#C> ; <http://example.org/kd#id> ?id . " <>
            "FILTER(?other != $this) }"
        )
      ),
      cal(
        "c17_sparql_no_rows",
        "sparql",
        :conforms,
        0,
        ~s(ex:a a ex:C ; ex:p "x" .),
        sparql("SELECT $this WHERE { $this <http://example.org/kd#absent> ?v . }")
      )
    ]
  end

  defp cal(id, component, expected, expected_violations, data, shape_body) do
    %{
      id: id,
      component: component,
      expected: expected,
      expected_violations: expected_violations,
      data_ttl: @calibration_prefix <> data <> "\n",
      shapes_ttl:
        @calibration_prefix <> "ex:S a sh:NodeShape ; sh:targetClass ex:C ; #{shape_body} .\n"
    }
  end

  defp sparql(query), do: ~s(sh:sparql [ sh:message "calibration" ; sh:select """#{query}""" ])

  @doc """
  Runs `calibration_cases/0` through every kernel. Each row records the
  verdicts and, per kernel, whether the verdict matches the spec
  (`on_spec`: status and violation count both as expected).
  """
  @spec calibrate([kernel()]) :: [map()]
  def calibrate(kernels) do
    Enum.map(calibration_cases(), fn c ->
      input = %{
        data_ttl: c.data_ttl,
        shapes_ttl: c.shapes_ttl,
        data_graph: RDF.Turtle.read_string!(c.data_ttl),
        shapes_graph: RDF.Turtle.read_string!(c.shapes_ttl)
      }

      verdicts = evaluate(kernels, input)

      on_spec =
        Map.new(verdicts, fn {name, v} ->
          {name, v.status == c.expected and v.violations == c.expected_violations}
        end)

      %{
        id: c.id,
        component: c.component,
        expected: %{status: c.expected, violations: c.expected_violations},
        verdicts: verdicts,
        on_spec: on_spec,
        data_sha256: sha256(c.data_ttl),
        shapes_sha256: sha256(c.shapes_ttl)
      }
    end)
  end

  # The constraint component a leaf id names: "<shape>/<component>@<path>",
  # "<shape>/sparql:<n>" or "<shape>/closed".
  defp leaf_component(slice_id) do
    slice_id
    |> String.split("/", parts: 2)
    |> List.last()
    |> String.split(["@", ":", "#"], parts: 2)
    |> hd()
  end

  # Adds `cause` to every leaf diff: the calibration cases of the same
  # component on which some kernel is off-spec. An empty cause list is typed
  # UNCALIBRATED rather than left implicit.
  defp attribute(nil, _calibration), do: nil

  defp attribute(explanation, calibration),
    do: %{explanation | slices: Enum.map(explanation.slices, &leaf_cause(&1, calibration))}

  defp leaf_cause(diff, calibration) do
    component = leaf_component(diff.slice)

    causes =
      for row <- calibration,
          row.component == component,
          off = for({k, false} <- row.on_spec, do: k),
          off != [],
          do: %{calibration: row.id, off_spec: Enum.sort(off)}

    Map.merge(diff, %{
      component: component,
      cause: causes,
      cause_type: if(causes == [], do: "UNCALIBRATED", else: "CALIBRATED")
    })
  end

  ## Probe orchestration

  @doc """
  Runs the whole probe and returns the report body (render with `encode/1`):

    * `calibration` -- `calibrate/1` over both kernels;
    * `whole_graph` -- the unrestricted pack shapes over the whole work graph;
    * `per_order` -- one case per work order (targets restricted to its
      closure), in IRI order;
    * `mutations` -- `mutate/3` over the first two orders both kernels admit
      (`mutation_base`); each case is focused on the target's closure plus the
      touched subjects and carries a `baseline` (the unmutated data under the
      same focused shapes) and a per-kernel `detection`: `DETECTED` when the
      mutated violation count exceeds the baseline count, else
      `NOT_DETECTED` (`KERNEL_ERROR` if either run errored).
      `mutation_base.status` is `NO_ADMITTED_BASE` when fewer than two such
      orders exist;
    * `matrix` -- class counts per section; `disagreements` -- every differing
      case (verdict classification not in AGREE_ADMIT/AGREE_REFUSE, or, for a
      mutation, kernels differing on detection) with its typed explanation;
      each explained leaf carries a calibration `cause`.

  Options: `:kernels` (exactly two), `:data`, `:shapes`, `:orders`
  (`[%{id, repo}]`, keyed to `order_iri/1`), `:max_concurrency`.
  """
  @spec probe(keyword()) :: map()
  def probe(opts) do
    kernels = Keyword.fetch!(opts, :kernels)
    data = Keyword.fetch!(opts, :data)
    shapes = Keyword.fetch!(opts, :shapes)

    order_meta =
      opts |> Keyword.get(:orders, []) |> Map.new(&{RDF.IRI.to_string(order_iri(&1.id)), &1})

    pmap_opts = [max_concurrency: Keyword.get(opts, :max_concurrency, 1)]

    prepared = prepare(data)
    tree = slice_tree(shapes)
    leaf_index = Map.new(slices(shapes), fn {id, _, _, graph} -> {id, graph} end)
    calibration = calibrate(kernels)

    whole_task = Task.async(fn -> evaluate_shapes(kernels, prepared, shapes, nil) end)

    per_order =
      data
      |> order_iris()
      |> pmap(
        fn iri ->
          result = evaluate_shapes(kernels, prepared, shapes, closure(data, iri))
          meta = Map.get(order_meta, RDF.IRI.to_string(iri), %{})

          result
          |> Map.merge(%{iri: RDF.IRI.to_string(iri), id: meta[:id], repo: meta[:repo]})
          |> Map.put(:differs, differs?(result.classification))
        end,
        pmap_opts
      )

    {base, mutation_cases} =
      mutation_cases(kernels, data, prepared, shapes, per_order, pmap_opts)

    whole = Task.await(whole_task, :infinity)
    whole = Map.merge(whole, %{case: "whole_graph", differs: differs?(whole.classification)})

    whole_explanation =
      if whole.differs,
        do: localize(kernels, prepared, tree, leaf_index, nil, [], pmap_opts),
        else: nil

    candidates =
      if whole_explanation, do: Enum.map(whole_explanation.slices, & &1.slice), else: []

    per_order =
      pmap(
        per_order,
        fn case_result ->
          explain(case_result, fn ->
            focus = closure(data, RDF.iri(case_result.iri))
            localize(kernels, prepared, tree, leaf_index, focus, candidates)
          end)
        end,
        pmap_opts
      )

    mutation_cases =
      mutation_cases
      |> pmap(
        fn m ->
          explain(m, fn ->
            localize_mutation(kernels, prepared, tree, leaf_index, candidates, m)
          end)
        end,
        pmap_opts
      )
      |> Enum.map(&Map.drop(&1, [:prepared, :focus]))

    whole = Map.put(whole, :explanation, whole_explanation)

    [whole | per_order] =
      Enum.map(
        [whole | per_order],
        &Map.update!(&1, :explanation, fn e -> attribute(e, calibration) end)
      )

    mutation_cases =
      Enum.map(
        mutation_cases,
        &Map.update!(&1, :explanation, fn e -> attribute(e, calibration) end)
      )

    cases = [whole | per_order] ++ mutation_cases

    %{
      calibration: calibration,
      whole_graph: whole,
      per_order: per_order,
      mutation_base: base,
      mutations: mutation_cases,
      matrix: %{
        whole_graph: whole.classification.class,
        per_order: Enum.frequencies_by(per_order, & &1.classification.class),
        mutations: Enum.frequencies_by(mutation_cases, & &1.classification.class),
        mutation_detection:
          Enum.frequencies_by(mutation_cases, fn m ->
            m.detection |> Enum.sort() |> Enum.map_join(",", fn {k, v} -> "#{k}=#{v}" end)
          end),
        calibration_off_spec:
          kernels
          |> Enum.map(&elem(&1, 0))
          |> Map.new(fn k ->
            {k, calibration |> Enum.reject(& &1.on_spec[k]) |> Enum.map(& &1.id)}
          end)
      },
      disagreements: cases |> Enum.filter(& &1.differs) |> Enum.map(&disagreement/1),
      untyped_disagreements: Enum.count(cases, &(&1.differs and is_nil(&1.explanation))),
      slice_count: map_size(leaf_index)
    }
  end

  defp disagreement(c) do
    slices = if c.explanation, do: c.explanation.slices, else: []

    %{
      case: c[:id] || c[:case] || c[:iri],
      classification: c.classification,
      detection: c[:detection],
      explanation_type: c.explanation && c.explanation.type,
      slices: Enum.map(slices, &Map.take(&1, [:slice, :cause_type, :cause]))
    }
  end

  # The mutated run explains a verdict difference; when the kernels agree on
  # the mutated verdict but not on detection, the baseline run is where they
  # differ.
  defp localize_mutation(kernels, prepared, tree, leaf_index, candidates, m) do
    data = if differs?(m.classification), do: m.prepared, else: prepared
    localize(kernels, data, tree, leaf_index, m.focus, candidates)
  end

  defp explain(case_result, localize_fun) do
    if case_result.differs,
      do: Map.put(case_result, :explanation, localize_fun.()),
      else: Map.put(case_result, :explanation, nil)
  end

  defp mutation_cases(kernels, data, prepared, shapes, per_order, pmap_opts) do
    admitted =
      per_order
      |> Enum.filter(&(&1.classification.class == "AGREE_ADMIT"))
      |> Enum.map(&RDF.iri(&1.iri))

    case admitted do
      [target, other | _] ->
        base = %{
          status: "SELECTED",
          target: RDF.IRI.to_string(target),
          other: RDF.IRI.to_string(other),
          rule: "first two orders (IRI order) that both kernels admit"
        }

        cases =
          data
          |> mutate(target, other)
          |> pmap(&mutation_case(kernels, prepared, shapes, target, &1), pmap_opts)

        {base, cases}

      _ ->
        {%{status: "NO_ADMITTED_BASE", admitted_orders: length(admitted)}, []}
    end
  end

  defp mutation_case(kernels, prepared, shapes, target, m) do
    focus = MapSet.union(closure(m.graph, target), m.touched)
    mutated = prepare(m.graph)
    result = evaluate_shapes(kernels, mutated, shapes, focus)
    baseline = evaluate_shapes(kernels, prepared, shapes, focus)

    detection =
      Map.new(result.verdicts, fn {k, v} -> {k, detection(baseline.verdicts[k], v)} end)

    result
    |> Map.merge(%{
      case: m.id,
      id: m.id,
      rule: m.rule,
      touched: m.touched |> Enum.map(&to_string/1) |> Enum.sort(),
      baseline: Map.take(baseline, [:verdicts, :classification, :shapes_sha256]),
      detection: detection,
      differs:
        differs?(result.classification) or
          detection |> Map.values() |> Enum.uniq() |> length() > 1,
      prepared: mutated,
      focus: focus
    })
  end

  defp detection(%{status: :error}, _), do: "KERNEL_ERROR"
  defp detection(_, %{status: :error}), do: "KERNEL_ERROR"

  defp detection(base, mutated) do
    if (mutated.violations || 0) > (base.violations || 0), do: "DETECTED", else: "NOT_DETECTED"
  end

  @doc """
  Encodes a report as pretty JSON with every object's keys sorted, so the
  same report always yields the same bytes.
  """
  @spec encode(term()) :: String.t()
  def encode(report), do: report |> to_json_term() |> ordered() |> Jason.encode!(pretty: true)

  defp ordered(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), ordered(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  @doc """
  Converts a report (or any term built from it) into JSON-encodable data:
  atoms stay atoms (Jason encodes them as strings), `RDF.IRI`s and
  `MapSet`s become strings and sorted lists, tuples become lists.
  """
  @spec to_json_term(term()) :: term()
  def to_json_term(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  def to_json_term(%MapSet{} = set), do: set |> Enum.map(&to_json_term/1) |> Enum.sort()

  def to_json_term(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, to_json_term(v)} end)

  def to_json_term(list) when is_list(list), do: Enum.map(list, &to_json_term/1)
  def to_json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> to_json_term()
  def to_json_term(other), do: other

  defp pmap(enumerable, fun, opts) do
    enumerable
    |> Task.async_stream(fun,
      max_concurrency: Keyword.get(opts, :max_concurrency, 1),
      timeout: :infinity,
      ordered: true
    )
    |> Enum.map(fn {:ok, value} -> value end)
  end

  ## Helpers

  defp node_shapes(shapes) do
    shapes
    |> RDF.Graph.descriptions()
    |> Enum.filter(&(sh("NodeShape") in RDF.Description.get(&1, RDF.type(), [])))
    |> Enum.map(& &1.subject)
    |> Enum.sort_by(&to_string/1)
  end

  defp shape_name(%RDF.IRI{} = iri), do: iri |> local() |> Macro.underscore()
  defp shape_name(other), do: to_string(other)

  defp sh_term?(%RDF.IRI{} = iri), do: String.starts_with?(RDF.IRI.to_string(iri), @sh)
  defp sh_term?(_), do: false

  defp curie(%RDF.IRI{} = iri) do
    value = RDF.IRI.to_string(iri)

    Enum.find_value(@prefixes, value, fn {prefix, ns} ->
      if String.starts_with?(value, ns),
        do: "#{prefix}:" <> String.replace_prefix(value, ns, "")
    end)
  end

  defp curie(other), do: to_string(other)

  defp local(%RDF.IRI{} = iri),
    do: iri |> RDF.IRI.to_string() |> String.split(["#", "/"]) |> List.last()

  defp sj(term), do: RDF.iri(@sj <> term)
  defp sh(term), do: RDF.iri(@sh <> term)
  defp rdfs(term), do: RDF.iri(@rdfs <> term)
  defp dcterms(term), do: RDF.iri(@dcterms <> term)
end
