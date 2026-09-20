defmodule GgenIgniter.Crown do
  @moduledoc """
  W6-A8 closed-loop demonstration glue (named glue by the crown receipt).

  In-family composition over `GgenIgniter.SemanticJira` and the
  semantic-jira-pack graph; it owns NO new law. It:

    * manufactures candidate WorkOrders (primary + a dependent) from a
      `xaas-sensing/1` observation document produced by
      `Xaas.Ultracode.Sensing` and admits them through the kernel;
    * renders the deterministic Turtle section that appends those work
      orders to the canonical pack graph (the manufacture path — no ticket
      is ever edited anywhere in the loop);
    * extracts admitted kernel-shaped work orders back out of the canonical
      graph through the pack's own SPARQL engine and RDF loader, for kernel
      frontier selection;
    * projects a selected work order into the exact execution descriptor
      contract consumed by `Xaas.Ultracode.SemanticWork.admit/1`;
    * renders the reconciler's graph revision: the durable `sj:Receipt`,
      two lawful stepwise `sj:StandingTransition` nodes, and the ALIVE-state
      promotion of the primary work order block.

  The graph's own admission court
  (`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`) refuses a
  single `UNKNOWN -> ALIVE` StandingTransition, so promotion to ALIVE is
  recorded as the two lawful hops UNKNOWN -> PARTIAL_ALIVE -> ALIVE, each
  separately produced by the kernel's `promote/3`.
  """

  alias GgenIgniter.{Ontology, Query, SemanticJira}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms "http://purl.org/dc/terms/"
  @sensing_schema "xaas-sensing/1"
  @generator "ggen_igniter:crown-glue@26.9.19"

  @type refusal :: {:error, term()}

  # ----------------------------------------------------------------------
  # Observation -> candidate WorkOrders (manufacture)
  # ----------------------------------------------------------------------

  @doc """
  Manufactures the primary candidate WorkOrder from the first item of a
  `xaas-sensing/1` document plus a dependent WorkOrder that requires the
  primary at standing ALIVE. Both are admitted by the kernel before return,
  so the returned digests are the canonical definition digests.
  """
  @spec manufacture(map(), map()) :: {:ok, map()} | refusal()
  def manufacture(sensing_doc, attrs) when is_map(sensing_doc) and is_map(attrs) do
    doc = strings(sensing_doc)
    attrs = strings(attrs)

    with :ok <- sensing_schema(doc),
         {:ok, [%{} = item | _]} <- sensing_items(doc),
         %{"head" => sensing_head} <- doc,
         :ok <- required(attrs, ~w(repository base_sha replay_tag)),
         :ok <- sha(:base_sha, attrs["base_sha"]),
         {:ok, primary} <- primary_work_order(doc, item, attrs) |> admit(),
         {:ok, dependent} <- dependent_work_order(primary, attrs) |> admit() do
      {:ok,
       %{
         "sensing_head" => sensing_head,
         "sensing_profile" => doc["profile"],
         "sensing_digest" => SemanticJira.digest(doc),
         "item_id" => item["id"],
         "generator" => @generator,
         "primary" => primary,
         "dependent" => dependent
       }}
    else
      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:refused_manufacture, {:unexpected, inspect(other)}}}
    end
  end

  def manufacture(_, _), do: {:error, {:refused_manufacture, :expected_maps}}

  defp sensing_schema(%{"schemaVersion" => @sensing_schema}), do: :ok

  defp sensing_schema(%{"schemaVersion" => other}),
    do: {:error, {:refused_manufacture, {:sensing_schema, other}}}

  defp sensing_schema(_), do: {:error, {:refused_manufacture, :missing_schema_version}}

  defp sensing_items(%{"items" => []}),
    do: {:error, {:refused_manufacture, :empty_sensing_items}}

  defp sensing_items(%{"items" => [item | _]}) when is_map(item), do: {:ok, [item]}
  defp sensing_items(_), do: {:error, {:refused_manufacture, :invalid_sensing_items}}

  defp primary_work_order(_doc, item, attrs) do
    %{
      "identity" => "CROWN-001",
      "title" => "Repair observed failing condition " <> item["id"],
      "description" => item["goal"],
      "subject" => "eds:crown-001-observed-condition",
      "repository" => attrs["repository"],
      "base_sha" => attrs["base_sha"],
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "SPECIFIED",
      "promotion_rule" =>
        "Standing may advance only from an independent exact-head court receipt " <>
          "for the same subject at the same base; sensed failure text is a signal, " <>
          "never evidence.",
      "replay_identity" => attrs["replay_tag"] <> ":CROWN-001",
      "required_courts" => ["eds-dod-exact-head"],
      "required_evidence" => ["local-execution-evidence", "receipt-evidence"],
      "acceptance" => ["crown-001-acceptance"],
      "falsifiers" => ["crown-001-falsifier"],
      "projections" => ["worker", "verification", "receipt"],
      "required_receipt_classes" => ["verification"],
      "path_scope" => path_scope(item),
      "authority_requirement" => "NONE"
    }
  end

  defp dependent_work_order(primary, attrs) do
    %{
      "identity" => "CROWN-002",
      "title" => "Receipt-bound regression guard for " <> primary["identity"],
      "description" =>
        "Encode a permanent regression guard for the repaired condition in " <>
          primary["identity"] <> "; eligibility requires the upstream receipt.",
      "subject" => "eds:crown-002-regression-guard",
      "repository" => primary["repository"],
      "base_sha" => attrs["base_sha"],
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "SPECIFIED",
      "promotion_rule" => primary["promotion_rule"],
      "replay_identity" => attrs["replay_tag"] <> ":CROWN-002",
      "required_courts" => ["eds-dod-exact-head"],
      "required_evidence" => ["local-execution-evidence", "receipt-evidence"],
      "acceptance" => ["crown-002-acceptance"],
      "falsifiers" => ["crown-002-falsifier"],
      "projections" => ["worker", "verification", "receipt"],
      "required_receipt_classes" => ["verification"],
      "path_scope" => primary["path_scope"],
      "authority_requirement" => "NONE",
      "dependencies" => [
        %{
          "upstream" => primary["identity"],
          "type" => "requiresSemanticIdentity",
          "required_standing" => "ALIVE"
        }
      ]
    }
  end

  defp path_scope(item) do
    case item["allowed_paths"] do
      paths when is_list(paths) and paths != [] -> paths
      _ -> ["src/eds/crown.py", "tests/test_w6_crown_seed.py"]
    end
  end

  # ----------------------------------------------------------------------
  # Canonical graph projection (manufacture path)
  # ----------------------------------------------------------------------

  @doc """
  Renders the deterministic Turtle section that appends the manufactured
  work orders (and their supporting nodes) to the canonical pack graph.
  """
  @spec render_turtle(map()) :: String.t()
  def render_turtle(%{"primary" => primary, "dependent" => dependent} = manufactured) do
    primary = strings(primary)
    dependent = strings(dependent)

    header = """

    # ── W6-A8 crown: closed-loop manufactured work orders ──────────────────
    # Manufactured by #{manufactured["generator"]} from sensing document
    # digest #{manufactured["sensing_digest"]} (schema #{@sensing_schema},
    # head #{manufactured["sensing_head"]}, item #{manufactured["item_id"]}).
    # The graph revision IS the manufacture path; no ticket was edited.
    """

    header <>
      render_court("crown-001", primary) <>
      render_court("crown-002", dependent) <>
      render_support("crown-001", primary) <>
      render_support("crown-002", dependent) <>
      render_edge("crown-002-from-001", "CROWN-002 dependency on CROWN-001") <>
      render_work_order(primary) <>
      render_work_order(dependent)
  end

  defp render_court(slug, wo) do
    """

    sj:court-#{slug} a sj:Court ;
        rdfs:label "#{wo["identity"]} exact-head court" ;
        dcterms:description "Independent exact-head court for #{wo["identity"]}; execution binds exact base, verifier/tool/environment identity, and durable receipt identity." .

    """
  end

  defp render_support(slug, wo) do
    """

    sj:acceptance-#{slug} a sj:AcceptanceCriterion ;
        rdfs:label "#{wo["identity"]} acceptance" ;
        dcterms:description "#{wo["title"]} is receipted at the exact head. Direct evidence is required; adjacency is insufficient." .

    sj:falsifier-#{slug} a sj:Falsifier ;
        rdfs:label "#{wo["identity"]} falsifier" ;
        dcterms:description "Subject, receipt, evidence, authority, replay, or contrary-observation mismatch falsifies promotion." .

    sj:run-#{slug}-court a sj:Action ;
        rdfs:label "Run #{wo["identity"]} court" ;
        dcterms:description "Execute the narrowest repository-native court; preserve failure evidence and never blindly rerun an unchanged failure." .

    sj:checkpoint-#{slug} a sj:Checkpoint ;
        rdfs:label "#{wo["identity"]} checkpoint" ;
        dcterms:description "Closed only by the reconciler recording a receipted standing transition." .

    """
  end

  defp render_edge(slug, label) do
    """

    sj:edge-#{slug} a sj:DependencyEdge ;
        rdfs:label "#{label}" ;
        dcterms:description "Typed semantic-identity dependency; runtime may strengthen it with exact receipt/digest identity." ;
        sj:dependencyType "requiresSemanticIdentity" ;
        sj:upstreamWorkOrder sj:crown-001 ;
        sj:requiredStanding "ALIVE" .

    """
  end

  defp render_work_order(wo) do
    slug = slug_of(wo["identity"])

    depends_on =
      case wo["dependencies"] do
        deps when is_list(deps) and deps != [] ->
          "    sj:dependsOn sj:edge-#{slug}-from-001 ;\n"

        _ ->
          ""
      end

    path_scope =
      wo["path_scope"]
      |> Enum.map_join(", ", &("\"" <> &1 <> "\""))

    """

    sj:#{slug} a sj:WorkOrder ;
        dcterms:identifier "#{wo["identity"]}" ;
        dcterms:title "#{escape(wo["title"])}" ;
        dcterms:description "#{escape(wo["description"])}" ;
        sj:repository "#{wo["repository"]}" ;
        sj:baseSha "#{wo["base_sha"]}" ;
        sj:subject "#{wo["subject"]}" ;\
    #{depends_on}    sj:pathScope #{path_scope} ;
        sj:standing "#{wo["standing"]}" ;
        sj:evidenceCeiling "#{wo["evidence_ceiling"]}" ;
        sj:authorityCeiling "CONSTRUCT" ;
        sj:authorityRequirement "NONE" ;
        sj:promotionRule "#{escape(wo["promotion_rule"])}" ;
        sj:replayIdentity "#{wo["replay_identity"]}" ;
        sj:requiresCourt sj:court-#{slug} ;
        sj:requiresEvidence sj:local-execution-evidence, sj:receipt-evidence ;
        sj:requiresReceiptClass "verification" ;
        sj:acceptance sj:acceptance-#{slug} ;
        sj:falsifier sj:falsifier-#{slug} ;
        sj:projection sj:projection-worker, sj:projection-verification, sj:projection-receipt ;
        sj:nextAction sj:run-#{slug}-court ;
        sj:nextCheckpoint sj:checkpoint-#{slug} .
    """
  end

  @doc "Appends rendered crown Turtle to the canonical graph file text."
  @spec append_to_graph(String.t(), String.t()) :: String.t()
  def append_to_graph(graph_text, turtle), do: graph_text <> turtle

  # ----------------------------------------------------------------------
  # Graph -> kernel work orders (extraction for frontier selection)
  # ----------------------------------------------------------------------

  @doc """
  Extracts every WorkOrder from the canonical graph as an admitted
  kernel-shaped map. Returns `{:ok, %{identity => admitted}}` or a refusal.
  """
  @spec extract_work_orders(String.t()) :: {:ok, map()} | refusal()
  def extract_work_orders(graph_path) when is_binary(graph_path) do
    graph = Ontology.load!(graph_path)

    scalars =
      Query.run(graph, """
      PREFIX sj: <#{@sj}>
      PREFIX dcterms: <#{@dcterms}>
      SELECT ?iri ?id ?title ?description ?repository ?base_sha ?candidate_sha
             ?subject ?standing ?evidence_ceiling ?promotion_rule ?replay_identity
             ?authority_requirement WHERE {
        ?iri a sj:WorkOrder ;
             dcterms:identifier ?id ;
             dcterms:title ?title ;
             dcterms:description ?description ;
             sj:repository ?repository ;
             sj:baseSha ?base_sha ;
             sj:subject ?subject ;
             sj:standing ?standing ;
             sj:evidenceCeiling ?evidence_ceiling ;
             sj:promotionRule ?promotion_rule ;
             sj:replayIdentity ?replay_identity ;
             sj:authorityRequirement ?authority_requirement .
        OPTIONAL { ?iri sj:candidateSha ?candidate_sha . }
      }
      """)

    extracted =
      Map.new(scalars, fn row ->
        iri = row["iri"]

        wo =
          %{
            "identity" => row["id"],
            "title" => row["title"],
            "description" => row["description"],
            "repository" => row["repository"],
            "base_sha" => row["base_sha"],
            "candidate_sha" => row["candidate_sha"],
            "subject" => row["subject"],
            "standing" => row["standing"],
            "evidence_ceiling" => row["evidence_ceiling"],
            "promotion_rule" => row["promotion_rule"],
            "replay_identity" => row["replay_identity"],
            "authority_requirement" => row["authority_requirement"],
            "required_courts" => iri_objects(graph, iri, @sj <> "requiresCourt"),
            "required_evidence" => iri_objects(graph, iri, @sj <> "requiresEvidence"),
            "acceptance" => iri_objects(graph, iri, @sj <> "acceptance"),
            "falsifiers" => iri_objects(graph, iri, @sj <> "falsifier"),
            "required_receipt_classes" => literal_values(graph, iri, @sj <> "requiresReceiptClass"),
            "path_scope" => literal_values(graph, iri, @sj <> "pathScope"),
            "projections" => projection_types(graph, iri),
            "dependencies" => dependency_edges(graph, iri)
          }

        {row["id"], Map.put(wo, "iri", iri)}
      end)

    admitted =
      Map.new(extracted, fn {id, wo} ->
        case SemanticJira.admit_work_order(wo) do
          {:ok, admitted_wo} -> {id, Map.put(admitted_wo, "iri", wo["iri"])}
          {:error, reason} -> throw({:refused_extraction, id, reason})
        end
      end)

    {:ok, admitted}
  catch
    {:refused_extraction, id, reason} -> {:error, {:refused_extraction, id, reason}}
  end

  defp description(graph, iri), do: RDF.Graph.description(graph, RDF.iri(iri))

  defp iri_objects(graph, iri, predicate) do
    graph
    |> description(iri)
    |> RDF.Description.get(predicate, [])
    |> Enum.map(fn
      %RDF.IRI{} = object -> local_name(RDF.IRI.to_string(object))
      %RDF.Literal{} = literal -> value(literal)
      other -> to_string(other)
    end)
    |> Enum.sort()
  end

  defp literal_values(graph, iri, predicate) do
    graph
    |> description(iri)
    |> RDF.Description.get(predicate, [])
    |> Enum.map(&value/1)
    |> Enum.sort()
  end

  defp projection_types(graph, iri) do
    graph
    |> description(iri)
    |> RDF.Description.get(@sj <> "projection", [])
    |> Enum.flat_map(fn projection_iri ->
      graph
      |> description(RDF.IRI.to_string(projection_iri))
      |> RDF.Description.get(@sj <> "projectionType", [])
      |> Enum.map(&value/1)
    end)
    |> Enum.sort()
  end

  defp dependency_edges(graph, iri) do
    graph
    |> description(iri)
    |> RDF.Description.get(@sj <> "dependsOn", [])
    |> Enum.map(fn edge_iri ->
      edge = description(graph, RDF.IRI.to_string(edge_iri))

      upstream =
        edge
        |> RDF.Description.get(@sj <> "upstreamWorkOrder", [])
        |> case do
          [%RDF.IRI{} = first | _] -> local_name(RDF.IRI.to_string(first))
          _ -> nil
        end

      type =
        edge
        |> RDF.Description.get(@sj <> "dependencyType", [])
        |> case do
          [first | _] -> value(first)
          _ -> nil
        end

      required_standing =
        edge
        |> RDF.Description.get(@sj <> "requiredStanding", [])
        |> case do
          [first | _] -> value(first)
          _ -> nil
        end

      %{"upstream" => upstream, "type" => type}
      |> maybe_put("required_standing", required_standing)
    end)
    |> Enum.sort_by(& &1["upstream"])
  end

  defp local_name(iri_string) do
    case String.split(iri_string, "#") do
      [_prefix, local] -> String.upcase(local)
      _ -> iri_string |> String.split("/") |> List.last()
    end
  end

  defp value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal) |> to_string()
  defp value(other), do: to_string(other)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ----------------------------------------------------------------------
  # Frontier (delegating selection; pack graph gate 050 is the graph twin)
  # ----------------------------------------------------------------------

  @doc "Kernel frontier over extracted work orders."
  @spec frontier([map()], map()) :: %{eligible: [map()], blocked: [map()]}
  def frontier(work_orders, evidence_by_id \\ %{}),
    do: SemanticJira.frontier(work_orders, evidence_by_id)

  # ----------------------------------------------------------------------
  # XaaS execution descriptor projection
  # ----------------------------------------------------------------------

  @doc """
  Projects one admitted work order into the exact execution descriptor
  contract consumed by `Xaas.Ultracode.SemanticWork.admit/1`.
  """
  @spec descriptor(map(), String.t(), map()) :: {:ok, map()} | refusal()
  def descriptor(wo, graph_digest, attrs) when is_map(wo) and is_binary(graph_digest) do
    attrs = strings(attrs)

    with :ok <- required(attrs, ~w(goal provider verifier_suite execution_repo_alias)),
         :ok <- digest(graph_digest),
         iri <- Map.fetch!(wo, "iri") do
      {:ok,
       %{
         "work_order_iri" => iri,
         "checkpoint_iri" => iri <> "/checkpoint",
         "graph_digest" => graph_digest,
         "repository_identity" => wo["repository"],
         "execution_repo_alias" => attrs["execution_repo_alias"],
         "base_sha" => wo["base_sha"],
         "goal" => attrs["goal"],
         "provider" => attrs["provider"],
         "verifier_suite" => attrs["verifier_suite"],
         "execution_policy" => attrs["execution_policy"] || "autonomic_wave_attempt",
         "standing" => wo["standing"],
         "dependencies" => xaas_dependencies(wo, attrs)
       }}
    else
      :error -> {:error, {:refused_descriptor, :missing_iri}}
      {:error, reason} -> {:error, {:refused_descriptor, reason}}
    end
  end

  def descriptor(_, _, _), do: {:error, {:refused_descriptor, :expected_map_and_digest}}

  defp xaas_dependencies(wo, attrs) do
    evidence = strings(Map.get(attrs, "dependency_evidence", %{}))

    Enum.flat_map(wo["dependencies"] || [], fn dep ->
      case evidence[dep["upstream"]] do
        %{"receipt_digest" => receipt_digest, "receipt_iri" => receipt_iri} ->
          [
            %{
              "work_order_iri" => dep["upstream"],
              "required_standing" => "ALIVE",
              "observed_standing" => "ALIVE",
              "receipt_iri" => receipt_iri,
              "receipt_digest" => receipt_digest
            }
          ]

        _ ->
          []
      end
    end)
  end

  # ----------------------------------------------------------------------
  # Reconciler projection: receipted, stepwise standing transitions
  # ----------------------------------------------------------------------

  @doc """
  Renders the reconciler's graph revision for the primary work order: the
  durable `sj:Receipt`, the two lawful stepwise `sj:StandingTransition`
  nodes (UNKNOWN -> PARTIAL_ALIVE -> ALIVE, each produced by the kernel's
  `promote/3` calculus), given the exact-head verification `evidence`.

  `receipt_facts` requires: work_order_digest, subject_sha, candidate_sha,
  receipt_iri, receipt_digest, receipt_class.
  """
  @spec transition_turtle(map(), map(), map()) :: {:ok, String.t()} | refusal()
  def transition_turtle(wo, evidence, receipt_facts)
      when is_map(wo) and is_map(evidence) and is_map(receipt_facts) do
    evidence = strings(evidence)
    receipt_facts = strings(receipt_facts)
    wo = strings(wo)
    slug = slug_of(wo["identity"])

    with :ok <-
           required(receipt_facts, ~w(work_order_digest subject_sha candidate_sha receipt_iri receipt_digest receipt_class)),
         :ok <- digest(receipt_facts["work_order_digest"]),
         :ok <- sha(:subject_sha, receipt_facts["subject_sha"]),
         :ok <- sha(:candidate_sha, receipt_facts["candidate_sha"]),
         :ok <- digest(receipt_facts["receipt_digest"]),
         {:ok, _hop1} <- SemanticJira.promote(wo, "PARTIAL_ALIVE", evidence),
         # The kernel digest covers standing, so each hop re-binds the
         # evidence to the digest of the exact order state being promoted.
         {:ok, partial} <- SemanticJira.admit_work_order(%{wo | "standing" => "PARTIAL_ALIVE"}),
         {:ok, _hop2} <-
           SemanticJira.promote(
             partial,
             "ALIVE",
             Map.put(evidence, "work_order_digest", partial["work_order_digest"])
           ) do
      {:ok,
       """

       # ── W6-A8 crown reconciler: receipted stepwise transition ────────────
       # Receipt #{receipt_facts["receipt_iri"]} digest #{receipt_facts["receipt_digest"]}
       sj:receipt-#{slug} a sj:Receipt ;
           sj:workOrderDigest "#{receipt_facts["work_order_digest"]}" ;
           sj:repository "#{wo["repository"]}" ;
           sj:baseSha "#{wo["base_sha"]}" ;
           sj:subjectSha "#{receipt_facts["subject_sha"]}" ;
           sj:replayIdentity "#{wo["replay_identity"]}" ;
           sj:receiptClass "#{receipt_facts["receipt_class"]}" ;
           rdfs:label "Durable fabric receipt for #{wo["identity"]}" .

       sj:transition-#{slug}-partial a sj:StandingTransition ;
           sj:fromStanding "UNKNOWN" ;
           sj:toStanding "PARTIAL_ALIVE" ;
           rdfs:label "#{wo["identity"]} UNKNOWN to PARTIAL_ALIVE" .

       sj:transition-#{slug}-alive a sj:StandingTransition ;
           sj:fromStanding "PARTIAL_ALIVE" ;
           sj:toStanding "ALIVE" ;
           rdfs:label "#{wo["identity"]} PARTIAL_ALIVE to ALIVE" .
       """}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def transition_turtle(_, _, _), do: {:error, {:refused_transition, :expected_maps}}

  @doc """
  Produces the ALIVE-state graph text: rewrites the named work order's
  `sj:standing` to ALIVE and binds candidateSha/subjectSha/receipt. The
  ALIVE integrity constraints of the admission court require exactly these
  bindings; deterministic surgery confined to the named block.
  """
  @spec promote_graph_text(String.t(), map(), map()) :: {:ok, String.t()} | refusal()
  def promote_graph_text(graph_text, wo, receipt_facts) do
    wo = strings(wo)
    slug = slug_of(wo["identity"])
    iri = "sj:#{slug} a sj:WorkOrder"

    result =
      rewrite_block(
        String.split(graph_text, "\n"),
        iri,
        "sj:standing \"UNKNOWN\" ;",
        "sj:nextCheckpoint",
        "        sj:standing \"ALIVE\" ;",
        [
          "        sj:candidateSha \"#{receipt_facts["candidate_sha"]}\" ;",
          "        sj:subjectSha \"#{receipt_facts["subject_sha"]}\" ;",
          "        sj:receipt sj:receipt-#{slug} ;"
        ],
        :outside
      )

    case result do
      {lines, :done} ->
        text = Enum.join(lines, "\n")

        if String.contains?(text, "sj:standing \"ALIVE\"") and
             String.contains?(text, "sj:receipt sj:receipt-#{slug}") do
          {:ok, text}
        else
          {:error, {:refused_promotion_text, {:rewrite_failed, wo["identity"]}}}
        end

      {_, state} ->
        {:error, {:refused_promotion_text, {:incomplete_block, wo["identity"], state}}}
    end
  end

  defp rewrite_block([], _iri, _standing, _anchor, _new_standing, _inserts, state),
    do: {[], state}

  defp rewrite_block([line | rest], iri, standing, anchor, new_standing, inserts, state) do
    trimmed = String.trim(line)

    cond do
      trimmed |> String.starts_with?(iri) ->
        {rest_lines, final_state} =
          rewrite_block(rest, iri, standing, anchor, new_standing, inserts, :inside)

        {[line | rest_lines], final_state}

      state == :inside and trimmed == standing ->
        {rest_lines, final_state} =
          rewrite_block(rest, iri, standing, anchor, new_standing, inserts, :inside)

        {[new_standing | rest_lines], final_state}

      state == :inside and String.starts_with?(trimmed, anchor) ->
        {rest_lines, final_state} =
          rewrite_block(rest, iri, standing, anchor, new_standing, inserts, :done)

        {inserts ++ [line | rest_lines], final_state}

      true ->
        {rest_lines, final_state} =
          rewrite_block(rest, iri, standing, anchor, new_standing, inserts, state)

        {[line | rest_lines], final_state}
    end
  end

  # ----------------------------------------------------------------------
  # Shared helpers
  # ----------------------------------------------------------------------

  defp slug_of("CROWN-001"), do: "crown-001"
  defp slug_of("CROWN-002"), do: "crown-002"

  defp slug_of(other) do
    other
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp required(map, keys) do
    case Enum.find(keys, &blank?(map[&1])) do
      nil -> :ok
      key -> {:error, {:missing_required_field, key}}
    end
  end

  defp blank?(value), do: value in [nil, "", []]

  defp sha(field, value) do
    if is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value),
      do: :ok,
      else: {:error, {:invalid_sha, field, value}}
  end

  defp digest(value) do
    if is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value),
      do: :ok,
      else: {:error, {:invalid_digest, value}}
  end

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp strings(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), strings(v)} end)

  defp strings(value) when is_list(value), do: Enum.map(value, &strings/1)
  defp strings(value), do: value

  defp admit(wo), do: SemanticJira.admit_work_order(wo)
end
