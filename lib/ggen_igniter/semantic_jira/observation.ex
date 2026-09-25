defmodule GgenIgniter.SemanticJira.Observation do
  @moduledoc """
  The observation edge: an observed process delta becomes a *candidate*
  WorkOrder, admitted or refused, never selected or executed here.

      finding  --process_finding/1-->  finding
      finding + base WorkOrder  -->  candidate WorkOrder  --admit_work_order/1-->  admitted
      declared origin  --Authority.verify_origin/3-->  :ok | {:refused_origin, _}
      candidate node + canonical graph  --SHACL-->  conformance

  The kernel's `process_finding/1` (and, when `opts[:repair]` is given,
  `repair_work_order/2`) do the semantic construction; this module only maps
  their output onto a WorkOrder that reuses the base order's typed courts,
  evidence, projections, ceilings and path scope, and adds the
  observation-specific acceptance criterion, falsifier, next action and
  checkpoint. No new ontology terms are introduced.

  Admission is two fences (INVARIANT A). The observation is authority-bound:
  `opts[:origin_authority]` is required, and `Authority.verify_origin/3` must
  admit it against the canonical ontology before the candidate graph merges.
  Then the real SHACL court (`GgenIgniter.SemanticJira.Shacl`) runs over the
  canonical graph (`opts[:ontology_path]`, default the pack ontology) plus
  the candidate's triples, so global constraints such as identifier and replay
  identity uniqueness are enforced against the existing work graph. The
  frontier is unchanged by this module either way. The
  candidate is returned with its Turtle so the caller can append it to the
  canonical graph through BRCE; this module writes nothing.
  """

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Authority
  alias GgenIgniter.SemanticJira.Shacl

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @default_ontology "priv/ggen/semantic-jira-pack/ontology.ttl"
  @default_ceiling "CONSTRUCT"

  @doc """
  Options: `:origin_authority` (REQUIRED — INVARIANT A), `:origin_observation`
  (optional), `:ontology_path`, `:shapes_path`, `:identity`, `:title`,
  `:base_sha`, `:authority_ceiling` (default `"CONSTRUCT"`), `:repair` (attrs
  for `SemanticJira.repair_work_order/2`).

  `:origin_authority` is the IRI of the canonical authority this observation
  is bound to. It is checked before any kernel work: a missing or empty value
  is a typed refusal and the kernel never runs. `:origin_observation` defaults
  to the stable `...#obs-<digest12>-finding` identity for the observed
  finding.

  Returns `{:ok, %{"work_order", "finding", "repair", "turtle", "shacl"}}` or
  `{:error, {:observation_refused, reason}}` with reason, among others:

    * `{:missing_origin_authority, msg}` — no `:origin_authority` opt was
      given (refused before any kernel work)
    * `{:origin_not_admitted, reason}` — `Authority.verify_origin/3` refused
      the declared origin against the canonical ontology
    * `{:shacl_violations, violations}` — the merged graph does not conform
      to the pack shapes
  """
  @spec candidate(map(), map(), keyword()) ::
          {:ok, map()} | {:error, {:observation_refused, term()}}
  def candidate(finding_attrs, base_work_order, opts \\ [])
      when is_map(finding_attrs) and is_map(base_work_order) do
    with :ok <- require_origin_authority(opts),
         {:ok, finding} <- wrap(:finding, SemanticJira.process_finding(finding_attrs)),
         {:ok, base} <- wrap(:base_work_order, SemanticJira.admit_work_order(base_work_order)),
         {:ok, repair} <- repair(base, opts),
         ids = ids(finding, opts),
         {:ok, admitted} <-
           wrap(
             :work_order,
             SemanticJira.admit_work_order(work_order(finding, base, repair, ids, opts))
           ),
         turtle = turtle(admitted, ids, opts),
         {:ok, report} <- shacl(turtle, ids, opts) do
      {:ok,
       %{
         "work_order" => admitted,
         "finding" => finding,
         "repair" => repair,
         "turtle" => turtle,
         "shacl" => %{
           "conforms" => true,
           "shapes_checked" => report.shapes_checked,
           "focus_node_count" => report.focus_node_count
         }
       }}
    end
  end

  # INVARIANT A, fence 0: an authority-bound observation must declare the
  # origin it is bound to before any kernel work runs. There is no default.
  defp require_origin_authority(opts) do
    case Keyword.get(opts, :origin_authority) do
      value when is_binary(value) and value != "" ->
        :ok

      _ ->
        refuse(
          {:missing_origin_authority,
           "candidate/3 requires opts[:origin_authority]: the IRI of the canonical " <>
             "authority this observation is bound to"}
        )
    end
  end

  defp repair(base, opts) do
    case Keyword.get(opts, :repair) do
      nil -> {:ok, nil}
      attrs -> wrap(:repair, SemanticJira.repair_work_order(base, attrs))
    end
  end

  defp ids(finding, opts) do
    hex = finding["finding_digest"] |> String.replace_prefix("sha256:", "")
    short = String.slice(hex, 0, 12)

    %{
      hex: hex,
      short: short,
      identity: Keyword.get(opts, :identity, "OBS-" <> String.upcase(short)),
      node: "obs-" <> short
    }
  end

  defp work_order(finding, base, repair, ids, opts) do
    acceptance =
      [@sj <> ids.node <> "-acceptance-delta"] ++
        if repair, do: [@sj <> ids.node <> "-acceptance-guard"], else: []

    %{
      "identity" => ids.identity,
      "title" => Keyword.get(opts, :title, "Resolve observed process delta #{ids.short}"),
      "description" => description(finding, repair),
      "subject" => "semantic-jira:observation:" <> ids.hex,
      "repository" => base["repository"],
      "base_sha" => Keyword.get(opts, :base_sha, base["base_sha"]),
      "standing" => "UNKNOWN",
      "evidence_ceiling" => base["evidence_ceiling"],
      "promotion_rule" => base["promotion_rule"],
      "replay_identity" => "semantic-jira:observation:" <> ids.hex,
      "origin_authority" => Keyword.fetch!(opts, :origin_authority),
      "origin_observation" =>
        Keyword.get(opts, :origin_observation) || @sj <> ids.node <> "-finding",
      "dependencies" => [],
      "required_courts" => base["required_courts"],
      "required_evidence" => base["required_evidence"],
      "acceptance" => acceptance,
      "falsifiers" => [@sj <> ids.node <> "-falsifier-delta"],
      "projections" => base["projections"],
      "required_receipt_classes" => base["required_receipt_classes"],
      "path_scope" => base["path_scope"],
      "authority_requirement" => "NONE",
      "replay_required" => base["replay_required"]
    }
  end

  defp description(finding, nil), do: "Observed delta: #{delta_text(finding["delta"])}"

  defp description(finding, repair) do
    "Observed delta: #{delta_text(finding["delta"])} Hypothesis: #{repair["hypothesis"]} " <>
      "Smallest repair: #{repair["smallest_repair"]} Permanent guard: #{repair["permanent_guard"]}"
  end

  defp delta_text(delta) when is_binary(delta), do: delta
  defp delta_text(delta), do: Jason.encode!(delta)

  # --- graph ----------------------------------------------------------------------

  defp turtle(work_order, ids, opts) do
    node = "sj:" <> ids.node
    ceiling = Keyword.get(opts, :authority_ceiling, @default_ceiling)

    properties =
      [
        "a sj:WorkOrder",
        "dcterms:identifier #{lit(work_order["identity"])}",
        "dcterms:title #{lit(work_order["title"])}",
        "dcterms:description #{lit(work_order["description"])}",
        "sj:repository #{lit(work_order["repository"])}",
        "sj:baseSha #{lit(work_order["base_sha"])}",
        "sj:subject #{lit(work_order["subject"])}",
        "sj:standing #{lit(work_order["standing"])}",
        "sj:evidenceCeiling #{lit(work_order["evidence_ceiling"])}",
        "sj:authorityCeiling #{lit(ceiling)}",
        "sj:promotionRule #{lit(work_order["promotion_rule"])}",
        "sj:replayIdentity #{lit(work_order["replay_identity"])}",
        "sj:originAuthority #{iri(work_order["origin_authority"])}",
        "sj:originObservation #{iri(work_order["origin_observation"])}",
        "sj:authorityRequirement #{lit(work_order["authority_requirement"])}",
        "sj:nextAction sj:#{ids.node}-action",
        "sj:nextCheckpoint sj:#{ids.node}-checkpoint"
      ] ++
        multi("sj:pathScope", work_order["path_scope"], &lit/1) ++
        multi("sj:requiresReceiptClass", work_order["required_receipt_classes"], &lit/1) ++
        multi("sj:requiresCourt", work_order["required_courts"], &iri/1) ++
        multi("sj:requiresEvidence", work_order["required_evidence"], &iri/1) ++
        multi("sj:acceptance", work_order["acceptance"], &iri/1) ++
        multi("sj:falsifier", work_order["falsifiers"], &iri/1) ++
        multi("sj:projection", work_order["projections"], &iri(@sj <> "projection-" <> &1))

    [
      "@prefix sj: <#{@sj}> .",
      "@prefix dcterms: <http://purl.org/dc/terms/> .",
      "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
      "",
      "#{node}\n    " <> Enum.join(properties, " ;\n    ") <> " .",
      ""
    ]
    |> Kernel.++(typed_nodes(work_order, ids))
    |> Enum.join("\n")
  end

  defp typed_nodes(work_order, ids) do
    acceptance =
      Enum.map(work_order["acceptance"], fn iri ->
        typed(
          iri,
          "sj:AcceptanceCriterion",
          "Observation acceptance #{ids.short}",
          "The observed delta #{ids.short} no longer reproduces at the candidate head, " <>
            "or the permanent guard for it exists and passes."
        )
      end)

    falsifier =
      Enum.map(work_order["falsifiers"], fn iri ->
        typed(
          iri,
          "sj:Falsifier",
          "Observation falsifier #{ids.short}",
          "Re-observe the delta #{ids.short} at the candidate head; a reproduction falsifies the repair."
        )
      end)

    acceptance ++
      falsifier ++
      [
        typed(
          @sj <> ids.node <> "-action",
          "sj:Action",
          "Resolve observed delta #{ids.short}",
          "Repair the repository condition behind the observed delta within the declared path scope."
        ),
        typed(
          @sj <> ids.node <> "-checkpoint",
          "sj:Checkpoint",
          "Delta #{ids.short} re-observed clean",
          "Closed only by an independent exact-head court receipt for this subject."
        )
      ]
  end

  defp typed(iri_string, class, label, description) do
    "#{iri(iri_string)} a #{class} ;\n    rdfs:label #{lit(label)} ;\n    dcterms:description #{lit(description)} .\n"
  end

  defp multi(_predicate, [], _render), do: []

  defp multi(predicate, values, render),
    do: ["#{predicate} " <> Enum.map_join(values, ", ", render)]

  defp lit(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    ~s("#{escaped}")
  end

  defp iri(value),
    do: "<" <> (value |> to_string() |> String.replace(~r/[<>"{}|^`\\\s]/, &pct/1)) <> ">"

  defp pct(char), do: "%" <> Base.encode16(char)

  # --- SHACL ------------------------------------------------------------------------

  defp shacl(turtle, ids, opts) do
    ontology_path = Keyword.get(opts, :ontology_path, @default_ontology)
    shapes_path = Keyword.get(opts, :shapes_path, Shacl.pack_shapes_path())

    candidate_graph = RDF.Turtle.read_string!(turtle)
    canonical = Ontology.load!(ontology_path)

    # Fence 1 (INVARIANT A): an authority-bound process observation may
    # manufacture an executable WorkOrder only when the origin it declares is
    # admitted by the canonical ontology. An unverified origin is a typed
    # refusal before any SHACL work — the candidate never merges.
    case Authority.verify_origin(candidate_graph, canonical, @sj <> ids.node) do
      :ok ->
        # Fence 2 (INVARIANT A): the merged graph must conform to the pack
        # shapes; the frontier is unchanged by this observation either way.
        graph = RDF.Graph.add(canonical, candidate_graph)
        report = Shacl.validate_file(graph, shapes_path)

        if report.conforms,
          do: {:ok, report},
          else: refuse({:shacl_violations, Enum.map(report.violations, &violation/1)})

      {:error, {:refused_origin, reason}} ->
        refuse({:origin_not_admitted, reason})
    end
  end

  defp violation(violation) do
    violation
    |> Map.take([:shape, :focus_node, :constraint, :path, :message, :value])
    |> Map.new(fn {key, value} -> {key, term(value)} end)
  end

  defp term(value) when is_atom(value) or is_binary(value) or is_number(value), do: value
  defp term(value), do: inspect(value)

  defp wrap(_tag, {:ok, value}), do: {:ok, value}
  defp wrap(tag, {:error, reason}), do: refuse({tag, reason})
  defp refuse(reason), do: {:error, {:observation_refused, reason}}
end
