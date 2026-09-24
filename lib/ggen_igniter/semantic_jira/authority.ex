defmodule GgenIgniter.SemanticJira.Authority do
  @moduledoc """
  Origin-authority admission and verification (resolution R5).

  The law: every `sj:WorkOrder` carries `sj:originAuthority` — a REQUIRED
  IRI — that resolves to an ADMITTED `sj:CodeWorkAuthority` node in the
  canonical graph. Typed is not admitted: a node is admitted only when it
  carries an `sj:admissionDigest` (`"sha256:<64 hex>"`) that recomputes
  byte-equal over the canonical graph with the digest predicate excluded —
  the same self-referential-exclusion construction PR-001 uses to stamp
  proposition `admissionDigest`s. `verify_origin/3` refuses fresh
  self-declared authorities (an origin the canonical graph does not admit)
  and forged digests (a candidate restatement whose digest set differs
  from canonical).

  Nothing here grants authority, performs DO, or promotes standing: the
  module computes digests, stamps them onto typed authority nodes, and
  refuses when an order's origin binding does not resolve to an admitted
  authority. NO SHACL validation runs inside `admit/2` — callers run
  their court first.
  """

  alias GgenIgniter.Digest

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @rdf_type RDF.type()

  @admission_digest_context "code-work-authority:v1"

  @authority_classes [
    RDF.iri(@sj <> "StrategicObjective"),
    RDF.iri(@sj <> "GoalCheckpoint")
  ]

  @type digest :: String.t()
  @type origin_refusal ::
          :order_absent
          | :origin_authority_missing
          | {:ambiguous_origin_authority, [String.t()]}
          | {:authority_not_admitted, String.t()}
          | {:authority_digest_mismatch, String.t()}
          | {:authority_type_mismatch, String.t()}

  @doc """
  The admission digest of the authority node `iri` over `graph`.

  `Digest.sha256/1` over the context string, the node IRI, and the sorted
  N-Triples serialization of the node's description with ALL
  `sj:admissionDigest` predicates deleted — the exclusion law that makes
  stamping idempotent (recomputing over a stamped graph returns the same
  digest). A node absent from the graph digests over the empty statement
  set; callers verify presence.
  """
  @spec admission_digest(RDF.Graph.t(), RDF.IRI.t() | String.t()) :: digest()
  def admission_digest(graph, %RDF.IRI{} = iri), do: node_digest(graph, iri)

  def admission_digest(graph, iri) when is_binary(iri), do: node_digest(graph, RDF.iri(iri))

  @doc """
  Stamps `sj:admissionDigest` onto every typed authority node in `graph`
  and returns `{:ok, stamped_graph, report}` with `%{iri_string => digest}`.

  Authority nodes are descriptions typed `sj:StrategicObjective` or
  `sj:GoalCheckpoint` (`:classes` override). Each digest is computed over
  the pre-stamp node description (existing `sj:admissionDigest` predicates
  deleted), then written back with replace-any semantics, so admission is
  idempotent. Refuses when the graph carries no typed authority node.
  """
  @spec admit(RDF.Graph.t(), keyword()) ::
          {:ok, RDF.Graph.t(), %{String.t() => digest()}}
          | {:error, {:refused_authority_admission, :no_typed_authority_node}}
  def admit(graph, opts \\ []) do
    classes = Keyword.get(opts, :classes, @authority_classes)

    case typed_nodes(graph, classes) do
      [] ->
        {:error, {:refused_authority_admission, :no_typed_authority_node}}

      nodes ->
        {stamped, report} = Enum.reduce(nodes, {graph, %{}}, &stamp/2)
        {:ok, stamped, report}
    end
  end

  @doc """
  Verifies that `order_iri`'s `sj:originAuthority` in `candidate_graph`
  resolves to an admitted authority node of `canonical_graph`.

  The order must exist in the candidate graph and carry exactly one
  origin authority; that origin must be present in the canonical graph,
  typed as an authority class, and carry an `sj:admissionDigest` (typed
  is not admitted). A candidate restatement of the origin node must agree
  with canonical on both the `sj:admissionDigest` set (the forged-digest
  refusal) and the `rdf:type` set.
  """
  @spec verify_origin(RDF.Graph.t(), RDF.Graph.t(), RDF.IRI.t() | String.t()) ::
          :ok | {:error, {:refused_origin, origin_refusal()}}
  def verify_origin(candidate_graph, canonical_graph, order_iri) do
    with {:ok, order} <- fetch_order(candidate_graph, to_iri(order_iri)),
         {:ok, origin} <- origin_authority(order) do
      admitted_origin?(candidate_graph, canonical_graph, origin)
    end
  end

  defp fetch_order(candidate_graph, order_iri) do
    case RDF.Graph.get(candidate_graph, order_iri) do
      nil -> {:error, {:refused_origin, :order_absent}}
      order -> {:ok, order}
    end
  end

  defp origin_authority(order) do
    case RDF.Description.get(order, sj("originAuthority"), []) do
      [] ->
        {:error, {:refused_origin, :origin_authority_missing}}

      [origin] ->
        {:ok, origin}

      origins ->
        {:error,
         {:refused_origin,
          {:ambiguous_origin_authority, origins |> Enum.map(&literal/1) |> Enum.sort()}}}
    end
  end

  defp admitted_origin?(candidate_graph, canonical_graph, origin) do
    canonical = RDF.Graph.get(canonical_graph, origin)

    if admitted?(canonical) do
      restatement_check(RDF.Graph.get(candidate_graph, origin), canonical, origin)
    else
      {:error, {:refused_origin, {:authority_not_admitted, literal(origin)}}}
    end
  end

  # Typed is not admitted: the canonical origin must exist, be typed as an
  # authority class, and carry at least one admission digest.
  defp admitted?(nil), do: false

  defp admitted?(description) do
    typed?(description, @authority_classes) and
      value_set(description, sj("admissionDigest")) != []
  end

  # A candidate that does not restate the origin node carries no claim
  # about it — canonical stands. A restatement must agree with canonical
  # on both the `sj:admissionDigest` set (the forged-digest refusal) and
  # the `rdf:type` set; comparisons are over sorted lexical forms.
  defp restatement_check(nil, _canonical, _origin), do: :ok

  defp restatement_check(candidate, canonical, origin) do
    cond do
      value_set(candidate, sj("admissionDigest")) != value_set(canonical, sj("admissionDigest")) ->
        {:error, {:refused_origin, {:authority_digest_mismatch, literal(origin)}}}

      value_set(candidate, @rdf_type) != value_set(canonical, @rdf_type) ->
        {:error, {:refused_origin, {:authority_type_mismatch, literal(origin)}}}

      true ->
        :ok
    end
  end

  defp value_set(description, predicate) do
    description
    |> RDF.Description.get(predicate, [])
    |> Enum.map(&literal/1)
    |> Enum.sort()
  end

  defp stamp({iri, description}, {graph, report}) do
    stripped = RDF.Description.delete_predicates(description, sj("admissionDigest"))
    digest = node_digest(graph, iri)

    stamped =
      graph
      |> RDF.Graph.delete_descriptions(iri)
      |> RDF.Graph.add(
        RDF.Description.add(stripped, {sj("admissionDigest"), RDF.literal(digest)})
      )

    {stamped, Map.put(report, RDF.IRI.to_string(iri), digest)}
  end

  defp typed_nodes(graph, classes) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.filter(&typed?(&1, classes))
    |> Enum.map(&{&1.subject, &1})
  end

  defp typed?(description, classes),
    do: Enum.any?(classes, &(&1 in RDF.Description.get(description, @rdf_type, [])))

  defp node_digest(graph, iri) do
    description =
      graph
      |> RDF.Graph.get(iri, RDF.Description.new(iri))
      |> RDF.Description.delete_predicates(sj("admissionDigest"))

    Digest.sha256(
      @admission_digest_context <>
        "\n" <> RDF.IRI.to_string(iri) <> "\n" <> sorted_ntriples(RDF.Graph.new(description))
    )
  end

  defp sorted_ntriples(graph) do
    graph
    |> RDF.NTriples.write_string!()
    |> String.split("\n", trim: true)
    |> Enum.sort()
    |> Enum.map_join("", &(&1 <> "\n"))
  end

  defp to_iri(%RDF.IRI{} = iri), do: iri
  defp to_iri(iri) when is_binary(iri), do: RDF.iri(iri)

  defp sj(local), do: RDF.iri(@sj <> local)

  defp literal(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp literal(%RDF.Literal{} = literal), do: RDF.Literal.lexical(literal)
  defp literal(other), do: to_string(other)
end
