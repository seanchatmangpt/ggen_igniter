defmodule GgenIgniter.SemanticJira.Provenance do
  @moduledoc """
  PROV-O (RDF/Turtle) serialization of `GgenIgniter.SemanticJira.TransitionLog`
  events, and the reverse: a verifying replay from that Turtle back to the
  exact event maps. It is a projection of the log (ADR-010) onto a public
  vocabulary (ADR-011); it never becomes a source of standing and carries
  authority NONE.

  - `to_turtle/1` renders events (receipt -> canonical-state transitions) through
    the pack template `runtime-templates/transition_log.ttl.eex` of
    `semantic-jira-pack`. Events are ordered by `seq`; output is deterministic
    (same events, any input order -> same text).
  - `replay/1` / `replay_file/1` load the Turtle through the real loader
    (`RDF.Turtle` / `GgenIgniter.Ontology`), recover every event with a real
    SPARQL query (`runtime-queries/transition_events.rq`, engine `oxigraph`,
    via `GgenIgniter.Engine`), and REFUSE unless every integrity check passes.
  - `standing_projection/1` recovers each work order's current standing straight
    from the RDF with SPARQL (`runtime-queries/standing_projection.rq`) after
    the same verification; it is the SPARQL twin of `SemanticJira.project/2`.

  ## Vocabulary

  Per event (`<urn:ggen:sj:event:sha256:...>`, a `prov:Activity` and
  `sj:StandingTransitionEvent`):

  | Event field | RDF |
  |---|---|
  | `event_digest` | IRI suffix and `dcterms:identifier` |
  | `seq` | `sj:seq` (`xsd:integer`) |
  | `kind`, `identity`, `from`, `to`, `transition_digest` | `sj:eventKind`, `sj:workOrderId`, `sj:fromStanding`, `sj:toStanding`, `sj:transitionDigest` |
  | `definition_digest`, `snapshot_digest`, `receipt_digest` | `prov:used` of a `prov:Entity` (`sj:WorkOrderDefinition` / `sj:WorkOrderSnapshot` / `sj:TransitionReceipt`) whose IRI embeds the digest and whose `dcterms:identifier` repeats it |
  | resulting standing | `sj:StandingState` entity: `prov:wasGeneratedBy` the event, `prov:wasDerivedFrom` the receipt, `sj:standing` |
  | `authority` | the state entity's `prov:wasAttributedTo` a `prov:Agent` `<urn:ggen:sj:authority:NONE>` |
  | `started_at` (optional) | `prov:startedAtTime` (`xsd:dateTime`); emitted only when the event carries it |
  | log order | `prov:wasInformedBy` the previous event by `seq` |
  | integrity | `sj:contentSeal` (sha256 over the canonical full event) |
  | any other key | `sj:extra` (one JSON literal), so the round trip is lossless |

  `TransitionLog`/`Reconciler` events carry no wall-clock time today (stamping
  one would change event digests and break idempotent replay), so
  `prov:startedAtTime` appears only for events that supply `started_at`.

  ## Replay refusals (`{:error, {:refused, reason}}`)

  `:invalid_turtle`, `:query_failed`, `:ambiguous_event`, `:iri_literal_mismatch`
  (an entity IRI disagrees with its `dcterms:identifier` literal),
  `:missing_state` / `:state_mismatch` (the `sj:StandingState` entity is absent, or its
  work order, standing or `prov:wasDerivedFrom` receipt disagrees with the event),
  `:invalid_seq`, `:invalid_extra`, `:extra_shadows_field`,
  `:event_digest_mismatch` (recomputed `SemanticJira.digest/1` over the event
  body differs), `:missing_content_seal`, `:content_seal_mismatch`,
  `:duplicate_seq`, `:broken_chain` (an event's `prov:wasInformedBy` is not the
  previous event by `seq`, e.g. an event was deleted from the middle).

  ## Not claimed

  Tamper EVIDENCE, not tamper PROOF: the digests are unkeyed (ADR-010: no
  signing), so a coordinated rewrite that also recomputes `sj:contentSeal`
  (and, for `to`/`from`/`identity`, `event_digest`) is undetectable.
  `SemanticJira.digest/1` deliberately ignores top-level `receipt_digest` and
  `transition_digest`, so `event_digest` alone does not cover them; the IRI
  cross-check and `sj:contentSeal` do. Truncating the log's tail is not
  detectable from the Turtle alone. Events must be JSON-shaped.

  Hand-written residue: the event-field -> predicate mapping and the verifier
  are Elixir. UNSUPPORTED(generator-capability): no ggen pack or generator in
  `~/ggen-marketplace/packs/` serializes an append-only JSON event log to
  PROV-O (the packs that mention `prov:` use it as vocabulary only).
  """

  alias GgenIgniter.{Digest, Engine, Ontology, Render, SemanticA2A, SemanticJira}

  @type event :: %{optional(String.t()) => term()}
  @type refusal :: {:error, {:refused, term()}}

  @digest_re ~r/\Asha256:[0-9a-f]{64}\z/
  @token_re ~r/\A[A-Za-z0-9_.-]+\z/
  @datetime_re ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})\z/

  @event_ns "urn:ggen:sj:event:"
  @standing_ns "urn:ggen:sj:standing:"
  @authority_ns "urn:ggen:sj:authority:"

  # Event key -> predicate, for values emitted as plain string literals.
  @literal_fields [
    {"kind", "sj:eventKind"},
    {"identity", "sj:workOrderId"},
    {"from", "sj:fromStanding"},
    {"to", "sj:toStanding"},
    {"transition_digest", "sj:transitionDigest"}
  ]

  # Event key -> {IRI namespace, RDF class, SPARQL IRI var, SPARQL id var}.
  @entity_fields [
    {"definition_digest", "urn:ggen:sj:definition:", "sj:WorkOrderDefinition", "definition",
     "definition_id"},
    {"snapshot_digest", "urn:ggen:sj:snapshot:", "sj:WorkOrderSnapshot", "snapshot",
     "snapshot_id"},
    {"receipt_digest", "urn:ggen:sj:receipt:", "sj:TransitionReceipt", "receipt", "receipt_id"}
  ]

  @literal_keys Enum.map(@literal_fields, &elem(&1, 0))
  @entity_keys Enum.map(@entity_fields, &elem(&1, 0))

  # -- export ------------------------------------------------------------------

  @doc """
  Renders `events` (as returned by `TransitionLog.read/1`) as PROV-O Turtle.

  Refuses with `{:error, {:refused_export, reason}}` for an event that is not a
  JSON-shaped map with a well-formed `event_digest` and an integer `seq`, or
  for duplicate `seq` / `event_digest` values.
  """
  @spec to_turtle([map()]) :: {:ok, String.t()} | {:error, {:refused_export, term()}}
  def to_turtle(events) when is_list(events) do
    with {:ok, events} <- prepare(events) do
      {:ok, render(blocks(events))}
    end
  end

  def to_turtle(_), do: {:error, {:refused_export, :expected_event_list}}

  defp prepare(events) do
    events = Enum.map(events, &stringify/1)

    with :ok <- each_event(events),
         sorted = Enum.sort_by(events, & &1["seq"]),
         :ok <- unique(sorted, "seq", :duplicate_seq),
         :ok <- unique(sorted, "event_digest", :duplicate_event_digest) do
      {:ok, sorted}
    end
  end

  defp each_event(events) do
    Enum.find_value(events, :ok, fn event ->
      case check_event(event) do
        :ok -> nil
        {:error, reason} -> {:error, {:refused_export, reason}}
      end
    end)
  end

  defp check_event(event) when is_map(event) do
    cond do
      not match?({:ok, _}, Jason.encode(event)) ->
        {:error, {:not_json_shaped, event}}

      not digest?(event["event_digest"]) ->
        {:error, {:invalid_event_digest, event["event_digest"]}}

      not is_integer(event["seq"]) ->
        {:error, {:invalid_seq, event["seq"]}}

      true ->
        :ok
    end
  end

  defp check_event(other), do: {:error, {:not_a_map, other}}

  defp unique(events, key, reason) do
    values = Enum.map(events, & &1[key])

    case values -- Enum.uniq(values) do
      [] -> :ok
      [value | _] -> {:error, {:refused_export, {reason, value}}}
    end
  end

  defp blocks(events) do
    previous = [nil | Enum.map(events, & &1["event_digest"])]
    pairs = Enum.zip(previous, events)

    Enum.map(pairs, fn {prev, event} -> activity(event, prev) end) ++
      Enum.map(events, &state/1) ++
      entities(events) ++
      agents(events)
  end

  defp activity(event, prev) do
    digest = event["event_digest"]

    po =
      [
        {"dcterms:identifier", literal(digest)},
        {"sj:seq", ~s("#{event["seq"]}"^^xsd:integer)}
      ] ++
        literal_po(event) ++
        used_po(event) ++
        started_po(event) ++
        chain_po(prev) ++
        [{"sj:contentSeal", literal(seal(event))}] ++
        extra_po(event)

    %{subject: iri(@event_ns, digest), types: "prov:Activity, sj:StandingTransitionEvent", po: po}
  end

  defp literal_po(event) do
    for {key, predicate} <- @literal_fields, is_binary(event[key]) do
      {predicate, literal(event[key])}
    end
  end

  defp used_po(event) do
    for {key, ns, _class, _iri_var, _id_var} <- @entity_fields, digest?(event[key]) do
      {"prov:used", iri(ns, event[key])}
    end
  end

  defp started_po(event) do
    if datetime?(event["started_at"]),
      do: [{"prov:startedAtTime", ~s("#{event["started_at"]}"^^xsd:dateTime)}],
      else: []
  end

  defp chain_po(nil), do: []
  defp chain_po(prev), do: [{"prov:wasInformedBy", iri(@event_ns, prev)}]

  defp extra_po(event) do
    case extra(event) do
      extra when map_size(extra) == 0 -> []
      extra -> [{"sj:extra", extra |> canonical() |> Jason.encode!() |> literal()}]
    end
  end

  defp state(event) do
    po =
      [{"prov:wasGeneratedBy", iri(@event_ns, event["event_digest"])}] ++
        attributed_po(event["authority"]) ++
        derived_po(event["receipt_digest"]) ++
        state_literal_po(event)

    %{
      subject: iri(@standing_ns, event["event_digest"]),
      types: "prov:Entity, sj:StandingState",
      po: po
    }
  end

  defp attributed_po(authority) do
    if authority?(authority),
      do: [{"prov:wasAttributedTo", iri(@authority_ns, authority)}],
      else: []
  end

  defp derived_po(receipt) do
    if digest?(receipt),
      do: [{"prov:wasDerivedFrom", iri("urn:ggen:sj:receipt:", receipt)}],
      else: []
  end

  defp state_literal_po(event) do
    for {key, predicate} <- [{"identity", "sj:workOrderId"}, {"to", "sj:standing"}],
        is_binary(event[key]) do
      {predicate, literal(event[key])}
    end
  end

  defp entities(events) do
    for {key, ns, class, _iri_var, _id_var} <- @entity_fields,
        digest <-
          events |> Enum.map(& &1[key]) |> Enum.filter(&digest?/1) |> Enum.uniq() |> Enum.sort() do
      %{
        subject: iri(ns, digest),
        types: "prov:Entity, #{class}",
        po: [{"dcterms:identifier", literal(digest)}]
      }
    end
  end

  defp agents(events) do
    for token <-
          events
          |> Enum.map(& &1["authority"])
          |> Enum.filter(&authority?/1)
          |> Enum.uniq()
          |> Enum.sort() do
      %{
        subject: iri(@authority_ns, token),
        types: "prov:Agent, sj:AuthorityCeiling",
        po: [{"dcterms:identifier", literal(token)}]
      }
    end
  end

  defp render(blocks) do
    [SemanticA2A.pack_dir(), "runtime-templates", "transition_log.ttl.eex"]
    |> Path.join()
    |> File.read!()
    |> Render.render(blocks: blocks)
  end

  # -- replay ------------------------------------------------------------------

  @doc """
  Replays the event log from PROV-O Turtle text: real parse, real SPARQL, and
  every integrity check listed in the moduledoc. Returns the events ordered by
  `seq`, equal (as maps) to what `TransitionLog.read/1` returned at export.
  """
  @spec replay(String.t()) :: {:ok, [event()]} | refusal()
  def replay(turtle) when is_binary(turtle) do
    with {:ok, graph} <- parse(turtle) do
      replay_graph(graph)
    end
  end

  @doc "Like `replay/1`, loading the graph from a Turtle file via `GgenIgniter.Ontology.load!/1`."
  @spec replay_file(Path.t()) :: {:ok, [event()]} | refusal()
  def replay_file(path) do
    replay_graph(Ontology.load!(path))
  rescue
    error -> refused({:invalid_turtle, Exception.message(error)})
  end

  @doc """
  Each work order's current standing recovered from the RDF by SPARQL, after
  `replay/1`-grade verification. Same shape as the evidence map returned by
  `SemanticJira.project/2`: `%{identity => %{"standing" => _, "receipt_digest" => _}}`.
  """
  @spec standing_projection(String.t()) :: {:ok, map()} | refusal()
  def standing_projection(turtle) when is_binary(turtle) do
    with {:ok, graph} <- parse(turtle),
         {:ok, _events} <- replay_graph(graph),
         {:ok, rows} <- sparql(graph, "standing_projection.rq") do
      {:ok,
       rows
       |> Enum.sort_by(&String.to_integer(&1["seq"]))
       |> Map.new(fn row ->
         {row["work_order_id"],
          %{"standing" => row["to"], "receipt_digest" => value(row, "receipt_digest")}}
       end)}
    end
  end

  defp parse(turtle) do
    {:ok, RDF.Turtle.read_string!(turtle)}
  rescue
    error -> refused({:invalid_turtle, Exception.message(error)})
  end

  defp replay_graph(graph) do
    with {:ok, rows} <- sparql(graph, "transition_events.rq"),
         {:ok, pairs} <- build_events(rows),
         {:ok, pairs} <- ordered(pairs),
         :ok <- chain(pairs) do
      {:ok, Enum.map(pairs, &elem(&1, 0))}
    end
  end

  defp sparql(graph, query_file) do
    engine = Engine.fetch!("oxigraph")
    context = engine.prepare!(graph, [])

    query =
      [SemanticA2A.pack_dir(), "runtime-queries", query_file] |> Path.join() |> File.read!()

    {:ok, engine.run(context, query)}
  rescue
    error in RuntimeError -> refused({:query_failed, Exception.message(error)})
  end

  defp build_events(rows) do
    rows
    |> Enum.group_by(& &1["event"])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {iri, group}, {:ok, acc} ->
      case build_event(iri, group) do
        {:ok, pair} -> {:cont, {:ok, [pair | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp build_event(iri, group) do
    with {:ok, row} <- single_row(iri, group),
         {:ok, typed, prev} <- typed_fields(iri, row),
         {:ok, event} <- merge_extra(iri, typed, value(row, "extra")),
         :ok <- verify_event_digest(iri, event),
         :ok <- verify_seal(iri, event, value(row, "seal")),
         :ok <- verify_state(iri, row, event["event_digest"]) do
      {:ok, {event, prev}}
    end
  end

  defp single_row(iri, group) do
    case Enum.uniq(group) do
      [row] -> {:ok, row}
      _ -> refused({:ambiguous_event, iri})
    end
  end

  defp typed_fields(iri, row) do
    digest = row["event_digest"]

    with :ok <- same_iri(:event, iri, @event_ns, digest),
         {:ok, seq} <- seq(iri, row["seq"]),
         {:ok, entities} <- entity_fields(row),
         {:ok, authority} <- authority(value(row, "agent")),
         {:ok, prev} <- previous(value(row, "informed_by")) do
      typed =
        [{"event_digest", digest}, {"seq", seq}, {"authority", authority}] ++
          [{"started_at", value(row, "started_at")}] ++
          entities ++
          [
            {"kind", value(row, "kind")},
            {"identity", value(row, "work_order_id")},
            {"from", value(row, "from")},
            {"to", value(row, "to")},
            {"transition_digest", value(row, "transition_digest")}
          ]

      {:ok, typed |> Enum.reject(&is_nil(elem(&1, 1))) |> Map.new(), prev}
    end
  end

  defp entity_fields(row), do: collect_entities(@entity_fields, row, [])

  defp collect_entities([], _row, acc), do: {:ok, acc}

  defp collect_entities([spec | rest], row, acc) do
    case entity_field(row, spec) do
      {:ok, nil} -> collect_entities(rest, row, acc)
      {:ok, pair} -> collect_entities(rest, row, [pair | acc])
      {:error, _} = error -> error
    end
  end

  defp entity_field(row, {key, ns, _class, iri_var, id_var}) do
    case value(row, iri_var) do
      nil ->
        {:ok, nil}

      entity_iri ->
        digest = value(row, id_var)

        with :ok <- same_iri(key, entity_iri, ns, digest) do
          {:ok, {key, digest}}
        end
    end
  end

  defp same_iri(field, iri, ns, digest) do
    if is_binary(digest) and iri == ns <> digest,
      do: :ok,
      else: refused({:iri_literal_mismatch, field, iri})
  end

  # The standing-state entity must exist and agree with its event: same work
  # order, same resulting standing, derived from the same receipt.
  defp verify_state(iri, row, digest) do
    case value(row, "state") do
      nil -> refused({:missing_state, iri})
      state -> verify_state_fields(state, row, digest)
    end
  end

  defp verify_state_fields(state, row, digest) do
    with :ok <- same_iri(:state, state, @standing_ns, digest) do
      if state_agrees?(row), do: :ok, else: refused({:state_mismatch, state})
    end
  end

  defp state_agrees?(row) do
    value(row, "state_work_order_id") == value(row, "work_order_id") and
      value(row, "state_standing") == value(row, "to") and
      value(row, "state_derived_from") == value(row, "receipt")
  end

  defp seq(iri, lexical) do
    case Integer.parse(lexical || "") do
      {n, ""} -> {:ok, n}
      _ -> refused({:invalid_seq, iri})
    end
  end

  defp authority(nil), do: {:ok, nil}

  defp authority(agent) do
    token = String.replace_prefix(agent, @authority_ns, "")

    if String.starts_with?(agent, @authority_ns) and authority?(token),
      do: {:ok, token},
      else: refused({:iri_literal_mismatch, :authority, agent})
  end

  defp previous(nil), do: {:ok, nil}

  defp previous(informed_by) do
    digest = String.replace_prefix(informed_by, @event_ns, "")

    if String.starts_with?(informed_by, @event_ns) and digest?(digest),
      do: {:ok, digest},
      else: refused({:iri_literal_mismatch, :informed_by, informed_by})
  end

  defp merge_extra(_iri, typed, nil), do: {:ok, typed}

  defp merge_extra(iri, typed, json) do
    case Jason.decode(json) do
      {:ok, extra} when is_map(extra) ->
        case Enum.find(Map.keys(extra), &Map.has_key?(typed, &1)) do
          nil -> {:ok, Map.merge(typed, extra)}
          key -> refused({:extra_shadows_field, key, iri})
        end

      _ ->
        refused({:invalid_extra, iri})
    end
  end

  defp verify_event_digest(iri, event) do
    expected = SemanticJira.digest(Map.drop(event, ["seq", "event_digest"]))

    if expected == event["event_digest"],
      do: :ok,
      else: refused({:event_digest_mismatch, iri})
  end

  defp verify_seal(iri, _event, nil), do: refused({:missing_content_seal, iri})

  defp verify_seal(iri, event, seal) do
    if seal(event) == seal, do: :ok, else: refused({:content_seal_mismatch, iri})
  end

  defp ordered(pairs) do
    sorted = Enum.sort_by(pairs, fn {event, _prev} -> event["seq"] end)

    case unique(sorted |> Enum.map(&elem(&1, 0)), "seq", :duplicate_seq) do
      :ok -> {:ok, sorted}
      {:error, {:refused_export, reason}} -> refused(reason)
    end
  end

  defp chain(pairs) do
    expected = [nil | Enum.map(pairs, fn {event, _} -> event["event_digest"] end)]

    pairs
    |> Enum.zip(expected)
    |> Enum.find_value(:ok, fn {{event, prev}, want} ->
      if prev == want, do: nil, else: refused({:broken_chain, event["event_digest"]})
    end)
  end

  # -- shared ------------------------------------------------------------------

  @doc "A Turtle double-quoted string literal for `string`, escaped per the Turtle grammar."
  @spec literal(String.t()) :: String.t()
  def literal(string) when is_binary(string) do
    escaped = for <<c::utf8 <- string>>, into: "", do: escape(c)
    ~s("#{escaped}")
  end

  defp escape(?\\), do: "\\\\"
  defp escape(?"), do: "\\\""
  defp escape(?\n), do: "\\n"
  defp escape(?\r), do: "\\r"
  defp escape(?\t), do: "\\t"

  defp escape(c) when c < 0x20 or c == 0x7F,
    do: "\\u" <> (c |> Integer.to_string(16) |> String.pad_leading(4, "0"))

  defp escape(c), do: <<c::utf8>>

  defp iri(ns, suffix), do: "<" <> ns <> suffix <> ">"

  # Keys emitted first-class are exactly those `typed?/2` admits; everything
  # else rides in the sj:extra JSON literal so the round trip is lossless.
  defp extra(event), do: event |> Enum.reject(fn {k, v} -> typed?(k, v) end) |> Map.new()

  defp typed?(key, value) when key in @literal_keys, do: is_binary(value)
  defp typed?(key, value) when key in @entity_keys, do: digest?(value)
  defp typed?("authority", value), do: authority?(value)
  defp typed?("started_at", value), do: datetime?(value)
  defp typed?(key, _value) when key in ["event_digest", "seq"], do: true
  defp typed?(_key, _value), do: false

  # sha256 over the canonical FULL event (unlike SemanticJira.digest/1, which
  # drops top-level receipt_digest/transition_digest).
  defp seal(event), do: event |> canonical() |> Jason.encode!() |> Digest.sha256()

  defp canonical(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(other), do: other

  defp stringify(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp digest?(value), do: is_binary(value) and Regex.match?(@digest_re, value)
  defp authority?(value), do: is_binary(value) and Regex.match?(@token_re, value)

  defp datetime?(value) do
    is_binary(value) and Regex.match?(@datetime_re, value) and
      match?({:ok, _, _}, DateTime.from_iso8601(value))
  end

  # SPARQL rows: an unbound OPTIONAL variable may be absent or nil.
  defp value(row, key), do: Map.get(row, key)

  defp refused(reason), do: {:error, {:refused, reason}}
end
