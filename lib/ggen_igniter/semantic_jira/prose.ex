defmodule GgenIgniter.SemanticJira.Prose do
  @moduledoc """
  First-mile compiler for accepted prose (GC-26.9.23 gates GC23-0 and GC23-2;
  PRD PR-002..PR-005, ARD sections 5 and 17): candidate propositions ->
  admitted semantic graph -> deterministic finite WorkOrder delta.

  Pipeline (ARD section 17):

      narrative -> candidate extraction (the only LLM edge; NOT here)
        -> provenance binding -> SHACL -> admission -> GoalCheckpoint
        -> current-state query -> semantic diff -> WorkOrder graph

  Everything this module runs is deterministic: no LLM, no network, no
  clock. The same inputs always produce byte-identical outputs (ARD 5.5:
  no second LLM interpretation of an admitted graph revision).

  ## Admission (all-or-nothing; any refusal means no output is written)

    1. **Provenance** (byte-level, not expressible in SHACL): for every
       `sj:Proposition` in the candidate graph, `sj:sourceSha256` equals the
       digest of the `--source` bytes, `sj:sourceDocument` names that file,
       `bytes[sj:sourceStart, sj:sourceEnd)` equals `sj:sourceText`, and the
       IRI recomputes per PVOCAB as
       `<goal namespace>P-<first 16 hex of sha256("<sourceSha256>:<start>:<end>:<kind>")>`.
       A root GoalCheckpoint carrying `sj:sourceSha256` must name the same
       source digest. Every other subject of the candidate graph must be a
       hint node (`sj:Falsifier`/`sj:AcceptanceCriterion`) referenced by a
       proposition -- a candidate file cannot smuggle a WorkOrder, a receipt
       or an edit to a goal node past admission (`foreign_subject`).
    2. **SHACL**: `GgenIgniter.SemanticJira.Shacl` over the pack ontology +
       the goal graph + the candidates, against `shapes/work-order.shacl.ttl`
       merged with `shapes/proposition.shacl.ttl`. Violations are scoped to
       focus nodes of the candidate graph (the goal graph's own admission is
       gate GC23-3's court, not this one).
    3. **Domain rules** (pack queries `prose/*.rq`): `contradictions.rq` (a
       statement that is both an Exclusion and a required Postcondition of
       the same gate), `foreign_requirements.rq` (a proposition required by a
       checkpoint outside the root's gates), `uncovered_gates.rq` (every gate
       of the root has >= 1 admitted proposition).

  ## Delta (PR-004)

  `prose/delta.construct.rq` over goal + admitted propositions + projected
  receipts manufactures one `sj:WorkOrder` per required, unwitnessed
  Postcondition/Invariant/Falsifier proposition, IRI
  `<ns>WO-<first 16 hex of sha256(proposition IRI)>`, with the full FRI-T1
  tuple. A receipt in `--receipts-dir` witnesses a proposition when it is a
  fleet R-schema object with `standing.value == "ALIVE"` whose
  `identity.subject` names the proposition or its gate (see `names?/2`).
  The manufacture is checked by a conservation twin (the expected order set
  is recomputed here from the admitted graph; any difference is
  `delta_nonconservation`) and by SHACL over the pack ontology + goal +
  orders (`order_inadmissible`: falsifier F1 at manufacture time).

  ## Outputs

  `propositions.ttl` (admitted; `sj:candidateStanding` replaced by
  `sj:admissionDigest`) and `orders.ttl`, each serialized as sorted
  N-Triples lines (valid Turtle) under a digest header: byte-identical
  across runs. `check/2` recomputes and compares them byte for byte.

  ## Goal admission (GC23-3 shapes court)

  `admit_goal/1` is the ggen_igniter half of the GC23-3 court: the goal graph
  merged with the pack ontology and any `:context` graphs (e.g. the
  predecessor goal that defines `sj:successorOf` targets) is validated
  against both pack shape files; violations are scoped to subjects of the
  goal graph (context graphs only resolve references), so a WorkOrder with
  one mandatory tuple field deleted is refused naming that field (F1).
  """

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira.Shacl

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms "http://purl.org/dc/terms/"
  @rdf_type RDF.type()

  @delta_kinds ~w(Postcondition Invariant Falsifier)
  @hint_predicates %{"falsifier" => "Falsifier", "acceptance" => "AcceptanceCriterion"}
  @hint_node_predicates [
    RDF.type(),
    RDF.iri("http://www.w3.org/2000/01/rdf-schema#label"),
    RDF.iri("http://www.w3.org/2000/01/rdf-schema#comment"),
    RDF.iri(@dcterms <> "description")
  ]

  @default_pack_dir "priv/ggen/semantic-jira-pack"
  @queries ~w(root foreign_requirements contradictions uncovered_gates delta.construct)

  @type refusal :: %{code: atom(), subject: String.t() | nil, detail: String.t()}
  @type result :: %{
          propositions_ttl: String.t(),
          orders_ttl: String.t(),
          summary: map()
        }

  @doc "Output file names written into `--out-dir`."
  @spec output_files() :: [String.t()]
  def output_files, do: ["propositions.ttl", "orders.ttl"]

  @doc "The ARD section 5.2 proposition kinds that manufacture WorkOrders when required."
  @spec delta_kinds() :: [String.t()]
  def delta_kinds, do: @delta_kinds

  @doc """
  Admits `:candidates` against `:source` and `:goal` and manufactures the
  delta. Options: `:source`, `:candidates`, `:goal` (paths, required),
  `:receipts_dir` (optional), `:pack_dir` (default
  `#{@default_pack_dir}`).
  """
  @spec compile(keyword()) :: {:ok, result()} | {:refused, [refusal()]}
  def compile(opts) do
    with {:ok, inputs} <- read_inputs(opts),
         {:ok, root} <- find_root(inputs),
         :ok <- admit(inputs, root),
         {:ok, witnesses} <- read_receipts(Keyword.get(opts, :receipts_dir)) do
      manufacture(inputs, root, witnesses)
    end
  end

  @doc "Writes a compiled result into `out_dir` (created if missing)."
  @spec write!(result(), String.t()) :: :ok
  def write!(%{propositions_ttl: propositions, orders_ttl: orders}, out_dir) do
    File.mkdir_p!(out_dir)
    File.write!(Path.join(out_dir, "propositions.ttl"), propositions)
    File.write!(Path.join(out_dir, "orders.ttl"), orders)
  end

  @doc "Verifies that `out_dir` holds byte-identical outputs of `result`."
  @spec check(result(), String.t()) :: :ok | {:refused, [refusal()]}
  def check(%{propositions_ttl: propositions, orders_ttl: orders}, out_dir) do
    [{"propositions.ttl", propositions}, {"orders.ttl", orders}]
    |> Enum.flat_map(fn {name, expected} -> drift(Path.join(out_dir, name), expected) end)
    |> verdict()
  end

  @doc """
  Admits a goal graph under the pack shapes (GC23-3). Options: `:goal`
  (path, required), `:context` (list of paths whose graphs only resolve
  references), `:pack_dir`. Returns a summary of the admitted graph or the
  scoped violations as `goal_inadmissible` refusals.
  """
  @spec admit_goal(keyword()) :: {:ok, map()} | {:refused, [refusal()]}
  def admit_goal(opts) do
    pack_dir = Keyword.get(opts, :pack_dir, @default_pack_dir)
    contexts = opts |> Keyword.get(:context, []) |> Enum.with_index(&{:"context_#{&2}", &1})

    files =
      [
        goal: Keyword.get(opts, :goal),
        ontology: Path.join(pack_dir, "ontology.ttl"),
        work_order_shapes: Path.join(pack_dir, "shapes/work-order.shacl.ttl"),
        proposition_shapes: Path.join(pack_dir, "shapes/proposition.shacl.ttl")
      ] ++ contexts

    with {:ok, bytes} <- read_all(files),
         {:ok, graphs} <- parse_all(bytes, Keyword.keys(files)) do
      goal = graphs.goal

      data =
        Enum.reduce(Keyword.keys(contexts), RDF.Graph.add(graphs.ontology, goal), fn key, acc ->
          RDF.Graph.add(acc, Map.fetch!(graphs, key))
        end)

      shapes = RDF.Graph.add(graphs.work_order_shapes, graphs.proposition_shapes)

      data
      |> scoped_violations(shapes, subjects(goal), :goal_inadmissible)
      |> verdict()
      |> case do
        :ok -> {:ok, goal_summary(goal, bytes.goal)}
        refused -> refused
      end
    end
  end

  defp goal_summary(goal, bytes) do
    %{
      goal_sha256: Digest.sha256(bytes),
      triples: RDF.Graph.triple_count(goal),
      goal_checkpoints: length(instances(goal, sj("GoalCheckpoint"))),
      work_orders: length(instances(goal, sj("WorkOrder")))
    }
  end

  @doc "One human-readable line for a refusal."
  @spec render_refusal(refusal()) :: String.t()
  def render_refusal(%{code: code, subject: subject, detail: detail}) do
    "REFUSED(#{code}) #{subject || "-"}: #{detail}"
  end

  @doc """
  True when a receipt `subject` names `target`: equal, or ending in
  `/target`, `#target` or `:target` (a gate receipt subject such as
  `GC-26.9.23/GC23-0` names the gate identifier `GC23-0`; a compact IRI
  `v23:P-...` names the local name `P-...`).
  """
  @spec names?(String.t(), String.t()) :: boolean()
  def names?(subject, target) when is_binary(subject) and is_binary(target) do
    subject == target or
      Enum.any?(["/", "#", ":"], &String.ends_with?(subject, &1 <> target))
  end

  ## Inputs

  defp read_inputs(opts) do
    pack_dir = Keyword.get(opts, :pack_dir, @default_pack_dir)

    files = [
      source: Keyword.get(opts, :source),
      candidates: Keyword.get(opts, :candidates),
      goal: Keyword.get(opts, :goal),
      ontology: Path.join(pack_dir, "ontology.ttl"),
      work_order_shapes: Path.join(pack_dir, "shapes/work-order.shacl.ttl"),
      proposition_shapes: Path.join(pack_dir, "shapes/proposition.shacl.ttl")
    ]

    query_files = Enum.map(@queries, &{&1, Path.join([pack_dir, "prose", &1 <> ".rq"])})

    with {:ok, bytes} <- read_all(files),
         {:ok, queries} <- read_all(query_files),
         {:ok, graphs} <-
           parse_all(bytes, ~w(candidates goal ontology work_order_shapes proposition_shapes)a) do
      {:ok,
       %{
         source_path: files[:source],
         bytes: bytes,
         graphs: graphs,
         queries: queries,
         shapes: RDF.Graph.add(graphs.work_order_shapes, graphs.proposition_shapes)
       }}
    end
  end

  defp read_all(pairs) do
    {read, refusals} =
      Enum.reduce(pairs, {%{}, []}, fn {key, path}, {acc, refusals} ->
        case read_file(path) do
          {:ok, bytes} -> {Map.put(acc, key, bytes), refusals}
          {:error, detail} -> {acc, [refusal(:input_unreadable, path, detail) | refusals]}
        end
      end)

    if refusals == [], do: {:ok, read}, else: {:refused, Enum.reverse(refusals)}
  end

  defp read_file(nil), do: {:error, "required input path is missing"}

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, "cannot read: #{:file.format_error(reason)}"}
    end
  end

  defp parse_all(bytes, keys) do
    {graphs, refusals} =
      Enum.reduce(keys, {%{}, []}, fn key, {acc, refusals} ->
        case RDF.Turtle.read_string(Map.fetch!(bytes, key)) do
          {:ok, graph} ->
            {Map.put(acc, key, graph), refusals}

          {:error, reason} ->
            {acc, [refusal(:input_unreadable, Atom.to_string(key), inspect(reason)) | refusals]}
        end
      end)

    if refusals == [], do: {:ok, graphs}, else: {:refused, Enum.reverse(refusals)}
  end

  ## Root

  defp find_root(inputs) do
    roots =
      inputs.graphs.goal
      |> select(query(inputs, "root"))
      |> Enum.map(& &1["root"])
      |> Enum.uniq()
      |> Enum.sort_by(&to_string/1)

    case roots do
      [%RDF.IRI{} = root] ->
        {:ok, root_info(inputs.graphs.goal, root)}

      other ->
        {:refused,
         [
           refusal(
             :goal_root,
             nil,
             "expected exactly one root GoalCheckpoint (children, no parent), found #{length(other)}"
           )
         ]}
    end
  end

  defp root_info(goal, root) do
    iri = RDF.IRI.to_string(root)
    [namespace | _] = Regex.run(~r/\A.*[#\/]/, iri) || [iri]
    %{iri: root, namespace: namespace, description: RDF.Graph.get(goal, root)}
  end

  ## Admission

  defp admit(inputs, root) do
    source_sha = Digest.sha256(inputs.bytes.source)
    candidates = inputs.graphs.candidates
    propositions = propositions(candidates)

    [
      root_refusals(root, source_sha),
      foreign_subject_refusals(candidates, propositions),
      Enum.flat_map(propositions, &provenance_refusals(&1, candidates, inputs, root, source_sha)),
      shacl_refusals(inputs, candidates),
      rule_refusals(inputs, root)
    ]
    |> List.flatten()
    |> verdict()
  end

  defp propositions(graph) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.filter(&typed?(&1, sj("Proposition")))
    |> Enum.map(& &1.subject)
    |> Enum.sort_by(&term/1)
  end

  defp typed?(description, class), do: class in RDF.Description.get(description, @rdf_type, [])

  defp root_refusals(%{iri: root, description: description}, source_sha) do
    missing =
      for predicate <- ~w(repository baseSha),
          RDF.Description.first(description, sj(predicate)) == nil,
          do: refusal(:goal_incomplete, iri(root), "root GoalCheckpoint lacks sj:#{predicate}")

    case RDF.Description.first(description, sj("sourceSha256")) do
      nil ->
        missing

      digest ->
        if literal(digest) == source_sha,
          do: missing,
          else: [
            refusal(
              :provenance_mismatch,
              iri(root),
              "root sj:sourceSha256 #{literal(digest)} != source #{source_sha}"
            )
            | missing
          ]
    end
  end

  # Every subject of the candidate graph is a proposition or a hint node that
  # a proposition references through sj:falsifier / sj:acceptance, typed only
  # as that hint class and carrying only descriptive predicates.
  defp foreign_subject_refusals(candidates, propositions) do
    hints = hint_nodes(candidates, propositions)

    candidates
    |> RDF.Graph.descriptions()
    |> Enum.reject(&(&1.subject in propositions))
    |> Enum.flat_map(&foreign_subject(&1, Map.get(hints, &1.subject)))
    |> Enum.sort_by(& &1.subject)
  end

  defp hint_nodes(candidates, propositions) do
    for proposition <- propositions,
        {local, class} <- @hint_predicates,
        node <- RDF.Description.get(RDF.Graph.get(candidates, proposition), sj(local), []),
        into: %{},
        do: {node, sj(class)}
  end

  defp foreign_subject(description, nil) do
    [
      refusal(
        :foreign_subject,
        term(description.subject),
        "not a sj:Proposition nor a hint node referenced by one"
      )
    ]
  end

  defp foreign_subject(description, class) do
    types = RDF.Description.get(description, @rdf_type, [])

    extra =
      description |> RDF.Description.predicates() |> Enum.reject(&(&1 in @hint_node_predicates))

    if types == [class] and extra == [],
      do: [],
      else: [
        refusal(
          :foreign_subject,
          term(description.subject),
          "hint node must be typed only #{iri(class)} and carry only rdfs:label/rdfs:comment/dcterms:description"
        )
      ]
  end

  defp provenance_refusals(proposition, candidates, inputs, root, source_sha) do
    description = RDF.Graph.get(candidates, proposition)
    fields = ~w(propositionKind sourceDocument sourceSha256 sourceStart sourceEnd sourceText)

    case single_values(description, fields) do
      {:ok, values} ->
        span_refusals(proposition, values, inputs, root, source_sha)

      {:error, field} ->
        [refusal(:provenance_mismatch, term(proposition), "missing or multi-valued sj:#{field}")]
    end
  end

  defp single_values(description, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case RDF.Description.get(description, sj(field), []) do
        [value] -> {:cont, {:ok, Map.put(acc, field, value)}}
        _ -> {:halt, {:error, field}}
      end
    end)
  end

  defp span_refusals(proposition, values, inputs, root, source_sha) do
    subject = term(proposition)
    sha = literal(values["sourceSha256"])
    start = integer_value(values["sourceStart"])
    stop = integer_value(values["sourceEnd"])
    kind = literal(values["propositionKind"])

    [
      check(sha == source_sha, subject, "sj:sourceSha256 #{sha} != source #{source_sha}"),
      check(
        document_matches?(inputs.source_path, literal(values["sourceDocument"])),
        subject,
        "sj:sourceDocument #{literal(values["sourceDocument"])} does not name --source #{inputs.source_path}"
      ),
      span_check(subject, inputs.bytes.source, start, stop, literal(values["sourceText"])),
      iri_check(subject, root.namespace, sha, start, stop, kind)
    ]
    |> List.flatten()
  end

  defp check(true, _subject, _detail), do: []
  defp check(false, subject, detail), do: [refusal(:provenance_mismatch, subject, detail)]

  defp document_matches?(source_path, document) do
    expanded = Path.expand(source_path)
    expanded == Path.expand(document) or String.ends_with?(expanded, "/" <> document)
  end

  defp span_check(subject, source, start, stop, text)
       when is_integer(start) and is_integer(stop) and start >= 0 and start < stop and
              stop <= byte_size(source) do
    check(
      binary_part(source, start, stop - start) == text,
      subject,
      "source bytes [#{start}, #{stop}) != sj:sourceText"
    )
  end

  defp span_check(subject, source, start, stop, _text) do
    [
      refusal(
        :provenance_mismatch,
        subject,
        "span [#{inspect(start)}, #{inspect(stop)}) is not an integer span inside the #{byte_size(source)}-byte source"
      )
    ]
  end

  defp iri_check(subject, namespace, sha, start, stop, kind) do
    expected = proposition_iri(namespace, sha, start, stop, kind)
    check(subject == expected, subject, "IRI does not recompute per PVOCAB: expected #{expected}")
  end

  @doc "PVOCAB proposition IRI: `<ns>P-<first 16 hex of sha256(\"<sha>:<start>:<end>:<kind>\")>`."
  @spec proposition_iri(String.t(), String.t(), term(), term(), String.t()) :: String.t()
  def proposition_iri(namespace, sha, start, stop, kind) do
    namespace <> "P-" <> binary_part(Digest.hex("#{sha}:#{start}:#{stop}:#{kind}"), 0, 16)
  end

  @doc "Manufactured WorkOrder IRI: `<ns>WO-<first 16 hex of sha256(proposition IRI)>`."
  @spec order_iri(String.t(), String.t()) :: String.t()
  def order_iri(namespace, proposition),
    do: namespace <> "WO-" <> binary_part(Digest.hex(proposition), 0, 16)

  defp shacl_refusals(inputs, candidates) do
    data =
      inputs.graphs.ontology |> RDF.Graph.add(inputs.graphs.goal) |> RDF.Graph.add(candidates)

    scoped_violations(data, inputs.shapes, subjects(candidates), :shacl_violation)
  end

  defp scoped_violations(data, shapes, scope, code) do
    data
    |> Shacl.validate(shapes)
    |> Map.fetch!(:violations)
    |> Enum.filter(&(is_nil(&1.focus_node) or MapSet.member?(scope, &1.focus_node)))
    |> Enum.map(fn violation ->
      refusal(
        code,
        violation.focus_node,
        "#{violation.shape} #{violation.path || "-"} #{violation.constraint}: #{violation.message}" <>
          if(violation.value, do: " (#{violation.value})", else: "")
      )
    end)
    |> Enum.sort_by(&{&1.subject || "", &1.detail})
  end

  defp subjects(graph) do
    graph |> RDF.Graph.subjects() |> MapSet.new(&term/1)
  end

  defp rule_refusals(inputs, root) do
    data = RDF.Graph.add(inputs.graphs.goal, inputs.graphs.candidates)

    foreign =
      for row <- select(data, query(inputs, "foreign_requirements"), root),
          do:
            refusal(
              :foreign_requirement,
              term(row["proposition"]),
              "sj:requiredBy #{term(row["gate"])} is neither the root nor one of its gates"
            )

    contradictions =
      for row <- select(data, query(inputs, "contradictions"), root),
          do:
            refusal(
              :contradiction,
              term(row["exclusion"]),
              "Exclusion statement equals the required Postcondition " <>
                "#{term(row["postcondition"])} of #{term(row["gate"])}"
            )

    uncovered =
      for row <- select(data, query(inputs, "uncovered_gates"), root),
          do:
            refusal(
              :uncovered_gate,
              term(row["gate"]),
              "no admitted proposition has sj:requiredBy this gate"
            )

    Enum.sort_by(foreign ++ contradictions ++ uncovered, &{&1.code, &1.subject, &1.detail})
  end

  ## Receipts (AdmittedCurrentState)

  defp read_receipts(nil), do: {:ok, []}

  defp read_receipts(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        {:ok,
         names
         |> Enum.filter(&String.ends_with?(&1, ".json"))
         |> Enum.sort()
         |> Enum.flat_map(&alive_receipt(Path.join(dir, &1)))}

      {:error, reason} ->
        {:refused,
         [
           refusal(
             :input_unreadable,
             dir,
             "cannot list receipts dir: #{:file.format_error(reason)}"
           )
         ]}
    end
  end

  # A witness is a fleet R-schema object (identity/authority/consequence/
  # replay/standing all present) with standing.value ALIVE and a string
  # identity.subject. Anything else witnesses nothing.
  defp alive_receipt(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok,
          %{"identity" => %{"subject" => subject}, "standing" => %{"value" => "ALIVE"}} = receipt}
         when is_binary(subject) <- Jason.decode(bytes),
         true <- Enum.all?(~w(authority consequence replay), &Map.has_key?(receipt, &1)) do
      [%{subject: subject, file: Path.basename(path), digest: Digest.hex(bytes)}]
    else
      _ -> []
    end
  end

  ## Manufacture

  defp manufacture(inputs, root, receipts) do
    context = admission_context(inputs)
    admitted = admitted_graph(inputs.graphs.candidates, context)
    witness = witness_graph(admitted, inputs.graphs.goal, receipts)

    orders =
      inputs.graphs.goal
      |> RDF.Graph.add(admitted)
      |> RDF.Graph.add(witness)
      |> construct(query(inputs, "delta.construct"), root)

    expected = expected_orders(admitted, witness, root.namespace)
    actual = orders |> instances(sj("WorkOrder")) |> MapSet.new()

    with :ok <- conservation(expected, actual),
         :ok <- admit_orders(inputs, orders) do
      {:ok,
       result(
         inputs,
         context,
         admitted,
         orders,
         summary(inputs, admitted, witness, actual, receipts)
       )}
    end
  end

  defp admission_context(inputs) do
    inputs.bytes
    |> Map.merge(Map.new(inputs.queries, fn {name, bytes} -> {"query:" <> name, bytes} end))
    |> Enum.map(fn {key, bytes} -> "#{key}=#{Digest.sha256(bytes)}" end)
    |> Enum.sort()
    |> Enum.join("\n")
    |> Digest.sha256()
  end

  defp admitted_graph(candidates, context) do
    candidate_standing = sj("candidateStanding")

    Enum.reduce(propositions(candidates), candidates, fn proposition, graph ->
      description =
        graph
        |> RDF.Graph.get(proposition)
        |> RDF.Description.delete_predicates(candidate_standing)

      digest =
        Digest.sha256(
          context <>
            "\n" <> term(proposition) <> "\n" <> sorted_ntriples(RDF.Graph.new(description))
        )

      graph
      |> RDF.Graph.delete_descriptions(proposition)
      |> RDF.Graph.add(
        RDF.Description.add(description, {sj("admissionDigest"), RDF.literal(digest)})
      )
    end)
  end

  # Projects each ALIVE receipt that names an admitted proposition or its
  # required checkpoint as `<target> sj:receipt <urn:sha256:...>` plus
  # `<urn:...> a sj:Receipt ; sj:standing "ALIVE"` -- the representation the
  # xaas stop court uses for admitted receipts.
  defp witness_graph(admitted, goal, receipts) do
    targets = witness_targets(admitted, goal)

    for receipt <- receipts,
        {target, names} <- targets,
        Enum.any?(names, &names?(receipt.subject, &1)),
        reduce: RDF.Graph.new() do
      graph ->
        node = RDF.iri("urn:sha256:" <> receipt.digest)

        RDF.Graph.add(graph, [
          {target, sj("receipt"), node},
          {node, @rdf_type, sj("Receipt")},
          {node, sj("standing"), RDF.literal("ALIVE")}
        ])
    end
  end

  defp witness_targets(admitted, goal) do
    props = propositions(admitted)

    gates =
      props
      |> Enum.flat_map(&RDF.Description.get(RDF.Graph.get(admitted, &1), sj("requiredBy"), []))
      |> Enum.uniq()

    Enum.map(props, &{&1, [iri(&1), local(&1)]}) ++
      Enum.map(gates, fn gate -> {gate, [iri(gate), local(gate) | identifiers(goal, gate)]} end)
  end

  defp identifiers(goal, node) do
    case RDF.Graph.get(goal, node) do
      nil ->
        []

      description ->
        description
        |> RDF.Description.get(RDF.iri(@dcterms <> "identifier"), [])
        |> Enum.map(&literal/1)
    end
  end

  # Conservation twin of delta.construct.rq: the orders that MUST exist,
  # recomputed from the admitted graph and the witness projection alone.
  defp expected_orders(admitted, witness, namespace) do
    admitted
    |> propositions()
    |> Enum.map(&RDF.Graph.get(admitted, &1))
    |> Enum.filter(&delta_order?(&1, witness))
    |> MapSet.new(&order_iri(namespace, term(&1.subject)))
  end

  defp delta_order?(description, witness) do
    kind = literal(RDF.Description.first(description, sj("propositionKind")))
    gate = RDF.Description.first(description, sj("requiredBy"))

    kind in @delta_kinds and gate != nil and not witnessed?(witness, description.subject) and
      not witnessed?(witness, gate)
  end

  defp witnessed?(witness, node) do
    case RDF.Graph.get(witness, node) do
      nil -> false
      description -> RDF.Description.get(description, sj("receipt"), []) != []
    end
  end

  defp conservation(expected, actual) do
    missing = MapSet.difference(expected, actual)
    extra = MapSet.difference(actual, expected)

    (Enum.map(
       Enum.sort(missing),
       &refusal(:delta_nonconservation, &1, "required delta order was not manufactured")
     ) ++
       Enum.map(
         Enum.sort(extra),
         &refusal(:delta_nonconservation, &1, "manufactured order is not in the required delta")
       ))
    |> verdict()
  end

  defp admit_orders(inputs, orders) do
    inputs.graphs.ontology
    |> RDF.Graph.add(inputs.graphs.goal)
    |> RDF.Graph.add(orders)
    |> scoped_violations(inputs.shapes, subjects(orders), :order_inadmissible)
    |> verdict()
  end

  defp instances(graph, class) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.filter(&typed?(&1, class))
    |> Enum.map(&term(&1.subject))
  end

  ## Serialization and summary

  defp result(inputs, context, admitted, orders, summary) do
    header = [
      "# GENERATED by mix semantic_jira.compile_prose (ggen_igniter GgenIgniter.SemanticJira.Prose); do not edit.",
      "# source: #{summary.source_document} #{Digest.sha256(inputs.bytes.source)}",
      "# candidates: #{Digest.sha256(inputs.bytes.candidates)}; goal: #{Digest.sha256(inputs.bytes.goal)}",
      "# admission context: #{context}"
    ]

    propositions_ttl =
      render(
        header ++ ["# admitted propositions: #{summary.admitted} (required #{summary.required})"],
        admitted
      )

    orders_ttl =
      render(
        header ++
          [
            "# work orders: #{summary.orders} (#{summary.witnessed} required propositions witnessed ALIVE)"
          ],
        orders
      )

    summary =
      Map.merge(summary, %{
        admission_context: context,
        propositions_sha256: Digest.sha256(propositions_ttl),
        orders_sha256: Digest.sha256(orders_ttl)
      })

    %{propositions_ttl: propositions_ttl, orders_ttl: orders_ttl, summary: summary}
  end

  defp render(header, graph), do: Enum.join(header, "\n") <> "\n\n" <> sorted_ntriples(graph)

  defp sorted_ntriples(graph) do
    graph
    |> RDF.NTriples.write_string!()
    |> String.split("\n", trim: true)
    |> Enum.sort()
    |> Enum.map_join("", &(&1 <> "\n"))
  end

  defp summary(inputs, admitted, witness, orders, receipts) do
    props = Enum.map(propositions(admitted), &RDF.Graph.get(admitted, &1))
    required = Enum.filter(props, &(RDF.Description.first(&1, sj("requiredBy")) != nil))

    delta_required =
      Enum.filter(
        required,
        &(literal(RDF.Description.first(&1, sj("propositionKind"))) in @delta_kinds)
      )

    %{
      source_document:
        props
        |> Enum.map(&literal(RDF.Description.first(&1, sj("sourceDocument"))))
        |> Enum.min(fn -> "-" end),
      admitted: length(props),
      required: length(required),
      not_required: length(props) - length(required),
      by_kind:
        Enum.frequencies_by(props, &literal(RDF.Description.first(&1, sj("propositionKind")))),
      required_by:
        Enum.frequencies_by(
          required,
          &gate_name(inputs.graphs.goal, RDF.Description.first(&1, sj("requiredBy")))
        ),
      delta_required: length(delta_required),
      witnessed:
        Enum.count(
          delta_required,
          &(witnessed?(witness, &1.subject) or gate_witnessed?(witness, &1))
        ),
      orders: MapSet.size(orders),
      receipts_alive: length(receipts)
    }
  end

  defp gate_witnessed?(witness, description) do
    witnessed?(witness, RDF.Description.first(description, sj("requiredBy")))
  end

  defp gate_name(goal, gate) do
    case identifiers(goal, gate) do
      [identifier | _] -> identifier
      [] -> iri(gate)
    end
  end

  ## SPARQL helpers

  defp query(inputs, name), do: Map.fetch!(inputs.queries, name)

  defp select(graph, query, root \\ nil) do
    case SPARQL.execute_query(graph, bind(query, root)) do
      %SPARQL.Query.Result{results: rows} -> rows
      {:error, reason} -> raise ArgumentError, "prose query failed: #{inspect(reason)}"
    end
  end

  defp construct(graph, query, root) do
    case SPARQL.execute_query(graph, bind(query, root)) do
      %RDF.Graph{} = constructed -> constructed
      other -> raise ArgumentError, "delta.construct.rq did not return a graph: #{inspect(other)}"
    end
  end

  # Binds ?root and ?ns by injecting BINDs at the head of the first WHERE
  # group -- the same technique GgenIgniter.SemanticJira.Shacl uses for $this
  # (sparql 0.3.12 has no pre-binding API and ignores VALUES).
  defp bind(query, nil), do: query

  defp bind(query, %{iri: root, namespace: namespace}) do
    Regex.replace(
      ~r/WHERE\s*\{/i,
      query,
      "WHERE { BIND(<#{iri(root)}> AS ?root) BIND(\"#{namespace}\" AS ?ns) ",
      global: false
    )
  end

  ## Term helpers

  defp verdict([]), do: :ok
  defp verdict(refusals), do: {:refused, refusals}

  defp drift(path, expected) do
    case File.read(path) do
      {:ok, ^expected} ->
        []

      {:ok, _other} ->
        [refusal(:output_drift, path, "existing output differs from the recomputed bytes")]

      {:error, reason} ->
        [refusal(:output_drift, path, "cannot read: #{:file.format_error(reason)}")]
    end
  end

  defp refusal(code, subject, detail), do: %{code: code, subject: subject, detail: detail}

  defp sj(local), do: RDF.iri(@sj <> local)

  defp iri(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)

  defp term(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp term(other), do: to_string(other)

  defp local(%RDF.IRI{} = iri) do
    iri |> RDF.IRI.to_string() |> String.split(["#", "/"]) |> List.last()
  end

  defp integer_value(%RDF.Literal{} = literal) do
    value = RDF.Literal.value(literal)
    if is_integer(value), do: value, else: RDF.Literal.lexical(literal)
  end

  defp integer_value(other), do: term(other)

  defp literal(nil), do: nil
  defp literal(%RDF.Literal{} = literal), do: RDF.Literal.lexical(literal)
  defp literal(other), do: term(other)
end
