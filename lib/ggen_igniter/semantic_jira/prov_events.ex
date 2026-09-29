defmodule GgenIgniter.SemanticJira.ProvEvents do
  @moduledoc """
  PROV-O serialization of `TransitionLog` standing-transition events.

  Each event becomes a `prov:Activity` (also `sj:StandingTransitionEvent`):

    * `prov:used` the receipt entity (`prov:Entity`, `sj:Receipt`) and the
      pre-transition standing entity;
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

  `to_turtle/1` refuses (typed) an event missing a required field rather than
  emitting a partial record. `shapes_turtle/0` + `validate/1` run the result
  through the real `GgenIgniter.SemanticJira.Shacl` court. Authority stays NONE.
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

  @doc "SHACL shapes (Turtle) the serialized events must satisfy."
  @spec shapes_turtle() :: String.t()
  def shapes_turtle do
    """
    @prefix sh: <http://www.w3.org/ns/shacl#> .
    @prefix prov: <http://www.w3.org/ns/prov#> .
    @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    sj:StandingTransitionEventProvShape a sh:NodeShape ;
      sh:targetClass sj:StandingTransitionEvent ;
      sh:property [ sh:path sj:seq ; sh:minCount 1 ; sh:maxCount 1 ; sh:datatype xsd:integer ] ;
      sh:property [ sh:path sj:eventDigest ; sh:minCount 1 ; sh:maxCount 1 ;
                    sh:datatype xsd:string ; sh:pattern "^sha256:[0-9a-f]{64}$" ] ;
      sh:property [ sh:path sj:identity ; sh:minCount 1 ; sh:maxCount 1 ; sh:minLength 1 ] ;
      sh:property [ sh:path sj:from ; sh:minCount 1 ; sh:maxCount 1 ] ;
      sh:property [ sh:path sj:to ; sh:minCount 1 ; sh:maxCount 1 ] ;
      sh:property [ sh:path prov:used ; sh:minCount 2 ; sh:maxCount 2 ; sh:class prov:Entity ] ;
      sh:property [ sh:path prov:generated ; sh:minCount 1 ; sh:maxCount 1 ; sh:class prov:Entity ] ;
      sh:property [ sh:path prov:wasAssociatedWith ; sh:minCount 1 ; sh:class prov:SoftwareAgent ] .

    sj:StandingEntityProvShape a sh:NodeShape ;
      sh:targetClass sj:StandingState ;
      sh:property [ sh:path sj:standing ; sh:minCount 1 ; sh:maxCount 1 ] ;
      sh:property [ sh:path sj:identity ; sh:minCount 1 ; sh:maxCount 1 ] .

    sj:GeneratedStandingProvShape a sh:NodeShape ;
      sh:targetClass sj:GeneratedStandingState ;
      sh:property [ sh:path prov:wasGeneratedBy ; sh:minCount 1 ; sh:maxCount 1 ;
                    sh:class sj:StandingTransitionEvent ] ;
      sh:property [ sh:path prov:wasDerivedFrom ; sh:minCount 2 ; sh:maxCount 2 ;
                    sh:class prov:Entity ] .
    """
  end

  @doc "Validates a serialized-events graph or Turtle string with the real SHACL court."
  @spec validate(RDF.Graph.t() | String.t()) :: Shacl.t()
  def validate(%RDF.Graph{} = data),
    do: Shacl.validate(data, RDF.Turtle.read_string!(shapes_turtle()))

  def validate(turtle) when is_binary(turtle), do: validate(RDF.Turtle.read_string!(turtle))

  # ── serialization ─────────────────────────────────────────────────────────

  defp validate_events(events) do
    Enum.find_value(events, :ok, fn event ->
      missing =
        if is_map(event), do: Enum.reject(@required, &valid_field?(event, &1)), else: @required

      if missing == [], do: nil, else: {:error, {:invalid_event, seq_of(event), missing}}
    end)
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

    [
      [
        "<#{event_iri(event)}> a prov:Activity, sj:StandingTransitionEvent ;\n",
        "  sj:seq #{event["seq"]} ;\n",
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
        "<#{receipt_iri(event)}> a prov:Entity, sj:Receipt ;\n",
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
end
