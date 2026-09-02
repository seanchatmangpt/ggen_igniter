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

  Never a single aggregate boolean: `run/2` returns a typed, per-gate
  `[{gate_name, :pass | :fail}]` list on full success, or a typed refusal
  naming the specific first failed gate on any failure.
  """

  @doc """
  Runs every `<pack_dir>/gates/*.rq` query against the ontology graph loaded
  from `ontology_path`, in the pack's own lexical (`NNN_name.rq`) order.

  Returns:

    * `{:ok, [{gate_name, :pass}, ...]}` when every gate passes -- a real,
      individually-inspectable list, never a bare `true`.
    * `{:error, {:gate_failed, gate_name}}` naming the first gate (in pack
      order) whose query returned zero rows.
  """
  @spec run(String.t(), String.t()) ::
          {:ok, [{String.t(), :pass}]} | {:error, {:gate_failed, String.t()}}
  def run(pack_dir, ontology_path) when is_binary(pack_dir) and is_binary(ontology_path) do
    graph = GgenIgniter.Ontology.load!(ontology_path)

    pack_dir
    |> GgenIgniter.Pack.discover_queries()
    |> Enum.reduce_while([], fn {name, path}, acc ->
      case gate_status(graph, path) do
        :pass -> {:cont, [{name, :pass} | acc]}
        :fail -> {:halt, {:error, {:gate_failed, name}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      results -> {:ok, Enum.reverse(results)}
    end
  end

  defp gate_status(graph, query_path) do
    query = File.read!(query_path)

    case GgenIgniter.Query.run(graph, query) do
      [] -> :fail
      [_ | _] -> :pass
    end
  end
end
