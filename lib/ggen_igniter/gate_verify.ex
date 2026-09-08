defmodule GgenIgniter.GateVerify do
  @moduledoc """
  GGEN-1806 (`docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md`): post-sync,
  per-gate SPARQL verification. "Sync succeeded" (`GgenIgniter.SyncShellout`'s
  `{:ok, output}`) and "the pack's own contract holds" are separate,
  independently observable outcomes -- mirroring
  `lib/mix/tasks/ggen_igniter.doctor.ex`'s `check_hex_publish_readiness/0`
  precedent of not conflating subprocess success with the actual property
  being checked.

  Gate discovery reuses `GgenIgniter.Pack.discover_queries/1` (the existing
  `<pack_dir>/gates/*.rq` convention, `priv/ggen/CLAUDE.md`). Each gate query
  is executed for real via `GgenIgniter.Query.run/2` against the regenerated
  ontology graph (`GgenIgniter.Ontology.load!/1`). A gate's pass/fail
  convention mirrors this pack corpus's own `SELECT DISTINCT` existence-check
  style (see `priv/ggen/adr-index-pack/gates/010_adrs.rq` and every other
  pack's `gates/*.rq`): a gate **passes** when its query returns at least one
  row (the required ontology shape/individual is present), and **fails** when
  it returns zero rows.

  Never a single aggregate boolean: `run/3` returns a typed, per-gate
  `[{gate_name, :pass | :fail}]` list on full success, or a typed refusal
  naming the specific first failed gate on any failure.

  ## The fail-open problem this module now has two answers to

  Every gate in `test/fixtures/ash_manufacture_pack/gates/` is a CONJUNCTIVE
  `SELECT`, so the `>= 1 row` rule above FAILS OPEN. Measured, not argued:
  deleting `amp:primaryKeyKind` from `amp:BookResource` drops
  `gates/030_resources.rq` from 2 rows to 1 while `gates/040_attributes.rq`
  still returns all 9 rows -- so Book's 5 attributes are projected onto a
  resource that will never be generated, and the gate still scores `:pass`.
  Deleting one `amp:evidence` triple (a documentation citation) drops the
  whole `ash.install` capability from `gates/080_capabilities.rq` (21 rows to
  20), and because the manufacture template gates the install step on that
  capability's admission, the Ash installation silently vanishes.

  Two complementary mechanisms answer it, and they catch different residue:

    * **Inverted companion queries**, `<pack_dir>/verify/*.unbound.rq` --
      run by `verify_unbound/2`. Each re-emits one conjunct of its gate as a
      refutation returning `?subject ?missing_property`, so ZERO ROWS is the
      pass condition and a defect is NAMED. They anchor on `?subject a
      amp:Class`, so an individual that loses its `rdf:type` outright is
      invisible to them.
    * **A per-gate cardinality contract**, `run/3`'s `:cardinality` option --
      "this gate must emit exactly one row per subject the graph says should
      be there" (`ROWS`), or "per (subject, value) pair" (`VALUES`). It
      catches drops the queries cannot model, without naming which fact went
      missing.

  ## Every cardinality anchor has one blind spot, so the anchor is a choice

  A contract compares a gate's row count against a count derived from the same
  graph, so it is structurally blind to any deletion that moves BOTH numbers
  together -- that is, to the loss of its own anchor. Measured, on the real
  `test/fixtures/ash_manufacture_pack` ontology, across seven mutation classes:

    * Anchored on a CLASS (`?s a <C>`), deleting a Resource's `rdf:type`
      dropped the `resources` gate from 2 rows to 1 AND the contract count
      from 2 to 1 -- undetected. The inverted queries are blind to the same
      deletion, because they anchor on `?subject a amp:Resource` too. Both
      mechanisms sharing one blind spot leaves it uncovered.
    * Anchored on a PREDICATE (`?s <P> ?v`), the same deletion gave gate 1 vs
      contract 2 -- CAUGHT. The predicate anchor's own blind spot is the loss
      of `P` itself (gate 1 vs contract 1), and THAT is precisely what the
      inverted companion query names.

  So a predicate anchor and an inverted companion have DISJOINT blind spots,
  and a class anchor and an inverted companion do not. Every contract in
  `test/fixtures/ash_manufacture_pack/verify/cardinality.json` is therefore
  predicate-anchored. The class anchor is kept because it is the right choice
  for a gate whose anchor predicate is shared across classes; it is a weaker
  default, not a wrong one.

  ## The cardinality contract is ADDITIVE

  A gate with no contract entry keeps the documented `>= 1 row` behaviour
  exactly. Other packs in this repo were authored against that rule and ship
  no `verify/cardinality.json` at all; flipping the default would be a silent
  breaking change to packs this module cannot inspect. `run/2` therefore still
  exists with its original meaning, and `run/3` with no `:cardinality` option
  is identical to it.

  Precedence inside a gate is likewise unchanged-first: the zero-rows
  `:gate_failed` check runs BEFORE the cardinality check, so no input that
  fails today starts failing with a different error tomorrow.
  """

  @doc """
  Runs every `<pack_dir>/gates/*.rq` query against the ontology graph loaded
  from `ontology_path`, in the pack's own lexical (`NNN_name.rq`) order.

  `opts`:

    * `:cardinality` -- a map of `gate_stem => contract`, as produced by
      `load_cardinality/1`. Absent (the default), no gate carries a contract
      and behaviour is identical to `run/2`.

  Returns:

    * `{:ok, [{gate_name, :pass}, ...]}` when every gate passes -- a real,
      individually-inspectable list, never a bare `true`.
    * `{:error, {:gate_failed, gate_name}}` naming the first gate (in pack
      order) whose query returned zero rows.
    * `{:error, {:gate_cardinality, gate_name, expected, actual}}` naming the
      first gate whose row count disagrees with its declared contract.
      `expected` is derived from the graph, `actual` is the gate's real row
      count.
  """
  @spec run(String.t(), String.t(), keyword()) ::
          {:ok, [{String.t(), :pass}]}
          | {:error, {:gate_failed, String.t()}}
          | {:error, {:gate_cardinality, String.t(), non_neg_integer(), non_neg_integer()}}
  def run(pack_dir, ontology_path, opts \\ [])
      when is_binary(pack_dir) and is_binary(ontology_path) and is_list(opts) do
    graph = GgenIgniter.Ontology.load!(ontology_path)
    contracts = Keyword.get(opts, :cardinality, %{})

    pack_dir
    |> GgenIgniter.Pack.discover_queries()
    |> Enum.reduce_while([], fn {name, path}, acc ->
      case gate_status(graph, path, Map.get(contracts, name)) do
        :pass ->
          {:cont, [{name, :pass} | acc]}

        :fail ->
          {:halt, {:error, {:gate_failed, name}}}

        {:cardinality, expected, actual} ->
          {:halt, {:error, {:gate_cardinality, name, expected, actual}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      results -> {:ok, Enum.reverse(results)}
    end
  end

  defp gate_status(graph, query_path, contract) do
    rows = GgenIgniter.Query.run(graph, File.read!(query_path))

    # The zero-rows check stays FIRST and unchanged, so a pack that fails today
    # keeps failing with the same `:gate_failed` shape rather than acquiring a
    # new error type as a side effect of gaining a contract.
    case rows do
      [] -> :fail
      [_ | _] -> cardinality_status(graph, rows, contract)
    end
  end

  defp cardinality_status(_graph, _rows, nil), do: :pass

  defp cardinality_status(graph, rows, contract) do
    expected = length(GgenIgniter.Query.run(graph, contract_query(contract)))
    actual = length(rows)

    if expected == actual, do: :pass, else: {:cardinality, expected, actual}
  end

  # ROWS: one row per subject. Anchored on a class, or -- preferred, see the
  # blind-spot section of this module's docs -- on a required predicate.
  defp contract_query(%{mode: :rows, anchor: {:class, class}}) do
    "SELECT DISTINCT ?s WHERE { ?s a <#{class}> }"
  end

  defp contract_query(%{mode: :rows, anchor: {:predicate, predicate}}) do
    "SELECT DISTINCT ?s WHERE { ?s <#{predicate}> ?v }"
  end

  # VALUES: one row per (subject, value) pair, for a repeatable property such
  # as amp:defaultAction. Not DISTINCT and deliberately so -- an RDF graph is a
  # set of triples, so a (?s, ?v) pair cannot repeat, and the gates this mirrors
  # are themselves plain SELECTs.
  defp contract_query(%{mode: :values, anchor: {:predicate, predicate}}) do
    "SELECT ?s ?v WHERE { ?s <#{predicate}> ?v }"
  end

  defp contract_query(%{mode: :values, anchor: {:class_predicate, class, predicate}}) do
    "SELECT ?s ?v WHERE { ?s a <#{class}> ; <#{predicate}> ?v }"
  end

  @doc """
  Default cardinality-contract path for `pack_dir`:
  `<pack_dir>/verify/cardinality.json`.

  `verify/` rather than `gates/` is a hard wiring constraint, not a naming
  preference: `GgenIgniter.Pack.discover_queries/1` globs `gates/*.rq` only
  (`lib/ggen_igniter/pack.ex:87`), and five call sites consume that namespace.
  Anything placed under `gates/` would be executed as a gate.
  """
  @spec default_cardinality_path(String.t()) :: String.t()
  def default_cardinality_path(pack_dir), do: Path.join(pack_dir, "verify/cardinality.json")

  @doc """
  Loads and validates a `verify/cardinality.json` contract file into the
  `%{gate_stem => contract}` map `run/3` accepts.

  Each entry is `{"mode": "ROWS" | "VALUES", ...}` plus exactly one anchor:

      {"mode": "ROWS",   "predicate": "<IRI>"}            # preferred
      {"mode": "ROWS",   "class": "<IRI>"}
      {"mode": "VALUES", "predicate": "<IRI>"}            # preferred
      {"mode": "VALUES", "class": "<IRI>", "predicate": "<IRI>"}

  Returns `{:ok, map}`, `{:error, {:enoent, path}}` when the file is absent
  (a pack without contracts is legal -- see the ADDITIVE section of this
  module's docs), or `{:error, {:invalid_contract, gate_stem, reason}}` when an
  entry is malformed. Validation happens HERE, at the boundary, so `run/3`
  never has to branch on a bad contract mid-verification.
  """
  @spec load_cardinality(String.t()) ::
          {:ok, %{optional(String.t()) => map()}}
          | {:error, {:enoent, String.t()}}
          | {:error, {:invalid_contract, String.t(), atom()}}
  def load_cardinality(path) when is_binary(path) do
    with {:ok, body} <- read_contract_file(path),
         {:ok, json} <- decode_contract(body, path) do
      json
      |> Map.get("gates", %{})
      |> Enum.reduce_while({:ok, %{}}, fn {stem, entry}, {:ok, acc} ->
        case parse_contract(entry) do
          {:ok, contract} -> {:cont, {:ok, Map.put(acc, stem, contract)}}
          {:error, reason} -> {:halt, {:error, {:invalid_contract, stem, reason}}}
        end
      end)
    end
  end

  defp read_contract_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, :enoent} -> {:error, {:enoent, path}}
      {:error, reason} -> {:error, {:invalid_contract, path, reason}}
    end
  end

  defp decode_contract(body, path) do
    case Jason.decode(body) do
      {:ok, %{} = json} -> {:ok, json}
      {:ok, _other} -> {:error, {:invalid_contract, path, :not_an_object}}
      {:error, _} -> {:error, {:invalid_contract, path, :malformed_json}}
    end
  end

  # "ROWS"/"VALUES" are the CONTRACT with verify/cardinality.json's own "mode"
  # field, not chosen constants. The set is closed on purpose: an unrecognised
  # mode is a typed refusal, never a silently skipped contract -- a contract
  # that quietly does nothing would reintroduce the exact fail-open this module
  # exists to close.
  #
  # A ROWS contract takes exactly ONE anchor. Accepting both would leave the
  # reader unable to tell which count a mismatch came from, and the two anchors
  # have different blind spots (see this module's docs), so the choice is
  # load-bearing and has to be explicit.
  defp parse_contract(%{"mode" => "ROWS", "class" => _, "predicate" => _}) do
    {:error, :ambiguous_anchor}
  end

  defp parse_contract(%{"mode" => "ROWS", "class" => class}) when is_binary(class) do
    {:ok, %{mode: :rows, anchor: {:class, class}}}
  end

  defp parse_contract(%{"mode" => "ROWS", "predicate" => predicate}) when is_binary(predicate) do
    {:ok, %{mode: :rows, anchor: {:predicate, predicate}}}
  end

  defp parse_contract(%{"mode" => "VALUES", "class" => class, "predicate" => predicate})
       when is_binary(class) and is_binary(predicate) do
    {:ok, %{mode: :values, anchor: {:class_predicate, class, predicate}}}
  end

  defp parse_contract(%{"mode" => "VALUES", "predicate" => predicate})
       when is_binary(predicate) do
    {:ok, %{mode: :values, anchor: {:predicate, predicate}}}
  end

  defp parse_contract(%{"mode" => "ROWS"}), do: {:error, :missing_anchor}
  defp parse_contract(%{"mode" => "VALUES"}), do: {:error, :missing_predicate}
  defp parse_contract(%{"mode" => _}), do: {:error, :unknown_mode}
  defp parse_contract(_), do: {:error, :missing_mode}

  @doc """
  Discovers every `<pack_dir>/verify/*.unbound.rq` inverted companion query,
  sorted lexically, mapped to `{gate_stem, path}` -- where `gate_stem` is the
  stem of the GATE the query refutes, so `030_resources.unbound.rq` maps to
  `"resources"`, the same name `GgenIgniter.Pack.discover_queries/1` derives
  from `gates/030_resources.rq`.
  """
  @spec discover_unbound(String.t()) :: [{String.t(), String.t()}]
  def discover_unbound(pack_dir) when is_binary(pack_dir) do
    pack_dir
    |> Path.join("verify/*.unbound.rq")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path -> {unbound_gate_stem(path), path} end)
  end

  defp unbound_gate_stem(path) do
    path
    |> Path.basename(".unbound.rq")
    |> String.replace(~r/^\d+_/, "")
  end

  @doc """
  Runs every inverted companion query in `<pack_dir>/verify/` against the graph
  at `ontology_path`.

  These queries invert the pass condition: a row means a fact the corresponding
  gate requires is ABSENT, so ZERO ROWS across every query is the pass
  condition.

  Returns `{:ok, []}` when no query produced a row, or
  `{:error, {:unbound_facts, findings}}` where each finding is
  `%{gate: stem, subject: iri, missing_property: name}`. EVERY finding is
  returned, not just the first: unlike a gate failure (where the first failure
  aborts the run), a missing-fact census is more useful whole -- one dropped
  domain can orphan several resources at once.
  """
  @spec verify_unbound(String.t(), String.t()) ::
          {:ok, []} | {:error, {:unbound_facts, [map()]}}
  def verify_unbound(pack_dir, ontology_path)
      when is_binary(pack_dir) and is_binary(ontology_path) do
    graph = GgenIgniter.Ontology.load!(ontology_path)

    findings =
      pack_dir
      |> discover_unbound()
      |> Enum.flat_map(fn {stem, path} ->
        graph
        |> GgenIgniter.Query.run(File.read!(path))
        |> Enum.map(fn row ->
          # "subject"/"missing_property" are the CONTRACT every verify/*.unbound.rq
          # projects (see the SELECT line of each). A query that projects other
          # column names yields nils here rather than crashing, which is the right
          # failure mode for a census: the row still surfaces as a finding.
          %{
            gate: stem,
            subject: Map.get(row, "subject"),
            missing_property: Map.get(row, "missing_property")
          }
        end)
      end)

    case findings do
      [] -> {:ok, []}
      [_ | _] -> {:error, {:unbound_facts, findings}}
    end
  end
end
