defmodule GgenIgniter.Review.Store do
  @moduledoc """
  Round persistence under `.ggen_igniter/reviews/<review_id>/`:

  - `findings.json` — one JSON document, OVERWRITTEN per round (the latest
    round's full doc: posted + suppressed).
  - `rounds.jsonl` — append-only per-round history; one JSON object per line,
    the source `GgenIgniter.Review.Filter` reads prior rounds from.

  All JSON is string-keyed via `Jason`; `GgenIgniter.Review.Finding.to_map/
  from_map` is the ONLY Finding <-> map boundary — this module never encodes
  or decodes finding fields itself.

  `load/2` distinguishes `{:error, :not_found}` (no such round: file or line
  absent) from `{:error, :corrupt}` (present but unparseable or not a map) —
  a missing round is a normal condition of round 1, a corrupt one is a real
  defect, and the two must never read the same.
  """

  alias GgenIgniter.Review.Finding

  @doc "The review directory for a review_id under `base` (default: cwd/.ggen_igniter/reviews)."
  @spec review_dir(String.t(), String.t() | nil) :: String.t()
  def review_dir(review_id, base \\ nil) do
    Path.join([base || default_base(), review_id])
  end

  defp default_base, do: Path.join(File.cwd!(), ".ggen_igniter/reviews")

  @doc """
  Persists one round: overwrites `findings.json` with `doc` and appends it as
  one JSON line to `rounds.jsonl`. `doc` must contain `:round` and findings
  under `:posted` / `:suppressed` (Finding structs). Returns the directory.
  """
  @spec save(round_doc, String.t(), String.t() | nil) :: String.t()
        when round_doc: %{
               required(:round) => pos_integer(),
               required(:posted) => [Finding.t()],
               required(:suppressed) => [Finding.t()]
             }
  def save(%{round: round, posted: posted, suppressed: suppressed} = doc, review_id, base \\ nil)
      when is_integer(round) and round >= 1 and is_list(posted) and is_list(suppressed) do
    dir = review_dir(review_id, base)
    File.mkdir_p!(dir)

    serializable = %{
      "review_id" => review_id,
      "round" => round,
      "posted" => Enum.map(posted, &Finding.to_map/1),
      "suppressed" => Enum.map(suppressed, &Finding.to_map/1),
      "extra" => Map.get(doc, :extra, %{})
    }

    json = Jason.encode!(serializable)

    File.write!(Path.join(dir, "findings.json"), json <> "\n")
    :ok = File.write(Path.join(dir, "rounds.jsonl"), json <> "\n", [:append])

    dir
  end

  @doc """
  Loads round `round` for `review_id`. Reads `findings.json` (the current
  doc) and checks `rounds.jsonl` history.

  Returns:
  - `{:ok, doc}` — `%{round:, posted: [Finding.t()], suppressed: [Finding.t()]}`
  - `{:error, :not_found}` — no findings.json, or no line for this round
  - `{:error, :corrupt}` — file present but unparseable JSON or not an object
  """
  @spec load(String.t(), pos_integer(), String.t() | nil) ::
          {:ok, %{round: pos_integer(), posted: [Finding.t()], suppressed: [Finding.t()]}}
          | {:error, :not_found | :corrupt}
  def load(review_id, round, base \\ nil) when is_integer(round) and round >= 1 do
    path = Path.join(review_dir(review_id, base), "findings.json")

    with {:file, {:ok, body}} <- {:file, File.read(path)},
         {:parse, {:ok, map}} <- {:parse, parse_object(body)},
         {:round, true} <- {:round, Map.get(map, "round") == round} do
      {:ok, decode_doc(map)}
    else
      {:file, {:error, _}} -> {:error, :not_found}
      {:parse, :corrupt} -> {:error, :corrupt}
      {:round, false} -> {:error, :not_found}
    end
  end

  @doc """
  Loads the full append-only history for `review_id` as a list of decoded
  round docs (oldest first). `{:error, :not_found}` when no history exists;
  `{:error, :corrupt}` when any line is unparseable.
  """
  @spec load_history(String.t(), String.t() | nil) ::
          {:ok, [map()]} | {:error, :not_found | :corrupt}
  def load_history(review_id, base \\ nil) do
    path = Path.join(review_dir(review_id, base), "rounds.jsonl")

    case File.read(path) do
      {:error, _} ->
        {:error, :not_found}

      {:ok, body} ->
        lines = body |> String.split("\n", trim: true)

        docs =
          Enum.map(lines, &decode_line/1)

        if :corrupt in docs, do: {:error, :corrupt}, else: {:ok, docs}
    end
  end

  defp decode_line(line) do
    case parse_object(line) do
      {:ok, m} -> decode_doc(m)
      :corrupt -> :corrupt
    end
  end

  defp parse_object(body) do
    case Jason.decode(body) do
      {:ok, %{} = m} -> {:ok, m}
      _ -> :corrupt
    end
  rescue
    _ -> :corrupt
  end

  defp decode_doc(map) do
    %{
      round: Map.fetch!(map, "round"),
      review_id: Map.get(map, "review_id"),
      posted: decode_findings(Map.get(map, "posted", [])),
      suppressed: decode_findings(Map.get(map, "suppressed", []))
    }
  end

  defp decode_findings(maps) when is_list(maps) do
    Enum.map(maps, fn m ->
      {status, m} = Map.pop(m, "status", "posted")
      status_atom = if status == "posted", do: :posted, else: :suppressed
      f = Finding.from_map(Map.put(m, "status", status))
      %{f | status: status_atom}
    end)
  end
end
