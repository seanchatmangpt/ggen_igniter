defmodule GgenIgniter.Gall.ProjectManufacturer do
  @moduledoc """
  GALL-002 identity seal for one admitted project manufacture.

  This module does not generate Ash code and does not actuate. It binds the
  semantic subject, strict bootstrap manifest, generator/toolchain identity,
  selected profile, and the already-durable reconciliation receipt into one
  deterministic manufacturer subject. Framework-owned mutations remain owned
  by the real Ash/Igniter generators invoked by the reconciliation pipeline.
  """

  alias GgenIgniter.{Digest, Pack, Receipt}

  @enforce_keys [
    :graph_digest,
    :manifest_identity,
    :profile,
    :generator_tasks,
    :mix_lock_digest,
    :toolchain,
    :projection_digest,
    :manufacturer_digest
  ]
  defstruct [
    :repo_sha,
    :graph_digest,
    :manifest_identity,
    :profile,
    :generator_tasks,
    :mix_lock_digest,
    :toolchain,
    :projection_digest,
    :manufacturer_digest
  ]

  @type t :: %__MODULE__{}

  @spec build(String.t(), Pack.Manifest.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def build(graph_digest, %Pack.Manifest{} = manifest, opts)
      when is_binary(graph_digest) and is_list(opts) do
    with "sha256:" <> _ <- graph_digest,
         {:ok, projection_digest} <- projection_digest(opts),
         {:ok, mix_lock_digest} <- required_digest(opts, :mix_lock_digest),
         {:ok, repo_sha} <- required_binary(opts, :repo_sha),
         {:ok, profile} <- required_binary(opts, :profile),
         {:ok, generator_tasks} <- generator_tasks(opts),
         {:ok, toolchain} <- toolchain(opts) do
      manifest_identity = %{
        name: manifest.name,
        version: manifest.version,
        description: manifest.description
      }

      payload = %{
        repo_sha: repo_sha,
        graph_digest: graph_digest,
        manifest_identity: manifest_identity,
        profile: profile,
        generator_tasks: generator_tasks,
        mix_lock_digest: mix_lock_digest,
        toolchain: toolchain,
        projection_digest: projection_digest
      }

      {:ok,
       struct!(
         __MODULE__,
         Map.put(payload, :manufacturer_digest, digest(payload))
       )}
    else
      other -> {:error, {:refused_project_manufacturer, other}}
    end
  end

  @spec from_receipt(String.t(), Pack.Manifest.t(), Receipt.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def from_receipt(graph_digest, %Pack.Manifest{} = manifest, %Receipt{} = receipt, opts) do
    cond do
      receipt.standing != :alive ->
        {:error, {:refused_project_manufacturer, {:standing, receipt.standing}}}

      is_nil(receipt.post_run_hash) ->
        {:error, {:refused_project_manufacturer, :post_run_hash_missing}}

      Receipt.hash_files(receipt.files) != receipt.post_run_hash ->
        {:error,
         {:refused_project_manufacturer,
          {:projection_drift,
           %{expected: receipt.post_run_hash, observed: Receipt.hash_files(receipt.files)}}}}

      true ->
        build(
          graph_digest,
          manifest,
          Keyword.put(opts, :projection_digest, receipt.post_run_hash)
        )
    end
  end

  @spec digest(map()) :: String.t()
  def digest(payload) when is_map(payload) do
    payload
    |> canonical()
    |> Jason.encode!()
    |> Digest.sha256()
  end

  defp canonical(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical(item)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, item} -> [key, item] end)
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value) when is_tuple(value), do: value |> Tuple.to_list() |> canonical()
  defp canonical(value), do: value

  defp projection_digest(opts), do: required_digest(opts, :projection_digest)

  defp required_digest(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, "sha256:" <> _ = digest} -> {:ok, digest}
      {:ok, other} -> {:error, {key, other}}
      :error -> {:error, {key, :missing}}
    end
  end

  defp required_binary(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      {:ok, other} -> {:error, {key, other}}
      :error -> {:error, {key, :missing}}
    end
  end

  defp generator_tasks(opts) do
    case Keyword.fetch(opts, :generator_tasks) do
      {:ok, tasks} when is_list(tasks) and tasks != [] ->
        {:ok, tasks |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.uniq()}

      {:ok, other} ->
        {:error, {:generator_tasks, other}}

      :error ->
        {:error, {:generator_tasks, :missing}}
    end
  end

  defp toolchain(opts) do
    case Keyword.fetch(opts, :toolchain) do
      {:ok, toolchain} when is_map(toolchain) and map_size(toolchain) > 0 -> {:ok, toolchain}
      {:ok, other} -> {:error, {:toolchain, other}}
      :error -> {:error, {:toolchain, :missing}}
    end
  end
end
