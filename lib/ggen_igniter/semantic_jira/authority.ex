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
  authority.

  `index/1` + `resolve/2` are the ONE origin law: `verify_origin/3`
  (observation), `SemanticJira.frontier/4` (selection, AC-04) and
  `Reconciler.reconcile/4` (promotion) all resolve an origin through them, so
  an admitted origin is one whose digest RECOMPUTES, not merely one that
  states a well-formed digest. `canonical_index/1` is the default index. NO SHACL validation runs inside `admit/2` — callers run
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

  # A node typed as prose/proposition is never code-work authority, whatever
  # else it is typed as (ADR-012).
  @prose_classes [
    RDF.iri(@sj <> "Proposition"),
    RDF.iri(@sj <> "ProseObservation")
  ]

  @canonical_ontology ["priv", "ggen", "semantic-jira-pack", "ontology.ttl"]

  @type digest :: String.t()
  @type origin_refusal ::
          :order_absent
          | :origin_authority_missing
          | {:ambiguous_origin_authority, [String.t()]}
          | {:authority_not_admitted, String.t()}
          | {:authority_digest_mismatch, String.t()}
          | {:authority_type_mismatch, String.t()}

  @typedoc """
  The admission index of an authority graph: every node typed
  `sj:StrategicObjective`/`sj:GoalCheckpoint` is either `admitted` (IRI ->
  its recomputed digest) or `refused` (IRI -> typed refusal). An IRI in
  neither map is not an authority node at all.
  """
  @type index :: %{
          admitted: %{String.t() => digest()},
          refused: %{String.t() => origin_refusal()}
        }

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
  The admission index of `graph` (the one origin law shared by frontier
  selection, reconciliation and `verify_origin/3`).

  Every node typed `sj:StrategicObjective` or `sj:GoalCheckpoint` is judged:

    * also typed `sj:Proposition`/`sj:ProseObservation` -> refused
      `{:authority_type_mismatch, iri}` (prose is never authority);
    * no `sj:admissionDigest` -> refused `{:authority_not_admitted, iri}`
      (typed is not admitted);
    * more than one digest, or a digest that does not RECOMPUTE byte-equal
      via `admission_digest/2` over `graph` -> refused
      `{:authority_digest_mismatch, iri}` (an edited node under a kept
      digest, or a `sha256:PENDING-*` placeholder);
    * otherwise admitted with its digest.
  """
  @spec index(RDF.Graph.t()) :: index()
  def index(%RDF.Graph{} = graph) do
    graph
    |> typed_nodes(@authority_classes)
    |> Enum.reduce(%{admitted: %{}, refused: %{}}, fn {iri, description}, acc ->
      key = RDF.IRI.to_string(iri)

      case judge(graph, iri, description) do
        {:ok, digest} -> put_in(acc, [:admitted, key], digest)
        {:error, refusal} -> put_in(acc, [:refused, key], refusal)
      end
    end)
  end

  defp judge(graph, iri, description) do
    key = RDF.IRI.to_string(iri)

    if typed?(description, @prose_classes),
      do: {:error, {:authority_type_mismatch, key}},
      else: judge_digest(value_set(description, sj("admissionDigest")), graph, iri, key)
  end

  defp judge_digest([], _graph, _iri, key), do: {:error, {:authority_not_admitted, key}}

  defp judge_digest([stated], graph, iri, key) do
    if stated == node_digest(graph, iri),
      do: {:ok, stated},
      else: {:error, {:authority_digest_mismatch, key}}
  end

  defp judge_digest(_several, _graph, _iri, key), do: {:error, {:authority_digest_mismatch, key}}

  @doc """
  Resolves `origin` (an IRI string) against an admission `index/1`:
  `{:ok, digest}` when admitted, the node's typed refusal when it is a
  refused authority node, and `{:authority_not_admitted, origin}` when the
  IRI is not an authority node of the graph at all (a proposition, a prose
  observation, a fresh IRI).
  """
  @spec resolve(index(), String.t() | RDF.IRI.t()) ::
          {:ok, digest()} | {:error, {:refused_origin, origin_refusal()}}
  def resolve(index, %RDF.IRI{} = origin), do: resolve(index, RDF.IRI.to_string(origin))

  def resolve(%{admitted: admitted, refused: refused}, origin) when is_binary(origin) do
    case admitted do
      %{^origin => digest} ->
        {:ok, digest}

      _ ->
        {:error, {:refused_origin, Map.get(refused, origin, {:authority_not_admitted, origin})}}
    end
  end

  @doc """
  The admission index of the canonical semantic-jira-pack ontology
  (`priv/ggen/semantic-jira-pack/ontology.ttl` of the `:ggen_igniter` app),
  or of `opts[:path]`.

  The file is read on every call and the parsed index is cached in
  `:persistent_term` keyed by the sha256 of the file BYTES (never by path),
  so an edited file is re-indexed, never served stale. An unreadable or
  unparseable file is `{:error, {:authority_index_unavailable, path, reason}}`
  -- callers fail closed.
  """
  @spec canonical_index(keyword()) ::
          {:ok, index()} | {:error, {:authority_index_unavailable, Path.t(), term()}}
  def canonical_index(opts \\ []) do
    path = Keyword.get_lazy(opts, :path, &canonical_path/0)

    with {:ok, bytes} <- read_authority(path) do
      key = {__MODULE__, :index, Digest.sha256(bytes)}

      case :persistent_term.get(key, nil) do
        nil -> parse_and_cache(bytes, path, key)
        index -> {:ok, index}
      end
    end
  end

  @doc """
  The admission index named by `opts[:authority]`, the one option every
  selection/promotion surface takes: an `index/1` map (used as is), an
  `RDF.Graph` (indexed), or a Turtle path (`canonical_index(path: path)`).
  Absent, the canonical index. Anything else fails closed.
  """
  @spec index_from(keyword()) ::
          {:ok, index()} | {:error, {:authority_index_unavailable, Path.t() | nil, term()}}
  def index_from(opts) do
    case Keyword.get(opts, :authority) do
      nil -> canonical_index()
      %RDF.Graph{} = graph -> {:ok, index(graph)}
      %{admitted: _, refused: _} = index -> {:ok, index}
      path when is_binary(path) -> canonical_index(path: path)
      other -> {:error, {:authority_index_unavailable, nil, {:invalid_authority, inspect(other)}}}
    end
  end

  @doc "Path of the canonical semantic-jira-pack ontology inside the app."
  @spec canonical_path() :: Path.t()
  def canonical_path, do: Path.join([Application.app_dir(:ggen_igniter) | @canonical_ontology])

  defp read_authority(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:authority_index_unavailable, path, reason}}
    end
  end

  defp parse_and_cache(bytes, path, key) do
    case RDF.Turtle.read_string(bytes) do
      {:ok, graph} ->
        index = index(graph)
        :persistent_term.put(key, index)
        {:ok, index}

      {:error, reason} ->
        {:error, {:authority_index_unavailable, path, inspect(reason)}}
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

  # The same law as frontier selection: the origin must RESOLVE in the
  # canonical graph's admission index (typed, not prose, one digest that
  # recomputes), then a candidate restatement must agree with canonical.
  defp admitted_origin?(candidate_graph, canonical_graph, origin) do
    with {:ok, _digest} <- resolve(index(canonical_graph), literal(origin)) do
      restatement_check(
        RDF.Graph.get(candidate_graph, origin),
        RDF.Graph.get(canonical_graph, origin),
        origin
      )
    end
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
