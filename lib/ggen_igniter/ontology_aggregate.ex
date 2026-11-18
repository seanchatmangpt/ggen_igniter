defmodule GgenIgniter.OntologyAggregate do
  @moduledoc """
  Enforces `[ontology.aggregate]` freshness -- Elixir port of
  `enforce_ontology_aggregate` (`~/ggen/crates/ggen-engine/src/sync.rs:2985-3110`).

  `enforce/3` paths:

  - `nil` aggregate -> `{:ok, nil}`, no IO.
  - empty `constituents` -> `{:error, "[FM-ONTOLOGY-AGG-002] ..."}`.
  - unreadable constituent -> `{:error, "[FM-ONTOLOGY-AGG-003] ..."}`.
  - fresh (output bytes == sorted concat AND
    `.ggen_igniter/aggregate-freshness` == freshness hash) ->
    `{:ok, %{regenerated: false}}`.
  - stale, `auto_regen: false` -> `{:error, "REFUSED:ONTOLOGY_AGGREGATE_STALE
    [FM-ONTOLOGY-AGG-001] ..."}` (via `GgenIgniter.Refusals.format/2`), no writes.
  - stale, `auto_regen: true`, `dry_run: true` -> `{:ok, %{regenerated: false}}`, no writes.
  - stale, `auto_regen: true` -> writes output + marker, `{:ok, %{regenerated: true}}`;
    a write failure -> `{:error, "[FM-ONTOLOGY-AGG-004] ..."}`.

  Constituents are ordered by relative path; the concat is the contents joined
  with `"\\n"` plus a trailing `"\\n"` if missing.

  **SHA-256 evidence-store law (intentional, non-interop with Rust ggen):**
  the freshness hash is bare lowercase SHA-256 hex (`GgenIgniter.Digest.hex/1`)
  over `rel <> <<0>> <> content <> <<0>>` per constituent. Rust ggen uses
  BLAKE3 over the same byte stream and stores its marker under
  `.ggen-v2/aggregate-freshness`. Igniter owns `.ggen_igniter/aggregate-freshness`
  so the two tools never collide on a shared marker path and never pretend
  digests are interchangeable.

  **Sync wiring:** `enforce_project/2` loads optional `<root>/ggen.toml` via
  `SchemaDispatch` and runs before ontology load on both
  `GgenIgniter.Reconcile.run/1` and `GgenIgniter.Reactors.ReconcileReactor`
  (`:enforce_ontology_aggregate` step). Absent `ggen.toml` or a
  DeclarativeRules schema (no aggregate section) is a no-op.
  """

  alias GgenIgniter.{Digest, FrontmatterConfig, Refusals, SchemaDispatch}
  alias GgenIgniter.ProjectConfig.OntologyAggregate

  @marker_rel Path.join(".ggen_igniter", "aggregate-freshness")

  @type outcome :: %{regenerated: boolean()}

  @doc "Root-relative path of igniter's aggregate freshness marker (SHA-256 hex)."
  @spec marker_rel() :: String.t()
  def marker_rel, do: @marker_rel

  @doc """
  Load `<root>/ggen.toml` (if present) and enforce its `[ontology.aggregate]`.

  Missing `ggen.toml` -> `{:ok, nil}` (CLI-flag syncs without a toml stay
  byte-compatible). Frontmatter configs carry the aggregate; DeclarativeRules
  configs have no aggregate field today -> `{:ok, nil}`. A refused/malformed
  toml that *exists* fails closed.
  """
  @spec enforce_project(String.t(), keyword()) :: {:ok, outcome() | nil} | {:error, String.t()}
  def enforce_project(root, opts \\ []) when is_binary(root) do
    toml_path = Path.join(root, "ggen.toml")

    case File.read(toml_path) do
      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error,
         "[FM-ONTOLOGY-AGG-003] could not read `#{toml_path}`: #{:file.format_error(reason)}"}

      {:ok, raw} ->
        case SchemaDispatch.load_raw(raw) do
          {:frontmatter, %FrontmatterConfig{ontology: %{aggregate: aggregate}}} ->
            enforce(root, aggregate, opts)

          {:declarative_rules, _config} ->
            {:ok, nil}

          {:refused, reason} ->
            {:error, format_toml_refusal(toml_path, reason)}
        end
    end
  end

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

  defp format_toml_refusal(path, {:malformed, diagnostic: diagnostic}) do
    "[FM-ONTOLOGY-AGG-003] ggen.toml at `#{path}` refused as malformed: #{diagnostic}"
  end

  defp format_toml_refusal(path, {:ambiguous, matched: matched}) do
    "[FM-ONTOLOGY-AGG-003] ggen.toml at `#{path}` is schema-ambiguous (matched: #{inspect(matched)})"
  end

  defp format_toml_refusal(path, {:unsupported, observed_markers: markers}) do
    "[FM-ONTOLOGY-AGG-003] ggen.toml at `#{path}` uses unsupported markers: #{inspect(markers)}"
  end

  defp format_toml_refusal(path, other) do
    "[FM-ONTOLOGY-AGG-003] ggen.toml at `#{path}` refused: #{inspect(other)}"
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
