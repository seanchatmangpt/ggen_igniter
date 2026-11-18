defmodule GgenIgniter.OntologyAggregate do
  @moduledoc """
  Enforces `[ontology.aggregate]` freshness -- port of
  `enforce_ontology_aggregate` (`~/ggen/crates/ggen-engine/src/sync.rs:2985-3110`).

  `enforce/3` paths:

  - `nil` aggregate -> `{:ok, nil}`, no IO.
  - empty `constituents` -> `{:error, "[FM-ONTOLOGY-AGG-002] ..."}`.
  - unreadable constituent -> `{:error, "[FM-ONTOLOGY-AGG-003] ..."}`.
  - fresh (output bytes == sorted concat AND `.ggen-v2/aggregate-freshness`
    == freshness hash) -> `{:ok, %{regenerated: false}}`.
  - stale, `auto_regen: false` -> `{:error, "REFUSED:ONTOLOGY_AGGREGATE_STALE
    [FM-ONTOLOGY-AGG-001] ..."}` (via `GgenIgniter.Refusals.format/2`), no writes.
  - stale, `auto_regen: true`, `dry_run: true` -> `{:ok, %{regenerated: false}}`, no writes.
  - stale, `auto_regen: true` -> writes output + marker, `{:ok, %{regenerated: true}}`;
    a write failure -> `{:error, "[FM-ONTOLOGY-AGG-004] ..."}`.

  Constituents are ordered by relative path; the concat is the contents joined
  with `"\\n"` plus a trailing `"\\n"` if missing.

  **Disclosed deviation**: the freshness hash is SHA-256
  (`GgenIgniter.Digest.hex/1`) over `rel <> <<0>> <> content <> <<0>>` per
  constituent; ggen uses BLAKE3 over the same byte stream. Markers are NOT
  cross-compatible between the two tools: a marker written by one reads as
  stale to the other.

  Not yet wired into a sync path: `GgenIgniter.SchemaDispatch` configs are
  consumed by `GgenToml.IO` and `Mix.Tasks.GgenIgniter.Fortune5Ready`, neither of
  which reads the ontology for sync.
  """

  alias GgenIgniter.{Digest, Refusals}
  alias GgenIgniter.ProjectConfig.OntologyAggregate

  @marker_rel Path.join(".ggen-v2", "aggregate-freshness")

  @type outcome :: %{regenerated: boolean()}

  @doc "Enforce the aggregate's freshness law under `root`; see the moduledoc for outcomes."
  @spec enforce(String.t(), OntologyAggregate.t() | nil, keyword()) ::
          {:ok, outcome() | nil} | {:error, String.t()}
  def enforce(root, aggregate, opts \\ [])

  def enforce(_root, nil, _opts), do: {:ok, nil}

  def enforce(_root, %OntologyAggregate{constituents: []}, _opts) do
    {:error,
     "[FM-ONTOLOGY-AGG-002] `[ontology.aggregate]` declares no constituents. " <>
       "Remediation: list at least one constituent file or drop the section."}
  end

  def enforce(root, %OntologyAggregate{} = agg, opts) do
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, parts} <- read_parts(root, agg.constituents) do
      freshness = freshness(parts)
      concat = concat(parts)
      output_path = Path.join(root, agg.output)
      marker_path = Path.join(root, @marker_rel)

      cond do
        fresh?(output_path, marker_path, concat, freshness) ->
          {:ok, %{regenerated: false}}

        not agg.auto_regen ->
          {:error, stale_refusal(agg, freshness)}

        dry_run ->
          {:ok, %{regenerated: false}}

        true ->
          regenerate(output_path, marker_path, concat, freshness)
      end
    end
  end

  defp read_parts(root, constituents) do
    constituents
    |> Enum.reduce_while({:ok, []}, fn rel, {:ok, acc} ->
      path = Path.join(root, rel)

      case File.read(path) do
        {:ok, content} ->
          {:cont, {:ok, [{rel, content} | acc]}}

        {:error, reason} ->
          {:halt,
           {:error,
            "[FM-ONTOLOGY-AGG-003] constituent `#{rel}` unreadable at `#{path}`: " <>
              "#{:file.format_error(reason)}. Remediation: fix or remove the constituent."}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.sort_by(parts, &elem(&1, 0))}
      error -> error
    end
  end

  defp freshness(parts) do
    parts
    |> Enum.map(fn {rel, content} -> [rel, <<0>>, content, <<0>>] end)
    |> IO.iodata_to_binary()
    |> Digest.hex()
  end

  defp concat(parts) do
    joined = parts |> Enum.map(&elem(&1, 1)) |> Enum.join("\n")
    if String.ends_with?(joined, "\n"), do: joined, else: joined <> "\n"
  end

  defp fresh?(output_path, marker_path, concat, freshness) do
    File.read(output_path) == {:ok, concat} and File.read(marker_path) == {:ok, freshness}
  end

  defp stale_refusal(agg, freshness) do
    Refusals.format(
      :ONTOLOGY_AGGREGATE_STALE,
      "[FM-ONTOLOGY-AGG-001] aggregate corpus `#{agg.output}` is stale: constituents " <>
        "hash #{freshness} but the marker (#{@marker_rel}) does not match " <>
        "(or the output bytes diverge from the constituent concat). " <>
        "Remediation: set `[ontology.aggregate] auto_regen = true` once to regenerate, " <>
        "or regenerate the corpus manually and re-sync."
    )
  end

  defp regenerate(output_path, marker_path, concat, freshness) do
    with :ok <- write(output_path, concat, "aggregate output"),
         :ok <- write(marker_path, freshness, "freshness marker") do
      {:ok, %{regenerated: true}}
    end
  end

  defp write(path, data, what) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} ->
        {:error,
         "[FM-ONTOLOGY-AGG-004] failed to write #{what} `#{path}`: #{:file.format_error(reason)}"}
    end
  end
end
