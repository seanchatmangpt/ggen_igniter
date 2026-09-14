defmodule GgenIgniter.EphemeralProjection do
  @moduledoc """
  Admitted identity and provenance for a graph-generated ephemeral projection.

  The projection bytes are not canonical truth. `graph_digest` identifies the
  admitted semantic subject; the remaining digests identify the lawful
  manufacturing closure that produced one disposable artifact.

  This module deliberately does not write, execute, deploy, or delete files.
  Physical changes remain on the existing reconciliation/actuation path.
  `retirement_intent/1` is data for that path, never authority to perform DO.
  """

  alias GgenIgniter.{Digest, SemanticEpoch}

  @in_toto_statement "https://in-toto.io/Statement/v1"
  @slsa_provenance "https://slsa.dev/provenance/v1"
  @build_type "https://seanchatmangpt.github.io/ggen-igniter/ephemeral-projection/v26.9.15"

  @enforce_keys [
    :name,
    :graph_digest,
    :generator_digest,
    :environment_digest,
    :dependency_digest,
    :artifact_digest,
    :builder_id,
    :invocation_id
  ]
  defstruct [
    :name,
    :graph_digest,
    :generator_digest,
    :environment_digest,
    :dependency_digest,
    :artifact_digest,
    :builder_id,
    :invocation_id,
    :verification_receipt_hash,
    authority_ceiling: :construct,
    disposition: :ephemeral,
    status: :manufactured,
    resolved_dependencies: []
  ]

  @type t :: %__MODULE__{}
  @type refusal ::
          {:refused_ephemeral_projection, atom()}
          | {:refused_ephemeral_projection, atom(), term()}

  @doc """
  Builds and admits one ephemeral projection from exact artifact bytes.

  Required provenance digests use ggen_igniter's existing `sha256:<hex>`
  convention. The artifact digest is manufactured here from the exact bytes,
  preventing a caller from supplying an unrelated subject digest.
  """
  @spec manufacture(binary(), keyword()) ::
          {:ok, t()} | {:error, refusal() | SemanticEpoch.refusal()}
  def manufacture(bytes, opts) when is_binary(bytes) and is_list(opts) do
    projection = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      graph_digest: Keyword.fetch!(opts, :graph_digest),
      generator_digest: Keyword.fetch!(opts, :generator_digest),
      environment_digest: Keyword.fetch!(opts, :environment_digest),
      dependency_digest: Keyword.fetch!(opts, :dependency_digest),
      artifact_digest: Digest.sha256(bytes),
      builder_id: Keyword.fetch!(opts, :builder_id),
      invocation_id: Keyword.fetch!(opts, :invocation_id),
      authority_ceiling: Keyword.get(opts, :authority_ceiling, :construct),
      disposition: Keyword.get(opts, :disposition, :ephemeral),
      resolved_dependencies: Keyword.get(opts, :resolved_dependencies, [])
    }

    with {:ok, _epoch} <- SemanticEpoch.admit(:ephemeral, epoch_declaration(projection)),
         :ok <- validate_digest(:graph_digest, projection.graph_digest),
         :ok <- validate_digest(:generator_digest, projection.generator_digest),
         :ok <- validate_digest(:environment_digest, projection.environment_digest),
         :ok <- validate_digest(:dependency_digest, projection.dependency_digest),
         :ok <- validate_dependencies(projection.resolved_dependencies) do
      {:ok, projection}
    end
  end

  @doc """
  Advances a manufactured projection to `:verified` only with an exact
  verification-receipt digest. This records evidence; it does not execute the
  projection and does not confer ALIVE standing.
  """
  @spec verify(t(), String.t()) :: {:ok, t()} | {:error, refusal()}
  def verify(%__MODULE__{status: :manufactured} = projection, receipt_hash) do
    case validate_digest(:verification_receipt_hash, receipt_hash) do
      :ok ->
        {:ok,
         %{
           projection
           | status: :verified,
             verification_receipt_hash: receipt_hash
         }}

      {:error, _} = error ->
        error
    end
  end

  def verify(%__MODULE__{} = projection, _receipt_hash),
    do:
      {:error,
       {:refused_ephemeral_projection, :invalid_verification_transition, projection.status}}

  @doc """
  Returns a retirement intent only after verification evidence exists.

  The returned map is deliberately not executed here. A caller must route it
  through the repository's admitted actuation/authority boundary.
  """
  @spec retirement_intent(t()) :: {:ok, map()} | {:error, refusal()}
  def retirement_intent(%__MODULE__{status: :verified} = projection) do
    {:ok,
     %{
       operation: :retire_projection,
       subject: projection.name,
       artifact_digest: projection.artifact_digest,
       graph_digest: projection.graph_digest,
       verification_receipt_hash: projection.verification_receipt_hash,
       authority: :none
     }}
  end

  def retirement_intent(%__MODULE__{} = projection),
    do: {:error, {:refused_ephemeral_projection, :unverified_retirement, projection.status}}

  @doc """
  Renders the projection as an in-toto Statement carrying a SLSA Provenance
  predicate shape. ggen_igniter-specific graph and authority fields are
  bounded extensions inside `externalParameters`; they are not claims of
  SLSA certification.
  """
  @spec provenance_statement(t()) :: map()
  def provenance_statement(%__MODULE__{} = projection) do
    %{
      "_type" => @in_toto_statement,
      "subject" => [
        %{
          "name" => projection.name,
          "digest" => %{"sha256" => strip_sha256(projection.artifact_digest)}
        }
      ],
      "predicateType" => @slsa_provenance,
      "predicate" => %{
        "buildDefinition" => %{
          "buildType" => @build_type,
          "externalParameters" => %{
            "semanticGraphDigest" => projection.graph_digest,
            "generatorDigest" => projection.generator_digest,
            "environmentDigest" => projection.environment_digest,
            "dependencyClosureDigest" => projection.dependency_digest,
            "authorityCeiling" => Atom.to_string(projection.authority_ceiling),
            "disposition" => Atom.to_string(projection.disposition)
          },
          "internalParameters" => %{},
          "resolvedDependencies" => projection.resolved_dependencies
        },
        "runDetails" => %{
          "builder" => %{"id" => projection.builder_id},
          "metadata" => %{"invocationId" => projection.invocation_id}
        }
      }
    }
  end

  @doc "Receipt metadata that can be embedded in the existing GgenIgniter.Receipt metadata map."
  @spec receipt_metadata(t()) :: map()
  def receipt_metadata(%__MODULE__{} = projection) do
    %{
      "semantic_epoch" => SemanticEpoch.version(:ephemeral),
      "semantic_graph_digest" => projection.graph_digest,
      "ephemeral_projection" => true,
      "projection_digest" => projection.artifact_digest,
      "verification_receipt_hash" => projection.verification_receipt_hash,
      "authority_ceiling" => Atom.to_string(projection.authority_ceiling)
    }
  end

  defp epoch_declaration(projection) do
    SemanticEpoch.invariants(:ephemeral)
    |> Map.put(:generator_authority_ceiling, projection.authority_ceiling)
    |> Map.put(:projection_disposition, projection.disposition)
  end

  defp validate_digest(field, "sha256:" <> hex) when byte_size(hex) == 64 do
    if String.match?(hex, ~r/\A[0-9a-f]{64}\z/) do
      :ok
    else
      {:error, {:refused_ephemeral_projection, :invalid_digest, field}}
    end
  end

  defp validate_digest(field, _value),
    do: {:error, {:refused_ephemeral_projection, :invalid_digest, field}}

  defp validate_dependencies(dependencies) when is_list(dependencies) do
    if Enum.all?(dependencies, &valid_dependency?/1) do
      :ok
    else
      {:error, {:refused_ephemeral_projection, :invalid_resolved_dependency}}
    end
  end

  defp validate_dependencies(_),
    do: {:error, {:refused_ephemeral_projection, :invalid_resolved_dependency}}

  defp valid_dependency?(%{"uri" => uri, "digest" => digest})
       when is_binary(uri) and is_map(digest) and map_size(digest) > 0,
       do:
         Enum.all?(digest, fn {algorithm, value} -> is_binary(algorithm) and is_binary(value) end)

  defp valid_dependency?(_), do: false

  defp strip_sha256("sha256:" <> hex), do: hex
end
