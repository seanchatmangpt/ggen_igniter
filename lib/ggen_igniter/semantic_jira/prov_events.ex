defmodule GgenIgniter.SemanticJira.ProvEvents do
  @moduledoc """
  PROV-O serialization of `TransitionLog` standing-transition events.

  Each event becomes a `prov:Activity` (also `sj:StandingTransitionEvent`):

    * `prov:used` the receipt entity (`prov:Entity`) and the pre-transition
      standing entity;
    * `prov:generated` the post-transition standing entity, which carries
      `prov:wasGeneratedBy` the event and `prov:wasDerivedFrom` both the
      pre-transition standing and the receipt;
    * `prov:wasInformedBy` the previous event in `seq` order;
    * `prov:wasAssociatedWith` the reconciler software agent.

  The pre-transition entity of an identity's first event is a genesis entity;
  afterwards it is the post entity of that identity's previous event, so
  `prov:wasDerivedFrom` chains a WorkOrder's standing history.

  Output is deterministic: events are ordered by `seq`, IRIs are derived from
  digests only, and the Turtle is emitted by hand in a fixed statement order
  (no map/graph iteration order, no timestamps), so the same ledger always
  yields the same bytes regardless of ledger form (file or directory).

  Epoch + vector clocks (loops-of-loops spec §1 Loop 2): when an event
  carries `epoch` it is projected as `sj:epoch` (a plain integer literal);
  when it carries `vc` it is projected as a single `sj:vectorClock` literal
  holding the clock's JSON form with keys sorted, so projection stays
  deterministic. Both are CONDITIONALLY required: `@required` is unchanged,
  because pre-L3 events (which `TransitionLog.append/3` has stamped with
  `epoch` only since L3) cannot satisfy them and must keep projecting.
  `stamped?/1` is the post-L3 detector — an event carrying `epoch` must carry
  a well-formed u64 epoch, and an event carrying `vc` must carry a
  well-formed clock; a violation is the same typed
  `{:invalid_event, seq, missing}` refusal as a missing `@required` field.

  `to_turtle/1` refuses (typed) an event missing a required field rather than
  emitting a partial record. `validate/1` runs the result through the real
  `GgenIgniter.SemanticJira.Shacl` court against the pack shape file
  (`Shacl.pack_shapes_path/0`: sj:StandingTransitionEventProvShape,
  sj:StandingEntityProvShape, sj:GeneratedStandingProvShape) -- the same
  shapes file the work-order court executes; there is no second, module-local
  shape set to drift from it. The receipt entity is typed `prov:Entity` only,
  not `sj:Receipt`: the full `sj:Receipt` law (`sj:ReceiptShape`:
  workOrderDigest/repository/baseSha/subjectSha/replayIdentity/receiptClass)
  binds durable receipts, and the projection carries only the
  `sj:receiptDigest` the event records. Authority stays NONE.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Shacl, TransitionLog}

  @base "https://ggen-igniter.dev/ontology/semantic-jira/"
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @required ~w(seq event_digest identity from to receipt_digest)

  @prefixes """
  @prefix prov: <http://www.w3.org/ns/prov#> .
  @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
  @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  """

  @spec agent_iri() :: String.t()
  def agent_iri, do: @base <> "agent/reconciler"

  @doc "Turtle for the events of the ledger at `path` (refused ledgers are typed errors)."
  @spec from_ledger(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def from_ledger(path) do
    with {:ok, events} <- TransitionLog.fetch(path), do: to_turtle(events)
  end

  @doc "Deterministic Turtle for `events` (string-keyed maps as stored in the log)."
  @spec to_turtle([map()]) :: {:ok, String.t()} | {:error, {:invalid_event, term(), [String.t()]}}
  def to_turtle(events) when is_list(events) do
    with :ok <- validate_events(events) do
      sorted = Enum.sort_by(events, & &1["seq"])

      {blocks, _} =
        Enum.map_reduce(sorted, {%{}, nil}, fn event, {last_post, prev} ->
          known = Map.get(last_post, event["identity"])
          pre = known || genesis_iri(event["identity"])
          block = event_block(event, pre, prev, is_nil(known))
          {block, {Map.put(last_post, event["identity"], post_iri(event)), event}}
        end)

      body = Enum.map_join(blocks, "\n", &Enum.join/1)
      {:ok, @prefixes <> "\n" <> agent_block() <> "\n" <> body}
    end
  end

  @doc "The Turtle parsed by the real ontology loader into an `RDF.Graph`."
  @spec to_graph([map()]) :: {:ok, RDF.Graph.t()} | {:error, term()}
  def to_graph(events) do
    with {:ok, ttl} <- to_turtle(events), do: RDF.Turtle.read_string(ttl)
  end

  @doc "Validates a serialized-events graph or Turtle string with the real SHACL court."
  @spec validate(RDF.Graph.t() | String.t()) :: Shacl.t()
  def validate(%RDF.Graph{} = data), do: Shacl.validate_file(data)

  def validate(turtle) when is_binary(turtle), do: validate(RDF.Turtle.read_string!(turtle))

  # ── serialization ─────────────────────────────────────────────────────────

  defp validate_events(events) do
    Enum.find_value(events, :ok, fn event ->
      missing =
        if is_map(event),
          do: Enum.reject(@required, &valid_field?(event, &1)) ++ conditional_missing(event),
          else: @required

      if missing == [], do: nil, else: {:error, {:invalid_event, seq_of(event), missing}}
    end)
  end

  # The post-L3 detector: `TransitionLog.append/3` has stamped `"epoch"` on
  # every event it writes since L3 (loops-of-loops spec §1 Loop 2), so an
  # event carrying one is a post-L3 write and MUST carry a well-formed epoch;
  # an event without it is a pre-L3 write and is NOT required to (honest
  # scoping — old ledgers keep projecting). A present-but-malformed field is
  # a refusal, never a silently partial projection.
  defp stamped?(event) when is_map(event), do: Map.has_key?(event, "epoch")
  defp stamped?(_), do: false

  defp valid_epoch?(e), do: is_integer(e) and e >= 0 and e < 18_446_744_073_709_551_616

  defp valid_vc?(vc),
    do: is_map(vc) and Enum.all?(vc, fn {r, n} -> is_binary(r) and is_integer(n) and n >= 0 end)

  defp conditional_missing(event) do
    cond do
      stamped?(event) and not valid_epoch?(event["epoch"]) -> ["epoch"]
      Map.has_key?(event, "vc") and not valid_vc?(event["vc"]) -> ["vc"]
      true -> []
    end
  end

  defp seq_of(%{"seq" => seq}), do: seq
  defp seq_of(_), do: nil

  defp valid_field?(event, "seq"), do: is_integer(event["seq"]) and event["seq"] > 0

  defp valid_field?(event, key) when key in ["event_digest", "receipt_digest"],
    do: is_binary(event[key]) and Regex.match?(@digest, event[key])

  defp valid_field?(event, key), do: is_binary(event[key]) and event[key] != ""

  defp hex("sha256:" <> hex), do: hex

  defp event_iri(event), do: @base <> "event/" <> hex(event["event_digest"])
  defp receipt_iri(event), do: @base <> "receipt/" <> hex(event["receipt_digest"])
  defp post_iri(event), do: event_iri(event) <> "/post"

  defp genesis_iri(identity),
    do: @base <> "genesis/" <> hex(SemanticJira.digest(%{"genesis_of" => identity}))

  defp agent_block do
    "<#{agent_iri()}> a prov:SoftwareAgent ;\n  rdfs:label \"SemanticJira.Reconciler\" .\n"
  end

  defp event_block(event, pre, prev, genesis?) do
    informed =
      if prev, do: ["  prov:wasInformedBy <#{event_iri(prev)}> ;\n"], else: []

    # L3 stamps, projected only when the event carries them (pre-L3 events
    # project byte-identically to their old shape).
    stamp_lines =
      if(Map.has_key?(event, "epoch"), do: ["  sj:epoch #{event["epoch"]} ;\n"], else: []) ++
        if vc = vc_literal(event["vc"]), do: ["  sj:vectorClock #{vc} ;\n"], else: []

    [
      [
        "<#{event_iri(event)}> a prov:Activity, sj:StandingTransitionEvent ;\n",
        "  sj:seq #{event["seq"]} ;\n"
      ],
      stamp_lines,
      [
        "  sj:eventDigest #{lit(event["event_digest"])} ;\n",
        "  sj:identity #{lit(event["identity"])} ;\n",
        "  sj:from #{lit(event["from"])} ;\n",
        "  sj:to #{lit(event["to"])} ;\n",
        "  sj:authority #{lit(event["authority"] || "NONE")} ;\n"
      ],
      informed,
      [
        "  prov:wasAssociatedWith <#{agent_iri()}> ;\n",
        "  prov:used <#{pre}>, <#{receipt_iri(event)}> ;\n",
        "  prov:generated <#{post_iri(event)}> .\n\n"
      ],
      [
        "<#{receipt_iri(event)}> a prov:Entity ;\n",
        "  sj:receiptDigest #{lit(event["receipt_digest"])} .\n\n"
      ],
      if(genesis?,
        do: [
          "<#{pre}> a prov:Entity, sj:StandingState ;\n",
          "  sj:identity #{lit(event["identity"])} ;\n",
          "  sj:standing #{lit(event["from"])} .\n\n"
        ],
        else: []
      ),
      [
        "<#{post_iri(event)}> a prov:Entity, sj:StandingState, sj:GeneratedStandingState ;\n",
        "  sj:identity #{lit(event["identity"])} ;\n",
        "  sj:standing #{lit(event["to"])} ;\n",
        "  prov:wasGeneratedBy <#{event_iri(event)}> ;\n",
        "  prov:wasDerivedFrom <#{pre}>, <#{receipt_iri(event)}> .\n"
      ]
    ]
  end

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

  # The clock as a single JSON-ish literal, keys sorted, so the projection
  # stays deterministic regardless of map iteration order (the bytes law).
  defp vc_literal(nil), do: nil

  defp vc_literal(%{} = vc) do
    body = Enum.map_join(Enum.sort(vc), ",", fn {r, n} -> ~s("#{r}":#{n}) end)
    lit("{#{body}}")
  end

  defp vc_literal(_), do: nil
end
