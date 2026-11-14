defmodule GgenIgniter.PackFrontmatter.EaAdmission do
  @moduledoc """
  EA-graph admission for generated-only projects: `ggen sync run` demands an
  `ea.graph.json`; a project with none may pass `--skip-ea-admission` only with a
  skip receipt on disk.

  * `skip_receipt/2` -- writes `<project_dir>/.ggen_igniter/receipts/ea-skip-<ts>.json`
    (dir from `GgenIgniter.Receipt.dir/1`) holding `skipped`, `reason`,
    `ggen_toml_sha256` (sha256 of `<project_dir>/ggen.toml`, `nil` when absent) and `ts`.
    Empty reason refuses; the file is created exclusively, never overwritten.
  * `admit/1` -- `{:ok, :ea_graph_present}` when `<project_dir>/ea.graph.json` exists;
    else `{:ok, {:skipped, receipt_path}}` when a skip receipt whose `ggen_toml_sha256`
    equals the current `ggen.toml` digest exists (newest wins); else the typed refusal
    `{:error, {:ea_admission_refused, :no_ea_graph_and_no_skip_receipt}}`, or
    `{:error, {:ea_admission_refused, :stale_skip_receipt}}` when only mismatching
    receipts exist.

  Standing: UNVERIFIED until the test file is run.
  """

  alias GgenIgniter.Receipt

  @graph "ea.graph.json"

  @doc "Writes an EA-skip receipt; returns `{:ok, path}` or `{:error, :empty_reason}`."
  @spec skip_receipt(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def skip_receipt(project_dir, reason) when is_binary(project_dir) and is_binary(reason) do
    if String.trim(reason) == "" do
      {:error, :empty_reason}
    else
      now = DateTime.utc_now()
      ts = DateTime.to_iso8601(now)
      stamp = Calendar.strftime(now, "%Y%m%dT%H%M%S") <> "-#{System.unique_integer([:positive])}"
      dir = Receipt.dir(project_dir)
      path = Path.join(dir, "ea-skip-#{stamp}.json")

      body =
        Jason.encode!(%{
          "skipped" => true,
          "reason" => reason,
          "ggen_toml_sha256" => toml_sha(project_dir),
          "ts" => ts
        })

      with :ok <- File.mkdir_p(dir),
           :ok <- File.write(path, body, [:exclusive]) do
        {:ok, path}
      end
    end
  end

  @doc "Lawful EA admission: graph present, or skipped with a matching receipt on disk."
  @spec admit(String.t()) ::
          {:ok, :ea_graph_present}
          | {:ok, {:skipped, String.t()}}
          | {:error, {:ea_admission_refused, atom()}}
  def admit(project_dir) when is_binary(project_dir) do
    if File.regular?(Path.join(project_dir, @graph)) do
      {:ok, :ea_graph_present}
    else
      current = toml_sha(project_dir)

      receipts =
        project_dir
        |> Receipt.dir()
        |> Path.join("ea-skip-*.json")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.flat_map(&load/1)

      receipts
      |> Enum.filter(fn {_p, m} -> m["ggen_toml_sha256"] == current end)
      |> classify(receipts)
    end
  end

  defp classify([], []), do: {:error, {:ea_admission_refused, :no_ea_graph_and_no_skip_receipt}}
  defp classify([], _receipts), do: {:error, {:ea_admission_refused, :stale_skip_receipt}}

  defp classify(matching, _receipts) do
    {path, _} = List.last(matching)
    {:ok, {:skipped, path}}
  end

  defp load(path) do
    with {:ok, bin} <- File.read(path),
         {:ok, %{"skipped" => true, "reason" => r} = m} when is_binary(r) <- Jason.decode(bin) do
      [{path, m}]
    else
      _ -> []
    end
  end

  defp toml_sha(project_dir) do
    case File.read(Path.join(project_dir, "ggen.toml")) do
      {:ok, bin} -> :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end
end
