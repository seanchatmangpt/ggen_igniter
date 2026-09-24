defmodule GgenIgniter.SemanticJira.Bootstrap.Graph do
  @moduledoc """
  Canonical-RDF side of the cold bootstrap (GC23-1): the pack queries
  `priv/ggen/semantic-jira-pack/bootstrap/*.rq` (plus `prose/root.rq`, the
  root law the first-mile compiler already uses) run over the goal graph and
  the work graphs; this module only groups their rows.

  Work orders become two shapes:

    * the kernel map `GgenIgniter.SemanticJira.admit_work_order/1` admits
      (standing is filled in later from receipts; `sj:standing` literals are
      never selected -- PR-006);
    * the contract tuple the stop court digests (`subject`, `postcondition`,
      `capability` = the `sj:capabilityId` of the single required capability,
      `evidence_ceiling`, `authority_ceiling`, `consequence_class`,
      `exclusions` sorted), with `tuple_digest/1` byte-compatible with
      `mix xaas.stop_court` (Python `json.dumps(sort_keys=True,
      separators=(",", ":"), ensure_ascii=False)`). Each scalar must have
      exactly one value (`{:incomplete, field}` / `{:ambiguous, field}`
      otherwise); `sj:exclusion` is 0..n by the shared vocabulary contract,
      so an order with no exclusion is complete and digests
      `"exclusions":[]` -- the semantic-jira-pack `sj:FridayWorkOrderShape`
      rule and xaas `Xaas.Sa2a.Route.admit_field/2`. (xaas
      `mix xaas.stop_court`'s own `order_tuple` still reports such an order
      `{:incomplete, "exclusions"}`; that xaas-side alignment belongs to lane
      V23-K.)

  JSON work graphs (a kernel work-order array, or `{"work_orders": [...]}`,
  the shape `mix semantic_jira.frontier --work-orders` reads) are carried
  as-is, except that their `standing` is ignored: standing is derived.
  """

  alias GgenIgniter.Digest

  @queries ~w(work_orders dependencies checkpoints capabilities fleet)
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @tuple_scalars ~w(subject postcondition capability evidence_ceiling authority_ceiling consequence_class)
  @kernel_scalars ~w(identity title description subject repository base_sha candidate_sha
    evidence_ceiling authority_requirement promotion_rule replay_identity
    origin_authority origin_observation)
  @kernel_lists ~w(required_courts required_evidence required_receipt_classes acceptance
    falsifiers projections path_scope)

  @type order :: %{
          required(:id) => String.t(),
          required(:iri) => String.t() | nil,
          required(:source) => String.t(),
          required(:fields) => %{String.t() => [String.t()]},
          required(:kernel) => map(),
          required(:tuple) => {:ok, map(), String.t()} | {:incomplete | :ambiguous, String.t()}
        }

  @doc "Names of the pack query files this module reads (bootstrap/<name>.rq)."
  @spec query_names() :: [String.t()]
  def query_names, do: @queries

  @doc "Reads the pack queries: `%{name => text}` including `\"root\"` (prose/root.rq)."
  @spec read_queries(Path.t()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def read_queries(pack_dir) do
    paths =
      [{"root", Path.join([pack_dir, "prose", "root.rq"])}] ++
        Enum.map(@queries, &{&1, Path.join([pack_dir, "bootstrap", &1 <> ".rq"])})

    Enum.reduce_while(paths, {:ok, %{}}, fn {name, path}, {:ok, acc} ->
      case File.read(path) do
        {:ok, text} -> {:cont, {:ok, Map.put(acc, name, text)}}
        {:error, reason} -> {:halt, {:error, "pack query #{name}: #{:file.format_error(reason)}"}}
      end
    end)
  end

  @doc "Parses Turtle bytes."
  @spec parse(binary()) :: {:ok, RDF.Graph.t()} | {:error, String.t()}
  def parse(bytes) do
    case RDF.Turtle.read_string(bytes) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @doc "The single root GoalCheckpoint IRI of `goal` (prose/root.rq law)."
  @spec root(RDF.Graph.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def root(goal, queries) do
    goal
    |> select(queries["root"])
    |> Enum.map(&term(&1["root"]))
    |> Enum.uniq()
    |> case do
      [root] -> {:ok, root}
      many -> {:error, "expected exactly one root GoalCheckpoint, found #{length(many)}"}
    end
  end

  @doc "GoalCheckpoint fields: `%{iri => %{field => [values]}}`."
  @spec checkpoints(RDF.Graph.t(), map()) :: %{String.t() => map()}
  def checkpoints(graph, queries),
    do: graph |> select(queries["checkpoints"]) |> group("checkpoint")

  @doc "Capability IRI -> sorted capabilityId values."
  @spec capabilities(RDF.Graph.t(), map()) :: %{String.t() => [String.t()]}
  def capabilities(graph, queries) do
    graph
    |> select(queries["capabilities"])
    |> Enum.group_by(&term(&1["capability"]), &term(&1["capability_id"]))
    |> Map.new(fn {iri, ids} -> {iri, ids |> Enum.uniq() |> Enum.sort()} end)
  end

  @doc "Fleet matrix rows (fleet.rq) as plain maps."
  @spec fleet_rows(RDF.Graph.t(), map()) :: [map()]
  def fleet_rows(graph, queries) do
    graph
    |> select(queries["fleet"])
    |> Enum.map(fn row ->
      %{
        name: term(row["name"]),
        path: term(row["path"]),
        class: row["class"] && local_name(term(row["class"])),
        required: term(row["required"]) == "true",
        recorded_sha: term(row["recorded_sha"])
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Work orders of an RDF graph: `[order]` sorted by identity. `source` is the
  input ref recorded on every order.
  """
  @spec orders(RDF.Graph.t(), map(), String.t()) :: [order()]
  def orders(graph, queries, source) do
    dependencies = graph |> select(queries["dependencies"]) |> dependencies()

    graph
    |> select(queries["work_orders"])
    |> group("work_order")
    |> Enum.map(fn {iri, fields} ->
      id = first(fields["identity"]) || iri
      deps = Map.get(dependencies, iri, [])

      %{
        id: id,
        iri: iri,
        source: source,
        fields: fields,
        kernel: kernel(fields, id, deps),
        tuple: rdf_tuple(fields)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  @doc "Work orders of a decoded JSON work graph."
  @spec json_orders(term(), String.t()) :: {:ok, [order()]} | {:error, String.t()}
  def json_orders(decoded, source) do
    case decoded do
      list when is_list(list) -> json_list(list, source)
      %{"work_orders" => list} when is_list(list) -> json_list(list, source)
      _ -> {:error, "expected a JSON array or {\"work_orders\": [...]}"}
    end
  end

  defp json_list(list, source) do
    if Enum.all?(list, &(is_map(&1) and is_binary(&1["identity"]) and &1["identity"] != "")) do
      orders =
        list
        |> Enum.map(fn raw ->
          kernel = raw |> Map.delete("standing") |> Map.put("identity", raw["identity"])

          %{
            id: raw["identity"],
            iri: nil,
            source: source,
            fields: json_fields(raw),
            kernel: kernel,
            tuple: json_tuple(raw)
          }
        end)
        |> Enum.sort_by(& &1.id)

      {:ok, orders}
    else
      {:error, "every JSON work order must be an object with a non-empty \"identity\""}
    end
  end

  defp json_fields(raw) do
    for key <- ~w(checkpoint_of boundary_class authority_ceiling),
        is_binary(raw[key]),
        into: %{} do
      {key, [raw[key]]}
    end
  end

  @doc """
  The stop-court contract tuple digest: `"sha256:" <> hex(sha256(json))` over
  the tuple keys sorted, `exclusions` sorted (`[]` when the order has none).
  """
  @spec tuple_digest(map()) :: String.t()
  def tuple_digest(tuple) do
    encoded =
      ["exclusions" | @tuple_scalars]
      |> Enum.sort()
      |> Enum.map(fn
        "exclusions" -> {"exclusions", tuple |> Map.fetch!("exclusions") |> Enum.sort()}
        field -> {field, Map.fetch!(tuple, field)}
      end)
      |> Jason.OrderedObject.new()
      |> Jason.encode!()

    Digest.sha256(encoded)
  end

  # ── kernel projection ───────────────────────────────────────────────────

  defp kernel(fields, id, dependencies) do
    scalars =
      for key <- @kernel_scalars, value = first(fields[key]), into: %{}, do: {key, value}

    lists = for key <- @kernel_lists, into: %{}, do: {key, Map.get(fields, key, [])}

    scalars
    |> Map.merge(lists)
    |> Map.put("identity", id)
    |> Map.put("dependencies", dependencies)
  end

  # Only single-valued scalars reach the kernel; an ambiguous scalar is left
  # out, so kernel admission refuses the order naming the field.
  defp first([value]), do: value
  defp first(_none_or_many), do: nil

  defp dependencies(rows) do
    rows
    |> Enum.group_by(&term(&1["work_order"]), fn row ->
      %{
        "type" => term(row["type"]),
        "upstream" => term(row["upstream_id"]) || term(row["upstream"]),
        "required_standing" => term(row["required_standing"])
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
    |> Map.new(fn {iri, deps} ->
      {iri, deps |> Enum.uniq() |> Enum.sort_by(&{&1["upstream"], &1["type"]})}
    end)
  end

  defp rdf_tuple(fields) do
    capability =
      case Map.get(fields, "capability_node", []) do
        [_one] -> Map.get(fields, "capability", [])
        many -> many
      end

    fields
    |> Map.put("capability", capability)
    |> tuple_from(fn field -> Map.get(fields, field, []) end)
  end

  defp json_tuple(raw) do
    tuple_from(raw, fn
      "exclusions" -> raw |> Map.get("exclusions", []) |> List.wrap()
      field -> raw |> Map.get(field) |> List.wrap()
    end)
  end

  defp tuple_from(source, values_of) do
    capability_values =
      if is_map_key(source, "capability"), do: List.wrap(source["capability"]), else: []

    scalars =
      Enum.map(@tuple_scalars, fn
        "capability" -> {"capability", capability_values}
        field -> {field, values_of.(field)}
      end)

    # sj:exclusion is 0..n: no exclusion is the empty list, never incomplete.
    scalars
    |> Enum.reduce_while({:ok, %{"exclusions" => values_of.("exclusions")}}, &tuple_field/2)
    |> case do
      {:ok, tuple} -> {:ok, tuple, tuple_digest(tuple)}
      refusal -> refusal
    end
  end

  defp tuple_field({field, [value]}, {:ok, acc}) when is_binary(value),
    do: {:cont, {:ok, Map.put(acc, field, value)}}

  defp tuple_field({field, []}, _acc), do: {:halt, {:incomplete, field}}
  defp tuple_field({field, _many}, _acc), do: {:halt, {:ambiguous, field}}

  # ── SPARQL rows ─────────────────────────────────────────────────────────

  defp select(graph, query) do
    case SPARQL.execute_query(graph, query) do
      %SPARQL.Query.Result{results: rows} -> rows
      {:error, reason} -> raise ArgumentError, "bootstrap pack query failed: #{inspect(reason)}"
    end
  end

  defp group(rows, key) do
    rows
    |> Enum.group_by(&term(&1[key]))
    |> Map.new(fn {iri, subject_rows} ->
      fields =
        subject_rows
        |> Enum.group_by(&term(&1["field"]), &term(&1["value"]))
        |> Map.new(fn {field, values} -> {field, values |> Enum.uniq() |> Enum.sort()} end)

      {iri, fields}
    end)
  end

  @doc "Lexical form of an RDF term (`nil` stays `nil`)."
  @spec term(term()) :: String.t() | nil
  def term(nil), do: nil
  def term(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  def term(%RDF.Literal{} = literal), do: RDF.Literal.lexical(literal)
  def term(%RDF.BlankNode{} = node), do: to_string(node)
  def term(other), do: to_string(other)

  @doc "The local name of an IRI (after the last `#` or `/`)."
  @spec local_name(String.t()) :: String.t()
  def local_name(iri), do: iri |> String.split(["#", "/"]) |> List.last()

  @doc "The `sj:` namespace."
  @spec sj() :: String.t()
  def sj, do: @sj
end
