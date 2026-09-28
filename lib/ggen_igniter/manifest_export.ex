defmodule GgenIgniter.ManifestExport do
  @moduledoc """
  Stable, deterministic JSON export of a project's reconciliation state for
  third-party replay (modeled on `mix ash.manifest.dump`).

  Reads, from `<dir>/.ggen_igniter/`:

    * `manifest.json` -- the `GgenIgniter.Manifest` current-state document
      (must exist and load via `GgenIgniter.Manifest.load_safe/1`);
    * `receipts/*.jsonl` -- every `GgenIgniter.Receipt` partition, one JSON
      object per non-blank line.

  and returns ONE JSON document:

      {"format": "ggen_igniter.manifest_export/1",
       "manifest": {...},
       "manifest_sha256": "sha256:<hex of the raw manifest.json bytes>",
       "receipts": [{...}, ...]}

  Determinism: every object's keys are sorted (recursively, via
  `Jason.OrderedObject`), receipts are ordered by `{started_at, id, file, line}`,
  and no absolute path or wall-clock value is added -- identical on-disk input
  yields byte-identical output regardless of the directory it lives in.

  Typed errors (never a guess): `{:error, {:missing_manifest, path}}`,
  `{:error, {:corrupt_manifest, detail}}`, `{:error, {:corrupt_receipt, detail}}`.
  """

  alias GgenIgniter.{Digest, Manifest}

  @format "ggen_igniter.manifest_export/1"

  @type error ::
          {:missing_manifest, String.t()}
          | {:corrupt_manifest, String.t()}
          | {:corrupt_receipt, String.t()}

  @doc "The export format tag."
  @spec format() :: String.t()
  def format, do: @format

  @doc "Builds the export document (a string-keyed map) for `dir`."
  @spec build(String.t()) :: {:ok, map()} | {:error, error()}
  def build(dir) when is_binary(dir) do
    manifest_path = Manifest.path(dir)

    with {:ok, raw} <- read_manifest(manifest_path),
         {:ok, manifest} <- load_manifest(dir),
         {:ok, receipts} <- load_receipts(dir) do
      {:ok,
       %{
         "format" => @format,
         "manifest" => manifest,
         "manifest_sha256" => Digest.sha256(raw),
         "receipts" => receipts
       }}
    end
  end

  @doc "Builds the export and encodes it as sorted, pretty JSON (trailing newline)."
  @spec dump(String.t()) :: {:ok, String.t()} | {:error, error()}
  def dump(dir) do
    with {:ok, doc} <- build(dir), do: {:ok, encode(doc)}
  end

  @doc "Encodes any JSON-able term with recursively sorted object keys."
  @spec encode(term()) :: String.t()
  def encode(term), do: Jason.encode!(sort(term), pretty: true) <> "\n"

  defp sort(map) when is_map(map) and not is_struct(map) do
    pairs =
      map |> Enum.map(fn {k, v} -> {to_string(k), sort(v)} end) |> Enum.sort_by(&elem(&1, 0))

    Jason.OrderedObject.new(pairs)
  end

  defp sort(list) when is_list(list), do: Enum.map(list, &sort/1)
  defp sort(other), do: other

  defp read_manifest(path) do
    case File.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, :enoent} -> {:error, {:missing_manifest, path}}
      {:error, reason} -> {:error, {:corrupt_manifest, "cannot read #{path}: #{inspect(reason)}"}}
    end
  end

  defp load_manifest(dir) do
    case Manifest.load_safe(dir) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :corrupt_manifest, detail} -> {:error, {:corrupt_manifest, detail}}
    end
  end

  defp load_receipts(dir) do
    files = dir |> Path.join(".ggen_igniter/receipts/*.jsonl") |> Path.wildcard() |> Enum.sort()

    files
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, acc} ->
      case parse_file(file) do
        {:ok, rows} -> {:cont, {:ok, acc ++ rows}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, rows} ->
        {:ok,
         rows
         |> Enum.sort_by(fn {r, file, line} ->
           {to_string(r["started_at"]), to_string(r["id"]), file, line}
         end)
         |> Enum.map(&elem(&1, 0))}

      err ->
        err
    end
  end

  defp parse_file(file) do
    base = Path.basename(file)

    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {l, _} -> String.trim(l) == "" end)
    |> Enum.reduce_while({:ok, []}, fn {line, n}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, %{} = r} ->
          {:cont, {:ok, [{r, base, n} | acc]}}

        _ ->
          {:halt,
           {:error, {:corrupt_receipt, "#{base}:#{n} is not a JSON object -- refusing to export"}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      err -> err
    end
  end
end
