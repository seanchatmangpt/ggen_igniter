defmodule GgenIgniter.SemanticJira.CourtMap do
  @moduledoc """
  Projects a work order's court map out of the pack ontology.

  The court map is UPSTREAM data: the ontology records, on each acceptance
  (`sj:AcceptanceCriterion`) and falsifier (`sj:Falsifier`) node, the ONE
  suite test that witnesses it (`sj:witnessedBy "path/to/test.py::test_name"`).
  `from_ontology/2` reads those facts for one `sj:WorkOrder` identity and
  emits exactly the shape the fabric court-receipt producer consumes
  (`Xaas.Ultracode.CourtReceipt.admit/1`):

      %{"acceptance" => %{iri => %{"test" => id}},
        "falsifiers" => %{iri => %{"test" => id}},
        "courts"     => [court_iri, ...]}

  Fail-closed: a work order whose acceptance or falsifier IRIs lack a
  `sj:witnessedBy` fact is a typed refusal, never a partial map -- a court
  predicate the ontology does not record must not quietly become "no court".
  A work order with no acceptance/falsifier/court facts at all is also
  refused: a court map is minted for work orders that REQUIRE one.

  The parser is a conservative reader of the pack's own generated Turtle
  (the `Observation.candidate` projection shape: `@prefix sj:` blocks,
  period-terminated statements, prefixed or full-IRI subjects). It parses
  nothing it does not recognize; an unrecognized shape is a refusal, not a
  guess.
  """

  @type predicate :: %{optional(binary()) => binary()}

  @type court_map :: %{
          String.t() => %{String.t() => predicate()} | [String.t()]
        }

  @spec from_ontology(String.t(), String.t()) :: {:ok, court_map()} | {:error, term()}
  def from_ontology(ttl, identity) when is_binary(ttl) and is_binary(identity) do
    prefix = prefix(ttl)

    with {:ok, block} <- work_order(ttl, identity),
         {:ok, acceptance} <- group(block, "acceptance", prefix, ttl),
         {:ok, falsifiers} <- group(block, "falsifier", prefix, ttl),
         {:ok, courts} <- courts(block, prefix) do
      if acceptance == %{} and falsifiers == %{} and courts == [] do
        {:error, {:court_map_refused, {:no_court_facts, identity}}}
      else
        {:ok, %{"acceptance" => acceptance, "falsifiers" => falsifiers, "courts" => courts}}
      end
    end
  end

  def from_ontology(_, _), do: {:error, {:court_map_refused, :not_a_string}}

  # --- ontology readers ------------------------------------------------------

  defp prefix(ttl) do
    case Regex.run(~r/@prefix\s+sj:\s+<([^>]+)>\s*\./, ttl) do
      [_, iri] -> iri
      nil -> "https://ggen-igniter.dev/ontology/semantic-jira#"
    end
  end

  defp work_order(ttl, identity) do
    ttl
    |> statements()
    |> Enum.find(fn statement ->
      String.contains?(statement, ~s(dcterms:identifier "#{identity}")) and
        Regex.match?(~r/\bsj:WorkOrder\b/, statement)
    end)
    |> case do
      nil -> {:error, {:court_map_refused, {:work_order_not_found, identity}}}
      statement -> {:ok, statement}
    end
  end

  # The typed group predicate on the work order ("sj:acceptance", singular
  # "sj:falsifier", "sj:requiresCourt") carries one or more IRIs.
  defp group(block, predicate, prefix, ttl) do
    case objects(block, "sj:#{predicate}", prefix) do
      [] -> {:error, {:court_map_refused, {:missing_predicate, predicate}}}
      iris -> witnesses(iris, ttl, prefix)
    end
  end

  defp witnesses(iris, ttl, prefix) do
    Enum.reduce_while(iris, {:ok, %{}}, fn iri, {:ok, acc} ->
      case witness(ttl, iri, prefix) do
        {:ok, test_id} -> {:cont, {:ok, Map.put(acc, iri, %{"test" => test_id})}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp witness(ttl, iri, prefix) do
    ttl
    |> statements()
    |> Enum.find(fn statement ->
      String.starts_with?(statement, "<#{iri}>") or
        String.starts_with?(statement, "sj:" <> String.replace_prefix(iri, prefix, ""))
    end)
    |> case do
      nil ->
        {:error, {:court_map_refused, {:node_not_found, iri}}}

      statement ->
        case Regex.run(~r/sj:witnessedBy\s+"([^"]+)"/, statement) do
          [_, test_id] -> {:ok, test_id}
          nil -> {:error, {:court_map_refused, {:unwitnessed, iri}}}
        end
    end
  end

  defp courts(block, prefix) do
    case objects(block, "sj:requiresCourt", prefix) do
      [] -> {:ok, []}
      iris -> {:ok, iris}
    end
  end

  # --- conservative Turtle statement reader -----------------------------------

  defp statements(ttl) do
    ttl
    |> String.split([".\n", ".\r\n"], trim: false)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "@") or String.starts_with?(&1, "#")))
  end

  # Objects of one predicate inside one statement: `sj:predicate <iri>, <iri> ;`
  # or `sj:predicate sj:name, sj:name2 ;` -- commas and continuation lines are
  # part of the same statement text.
  defp objects(statement, predicate, prefix) do
    # Objects run to the statement's ';' terminator (dots occur inside IRIs,
    # e.g. https://...; the statement splitter already consumed terminators).
    pattern = Regex.escape(predicate) <> "\\s+([^;]+);?"

    case Regex.run(Regex.compile!(pattern), statement) do
      [_, body] ->
        body
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or &1 == "."))
        |> Enum.map(fn
          "<" <> rest -> String.trim_trailing(rest, ">")
          "sj:" <> named -> prefix <> named
          other -> other
        end)

      nil ->
        []
    end
  end
end
