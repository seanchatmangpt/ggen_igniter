defmodule GgenIgniter.SA2ADiataxis do
  @moduledoc """
  Deterministic projection boundary for machine-native SA2A Diátaxis.

  The input manifest is authority. This module does not infer repository purpose
  from source text and does not manufacture missing capability semantics. It emits
  a bootstrap plus an intentionally incomplete RDF profile; semantic closure is a
  separate verification step owned by engineering-standards.
  """

  @schema "sa2a-diataxis/v1"
  @roles ~w(runtime semantic manufacture evidence ash-extension product prior-art support)
  @required ~w(schema repository role authority generator capabilities)

  @spec validate_manifest(map()) :: :ok | {:error, term()}
  def validate_manifest(manifest) when is_map(manifest) do
    missing = Enum.reject(@required, &Map.has_key?(manifest, &1))

    cond do
      missing != [] -> {:error, {:missing_fields, missing}}
      manifest["schema"] != @schema -> {:error, {:unsupported_schema, manifest["schema"]}}
      manifest["role"] not in @roles -> {:error, {:unsupported_role, manifest["role"]}}
      not nonempty_strings?(manifest["authority"]) -> {:error, :authority_required}
      not nonempty_strings?(manifest["capabilities"]) -> {:error, :capabilities_required}
      true -> :ok
    end
  end

  def validate_manifest(_), do: {:error, :manifest_must_be_map}

  @spec project(map()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  def project(manifest) do
    with :ok <- validate_manifest(manifest) do
      {:ok,
       %{
         ".sa2a/bootstrap" => bootstrap(),
         ".sa2a/manifest.json" => Jason.encode!(manifest, pretty: true) <> "\n",
         ".sa2a/diataxis.ttl" => profile(manifest)
       }}
    end
  end

  @spec write(map(), Path.t()) :: {:ok, [Path.t()]} | {:error, term()}
  def write(manifest, root) when is_binary(root) do
    with {:ok, files} <- project(manifest) do
      written =
        Enum.map(files, fn {relative, content} ->
          path = Path.join(root, relative)
          path |> Path.dirname() |> File.mkdir_p!()
          File.write!(path, content)
          path
        end)

      {:ok, Enum.sort(written)}
    end
  end

  defp bootstrap do
    """
    schema=sa2a-diataxis/v1
    authority=engineering-standards/semantic/sa2a-diataxis
    generator=ggen-marketplace/packs/sa2a-diataxis-pack
    manifest=.sa2a/manifest.json
    profile=.sa2a/diataxis.ttl
    verify=engineering-standards/semantic/sa2a-diataxis/closure.rq
    """
  end

  defp profile(manifest) do
    repo = ttl(manifest["repository"])
    role = ttl(manifest["role"])
    authority = Enum.map_join(manifest["authority"], " ;\n  sa2a:authority ", &"<#{iri(&1)}>")

    exports =
      manifest["capabilities"]
      |> Enum.map(&"  sa2a:exports <urn:sa2a:capability:#{slug(&1)}> ")
      |> Enum.join(";\n")

    """
    @prefix sa2a: <https://seanchatmangpt.github.io/sa2a/diataxis#> .

    <urn:sa2a:repo:#{slug(manifest["repository"])}>
      a sa2a:RepositoryProfile ;
      sa2a:sourceRepo "#{repo}" ;
      sa2a:role "#{role}" ;
      sa2a:generator <#{iri(manifest["generator"])}> ;
      sa2a:authority #{authority} ;
    #{exports} .
    """
  end

  defp nonempty_strings?(xs) when is_list(xs),
    do: xs != [] and Enum.all?(xs, &(is_binary(&1) and byte_size(String.trim(&1)) > 0))

  defp nonempty_strings?(_), do: false

  defp slug(value),
    do: value |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9._-]+/u, "-")

  defp iri(value) do
    value = to_string(value)

    if String.starts_with?(value, ["http://", "https://", "urn:"]) do
      value
    else
      "https://github.com/seanchatmangpt/" <> String.trim_leading(value, "/")
    end
  end

  defp ttl(value),
    do: value |> to_string() |> String.replace("\\", "\\\\") |> String.replace(""", "\\"")
end
