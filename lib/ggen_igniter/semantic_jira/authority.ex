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

  Trust-root pin law (G1, v26.9.25 hardening): a recomputing digest is an
  UNKEYED content hash, so a caller-supplied graph can self-stamp any node.
  Admission therefore also requires the `(iri, digest)` pair to be pinned
  by an `sj:AuthorityTrustRoot` node of the CANONICAL semantic-jira-pack
  ontology (`trust_roots/0`, never a caller path). Every index a
  selection/promotion surface resolves through `index_from/1` -- the
  canonical index, a caller `RDF.Graph`, a Turtle path, or a ready-made
  `index/1` map (revalidated) -- passes through `pin/2`: an admitted node
  whose pair is not pinned is refused `{:authority_not_pinned, iri}`.
  `require_origin/2` is the one guard every entry point (lease request,
  execution package, DO intent, promotion, transition, repair, A2A task)
  runs. `admit/2` STAMPS only; a stamped node is admitted only when pinned.
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

  @trust_root_class RDF.iri(@sj <> "AuthorityTrustRoot")
  @digest_pattern ~r/\Asha256:[0-9a-f]{64}\z/

  @type digest :: String.t()
  @type origin_refusal ::
          :order_absent
          | :origin_authority_missing
          | {:ambiguous_origin_authority, [String.t()]}
          | {:authority_not_admitted, String.t()}
          | {:authority_digest_mismatch, String.t()}
          | {:authority_type_mismatch, String.t()}
          | {:authority_not_pinned, String.t()}
          | {:authority_digest_invalid, String.t()}
          | {:authority_index_conflict, String.t()}
          | {:authority_index_unavailable, Path.t() | nil, term()}

  @typedoc """
  The admission index of an authority graph: every node typed
  `sj:StrategicObjective`/`sj:GoalCheckpoint` is either `admitted` (IRI ->
  its recomputed digest) or `refused` (IRI -> typed refusal). An IRI in
  neither map is not an authority node at all.
  """
  @type index :: %{
          admitted: %{String.t() => digest()},
          refused: %{String.t() => origin_refusal()},
          source_graph: RDF.Graph.t(),
          source_digest: digest()
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
    judged =
      graph
      |> typed_nodes(@authority_classes)
      |> Enum.reduce(%{admitted: %{}, refused: %{}}, fn {iri, description}, acc ->
        key = RDF.IRI.to_string(iri)

        case judge(graph, iri, description) do
          {:ok, digest} -> put_in(acc, [:admitted, key], digest)
          {:error, refusal} -> put_in(acc, [:refused, key], refusal)
        end
      end)

    Map.merge(judged, %{
      source_graph: graph,
      source_digest: graph_digest(graph)
    })
  end

  @doc """
  Stable digest of the complete authority source graph.

  Unlike an admission digest (which covers one authority description with the
  self-referential digest predicate excluded), this digest binds a reusable
  index to the complete sorted N-Triples source from which it was recomputed.
  """
  @spec graph_digest(RDF.Graph.t()) :: digest()
  def graph_digest(%RDF.Graph{} = graph) do
    Digest.sha256("authority-index:v1\n" <> sorted_ntriples(graph))
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
    case {Map.fetch(admitted, origin), Map.fetch(refused, origin)} do
      {{:ok, _digest}, {:ok, _refusal}} ->
        {:error, {:refused_origin, {:authority_index_conflict, origin}}}

      {{:ok, digest}, :error} ->
        if is_binary(digest) and Regex.match?(@digest_pattern, digest),
          do: {:ok, digest},
          else: {:error, {:refused_origin, {:authority_digest_invalid, origin}}}

      {:error, {:ok, refusal}} ->
        {:error, {:refused_origin, refusal}}

      {:error, :error} ->
        {:error, {:refused_origin, {:authority_not_admitted, origin}}}
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
  The PINNED admission index named by `opts[:authority]`, the one option
  every selection/promotion surface takes: an `index/1` map (revalidated),
  an `RDF.Graph` (indexed), or a Turtle path (`canonical_index(path: path)`).
  Absent, the canonical index. Every form passes through `pin/2` against
  `trust_roots/0`. Anything else fails closed.
  """
  @spec index_from(keyword()) ::
          {:ok, index()} | {:error, {:authority_index_unavailable, Path.t() | nil, term()}}
  def index_from(opts) do
    with {:ok, unpinned} <- unpinned_index(Keyword.get(opts, :authority)),
         {:ok, pins} <- trust_roots() do
      {:ok, pin(unpinned, pins)}
    end
  end

  defp unpinned_index(nil), do: canonical_index()
  defp unpinned_index(%RDF.Graph{} = graph), do: {:ok, index(graph)}
  defp unpinned_index(path) when is_binary(path), do: canonical_index(path: path)

  defp unpinned_index(%{
         admitted: admitted,
         refused: refused,
         source_graph: %RDF.Graph{} = source_graph,
         source_digest: source_digest
       })
       when is_map(admitted) and is_map(refused) and is_binary(source_digest) do
    recomputed = index(source_graph)

    cond do
      source_digest != recomputed.source_digest ->
        {:error,
         {:authority_index_unavailable, nil, :precomputed_authority_source_digest_mismatch}}

      presented_matches?(admitted, refused, recomputed) ->
        {:ok, recomputed}

      true ->
        {:error, {:authority_index_unavailable, nil, :precomputed_authority_index_mismatch}}
    end
  end

  # A presented precomputed index is honored only when it is the exact
  # deterministic derivation of its own source graph: either the raw
  # `index/1` output or its `pin/2` projection against the canonical trust
  # roots -- the shape `pinned_goal_index/1` (bootstrap) presents and hands
  # back through `index_from/1`. Anything else (a forged admitted/refused
  # entry, a stale pin) still fails closed with
  # `:precomputed_authority_index_mismatch`.
  defp presented_matches?(admitted, refused, recomputed) do
    raw_match? = admitted == recomputed.admitted and refused == recomputed.refused

    raw_match? or pinned_match?(admitted, refused, recomputed)
  end

  defp pinned_match?(admitted, refused, recomputed) do
    case trust_roots() do
      {:ok, pins} ->
        pinned = pin(recomputed, pins)
        admitted == pinned.admitted and refused == pinned.refused

      {:error, _unavailable} ->
        false
    end
  end

  # Legacy bare maps carry no source graph, so their admitted claims can
  # never be recomputed. Preserve them only as a fail-closed refusal carrier:
  # every claimed admission becomes authority_not_pinned. This retains the
  # historical caller shape without permitting a precomputed map to grant
  # authority.
  defp unpinned_index(%{admitted: admitted, refused: refused})
       when is_map(admitted) and is_map(refused) do
    source_graph = RDF.Graph.new()

    refused =
      Enum.reduce(admitted, refused, fn {iri, _digest}, acc ->
        Map.put(acc, iri, {:authority_not_pinned, iri})
      end)

    {:ok,
     %{
       admitted: %{},
       refused: refused,
       source_graph: source_graph,
       source_digest: graph_digest(source_graph)
     }}
  end

  defp unpinned_index(other),
    do: {:error, {:authority_index_unavailable, nil, {:invalid_authority, inspect(other)}}}

  @doc """
  The trust-root pins of the CANONICAL semantic-jira-pack ontology:
  `%{authority_iri => digest}` read from its `sj:AuthorityTrustRoot` nodes
  (`sj:authorityIri`, `sj:admissionDigest`, `sj:sourceLocator`). Always the
  app's canonical path -- never a caller path -- cached by file-byte digest
  like `canonical_index/1`. An unreadable or unparseable file fails closed.
  """
  @spec trust_roots() ::
          {:ok, %{String.t() => digest()}}
          | {:error, {:authority_index_unavailable, Path.t(), term()}}
  def trust_roots do
    path = canonical_path()

    with {:ok, bytes} <- read_authority(path) do
      key = {__MODULE__, :pins, Digest.sha256(bytes)}

      case :persistent_term.get(key, nil) do
        nil -> parse_pins(bytes, path, key)
        pins -> {:ok, pins}
      end
    end
  end

  defp parse_pins(bytes, path, key) do
    case RDF.Turtle.read_string(bytes) do
      {:ok, graph} ->
        pins = pins(graph)
        :persistent_term.put(key, pins)
        {:ok, pins}

      {:error, reason} ->
        {:error, {:authority_index_unavailable, path, inspect(reason)}}
    end
  end

  @doc """
  The pins declared by `sj:AuthorityTrustRoot` nodes of `graph`. A pin is
  well-formed only with exactly one IRI `sj:authorityIri`, exactly one
  `sj:admissionDigest` matching `sha256:<64 hex>` and exactly one
  `sj:sourceLocator`; malformed pins pin nothing. An IRI pinned to two
  different digests is ambiguous and pins nothing (fail closed).
  """
  @spec pins(RDF.Graph.t()) :: %{String.t() => digest()}
  def pins(%RDF.Graph{} = graph) do
    graph
    |> typed_nodes([@trust_root_class])
    |> Enum.flat_map(fn {_node, description} -> pin_of(description) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {iri, digests} ->
      case Enum.uniq(digests) do
        [digest] -> [{iri, digest}]
        _ambiguous -> []
      end
    end)
    |> Map.new()
  end

  defp pin_of(description) do
    with [%RDF.IRI{} = iri] <- RDF.Description.get(description, sj("authorityIri"), []),
         [digest] <- value_set(description, sj("admissionDigest")),
         true <- Regex.match?(@digest_pattern, digest),
         [_locator] <- RDF.Description.get(description, sj("sourceLocator"), []) do
      [{RDF.IRI.to_string(iri), digest}]
    else
      _ -> []
    end
  end

  @doc """
  Applies the trust-root pin law to an admission `index`: an admitted entry
  stays admitted only when its `(iri, digest)` pair is exactly pinned;
  otherwise it moves to `refused` as `{:authority_not_pinned, iri}`.
  Already-refused entries keep their refusal.
  """
  @spec pin(index(), %{String.t() => digest()}) :: index()
  def pin(
        %{
          admitted: admitted,
          refused: refused,
          source_graph: %RDF.Graph{},
          source_digest: source_digest
        } = index,
        pins
      )
      when is_map(pins) and is_binary(source_digest) do
    conflicts =
      admitted
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(refused)))
      |> MapSet.to_list()

    conflict_refusals =
      Enum.reduce(conflicts, refused, fn iri, acc ->
        Map.put(acc, iri, {:authority_index_conflict, iri})
      end)

    admitted_without_conflicts = Map.drop(admitted, conflicts)

    {invalid, digest_valid} =
      Enum.split_with(admitted_without_conflicts, fn {iri, digest} ->
        not (is_binary(iri) and is_binary(digest) and Regex.match?(@digest_pattern, digest))
      end)

    invalid_refusals =
      Enum.reduce(invalid, conflict_refusals, fn {iri, _digest}, acc ->
        Map.put(acc, iri, {:authority_digest_invalid, iri})
      end)

    {kept, unpinned} =
      Enum.split_with(digest_valid, fn {iri, digest} ->
        Map.get(pins, iri) == digest
      end)

    final_refusals =
      Enum.reduce(unpinned, invalid_refusals, fn {iri, _digest}, acc ->
        Map.put(acc, iri, {:authority_not_pinned, iri})
      end)

    %{index | admitted: Map.new(kept), refused: final_refusals}
  end

  # Direct callers of the low-level pin/2 helper may still supply the legacy
  # two-map shape. That shape is never accepted as an admission source by
  # index_from/1; here it is retained only for explicit pin-set calculations.
  def pin(%{admitted: admitted, refused: refused}, pins)
      when is_map(admitted) and is_map(refused) and is_map(pins) do
    source_graph = RDF.Graph.new()

    pin(
      %{
        admitted: admitted,
        refused: refused,
        source_graph: source_graph,
        source_digest: graph_digest(source_graph)
      },
      pins
    )
  end

  @doc """
  Deterministic, authority-inert receipt for an authority index.

  The receipt preserves the complete typed refusal set so failed admission is
  replayable instead of being reduced to a boolean. It is a CONSTRUCT
  artifact only: `authority` is always `"NONE"`.
  """
  @spec index_receipt(index()) :: map()
  def index_receipt(%{
        admitted: admitted,
        refused: refused,
        source_digest: source_digest
      })
      when is_map(admitted) and is_map(refused) and is_binary(source_digest) do
    admitted_rows =
      admitted
      |> Enum.map(fn {iri, digest} -> %{"iri" => iri, "digest" => digest} end)
      |> Enum.sort_by(& &1["iri"])

    refused_rows =
      refused
      |> Enum.map(fn {iri, refusal} ->
        %{"iri" => iri, "refusal" => normalize_refusal(refusal)}
      end)
      |> Enum.sort_by(& &1["iri"])

    canonical =
      [
        "semantic-jira/authority-index-receipt/v1",
        source_digest,
        Enum.map_join(admitted_rows, "", fn row ->
          "A\t#{row["iri"]}\t#{row["digest"]}\n"
        end),
        Enum.map_join(refused_rows, "", fn row ->
          "R\t#{row["iri"]}\t#{inspect(row["refusal"], limit: :infinity)}\n"
        end)
      ]
      |> IO.iodata_to_binary()

    %{
      "schema" => "semantic-jira/authority-index-receipt/v1",
      "source_digest" => source_digest,
      "admitted" => admitted_rows,
      "refused" => refused_rows,
      "authority" => "NONE",
      "grants_do_authority" => false,
      "receipt_digest" => Digest.sha256(canonical)
    }
  end

  defp normalize_refusal(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_refusal(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&normalize_refusal/1)

  defp normalize_refusal(value) when is_list(value), do: Enum.map(value, &normalize_refusal/1)
  defp normalize_refusal(value), do: value

  @doc """
  The origin guard every kernel entry point runs (G1): `work_order`'s
  `origin_authority` must be present and RESOLVE in the pinned index named
  by `opts[:authority]` (`index_from/1`). Returns `{:ok, digest}` or
  `{:error, {:refused_origin, refusal}}` -- `:origin_authority_missing`,
  `{:authority_not_pinned, iri}`, `{:authority_not_admitted, iri}`, ... or
  `{:authority_index_unavailable, path, detail}` (fail closed).
  """
  @spec require_origin(map(), keyword()) ::
          {:ok, digest()} | {:error, {:refused_origin, origin_refusal()}}
  def require_origin(work_order, opts) when is_map(work_order) and is_list(opts) do
    case origin_of(work_order) do
      origin when is_binary(origin) and origin != "" ->
        case index_from(opts) do
          {:ok, index} -> resolve(index, origin)
          {:error, unavailable} -> {:error, {:refused_origin, unavailable}}
        end

      _missing ->
        {:error, {:refused_origin, :origin_authority_missing}}
    end
  end

  defp origin_of(work_order) do
    case Map.fetch(work_order, "origin_authority") do
      {:ok, origin} -> origin
      :error -> Map.get(work_order, :origin_authority)
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
    with {:ok, _digest} <- resolve_pinned(index(canonical_graph), literal(origin)) do
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

  # The canonical graph handed to verify_origin/3 may come from a caller
  # path (`:ontology_path`); its admission is still bounded by the pins.
  defp resolve_pinned(index, origin) do
    case trust_roots() do
      {:ok, pins} -> resolve(pin(index, pins), origin)
      {:error, unavailable} -> {:error, {:refused_origin, unavailable}}
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
