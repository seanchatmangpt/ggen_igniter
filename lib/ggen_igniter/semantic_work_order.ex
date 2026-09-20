defmodule GgenIgniter.SemanticWorkOrder do
  @moduledoc """
  Deterministic identity and execution-package projection for an admitted
  semantic work order.

  The work order is Turtle. It is parsed with the repository's real RDF loader
  before it can acquire an identity, so malformed RDF is refused rather than
  hashed as opaque text. The current portable identity is the exact source-byte
  SHA-256; source identity is kept distinct from semantic graph equivalence.

  Markdown/WBPR/Vision documents are projections and are not inputs to this identity.
  """

  alias GgenIgniter.{Digest, Ontology}

  @default_path "work-order.ttl"
  @schema "https://ggen.dev/work-order/execution-package/v1"

  @type identity :: %{path: String.t(), source_digest: String.t()}

  @doc "Returns the default root-relative semantic work-order path."
  @spec default_path() :: String.t()
  def default_path, do: @default_path

  @doc "Parse and identify one Turtle work order under the base directory."
  @spec identity(String.t(), String.t()) :: {:ok, identity()} | :none
  def identity(base_dir, relative_path \\ @default_path)
      when is_binary(base_dir) and is_binary(relative_path) do
    path = Path.join(base_dir, relative_path)

    case File.read(path) do
      {:ok, bytes} ->
        _graph = Ontology.load!(path)
        {:ok, %{path: relative_path, source_digest: Digest.sha256(bytes)}}

      {:error, :enoent} ->
        :none

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read semantic work order", path: path
    end
  end

  @doc "Manufacture an immutable execution package from work-order and artifact identities."
  @spec execution_package(String.t(), [map()], keyword()) :: map()
  def execution_package(base_dir, artifacts, opts \\ [])
      when is_binary(base_dir) and is_list(artifacts) do
    work_order =
      case identity(base_dir, Keyword.get(opts, :work_order, @default_path)) do
        {:ok, identity} ->
          identity

        :none ->
          raise ArgumentError,
                "semantic work order is required to manufacture an execution package"
      end

    normalized_artifacts =
      artifacts
      |> Enum.map(&normalize_artifact!/1)
      |> Enum.sort_by(& &1.id)

    manufacturer = %{name: "ggen_igniter", version: tool_version()}

    digest_payload = [
      @schema,
      work_order.path,
      work_order.source_digest,
      manufacturer.name,
      manufacturer.version,
      Enum.map(normalized_artifacts, fn artifact ->
        [artifact.id, artifact.digest, artifact.kind]
      end)
    ]

    package_digest = digest_payload |> Jason.encode!() |> Digest.sha256()

    %{
      schema: @schema,
      work_order: work_order,
      manufacturer: manufacturer,
      artifacts: normalized_artifacts,
      package_digest: package_digest
    }
  end

  @doc "Verify package digest and current work-order byte identity without actuation."
  @spec verify_execution_package(String.t(), map()) :: :ok | {:error, atom()}
  def verify_execution_package(base_dir, package) when is_binary(base_dir) and is_map(package) do
    with @schema <- map_get(package, :schema),
         work_order when is_map(work_order) <- map_get(package, :work_order),
         path when is_binary(path) <- map_get(work_order, :path),
         recorded when is_binary(recorded) <- map_get(work_order, :source_digest),
         {:ok, %{source_digest: ^recorded}} <- identity(base_dir, path),
         artifacts when is_list(artifacts) <- map_get(package, :artifacts),
         rebuilt <- execution_package(base_dir, artifacts, work_order: path),
         true <- rebuilt.package_digest == map_get(package, :package_digest) do
      :ok
    else
      :none -> {:error, :work_order_absent}
      {:ok, _different} -> {:error, :work_order_drift}
      false -> {:error, :package_digest_mismatch}
      _ -> {:error, :invalid_package}
    end
  end

  defp normalize_artifact!(artifact) when is_map(artifact) do
    id = map_get(artifact, :id)
    digest = map_get(artifact, :digest)
    kind = map_get(artifact, :kind) || "artifact"

    unless is_binary(id) and id != "" and is_binary(digest) and
             String.starts_with?(digest, "sha256:") do
      raise ArgumentError, "artifact requires non-empty id and sha256: digest"
    end

    %{id: id, digest: digest, kind: to_string(kind)}
  end

  defp map_get(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp tool_version do
    case Application.spec(:ggen_igniter, :vsn) do
      nil -> Mix.Project.config()[:version] |> to_string()
      version -> to_string(version)
    end
  end
end
