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

  @shared_required [
    :generator_digest,
    :environment_digest,
    :dependency_digest,
    :builder_id,
    :invocation_id
  ]

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
  Admits the shared provenance closure before any consequence-bearing
  reconciliation starts. This lets callers fail closed on missing or malformed
  manufacture identity without first actuating a project.
  """
  @spec admit_provenance_opts(keyword()) :: {:ok, keyword()} | {:error, refusal()}
  def admit_provenance_opts(opts) when is_list(opts) do
    with {:ok, admitted} <- fetch_required(opts, @shared_required),
         :ok <- validate_digest(:generator_digest, admitted[:generator_digest]),
         :ok <- validate_digest(:environment_digest, admitted[:environment_digest]),
         :ok <- validate_digest(:dependency_digest, admitted[:dependency_digest]),
         :ok <- validate_nonempty(:builder_id, admitted[:builder_id]),
         :ok <- validate_nonempty(:invocation_id, admitted[:invocation_id]),
         :ok <- validate_dependencies(Keyword.get(opts, :resolved_dependencies, [])) do
      {:ok,
       admitted
       |> Keyword.put(:authority_ceiling, Keyword.get(opts, :authority_ceiling, :construct))
       |> Keyword.put(:disposition, Keyword.get(opts, :disposition, :ephemeral))
       |> Keyword.put(:resolved_dependencies, Keyword.get(opts, :resolved_dependencies, []))}
    end
  end

  @doc """
  Builds and admits one ephemeral projection from exact artifact bytes.

  Required provenance digests use ggen_igniter's existing `sha256:<hex>`
  convention. The artifact digest is manufactured here from the exact bytes,
  preventing a caller from supplying an unrelated subject digest.
  """
  @spec manufacture(binary(), keyword()) ::
          {:ok, t()} | {:error, refusal() | SemanticEpoch.refusal()}
  def manufacture(bytes, opts) when is_binary(bytes) and is_list(opts) do
    with {:ok, shared} <- admit_provenance_opts(opts),
         {:ok, identity} <- fetch_required(opts, [:name, :graph_digest]),
         :ok <- validate_nonempty(:name, identity[:name]),
         :ok <- validate_digest(:graph_digest, identity[:graph_digest]) do
      projection = %__MODULE__{
        name: identity[:name],
        graph_digest: identity[:graph_digest],
        generator_digest: shared[:generator_digest],
        environment_digest: shared[:environment_digest],
        dependency_digest: shared[:dependency_digest],
        artifact_digest: Digest.sha256(bytes),
        builder_id: shared[:builder_id],
        invocation_id: shared[:invocation_id],
        authority_ceiling: shared[:authority_ceiling],
        disposition: shared[:disposition],
        resolved_dependencies: shared[:resolved_dependencies]
      }

      with {:ok, _epoch} <- SemanticEpoch.admit(:ephemeral, epoch_declaration(projection)) do
        {:ok, projection}
      end
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
          "metadata" => %{
            "invocationId" => projection.invocation_id,
            "verificationReceiptHash" => projection.verification_receipt_hash
          }
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

  defp fetch_required(opts, keys) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, acc} ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> {:cont, {:ok, Keyword.put(acc, key, value)}}
        :error -> {:halt, {:error, {:refused_ephemeral_projection, :missing_option, key}}}
      end
    end)
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

  defp validate_nonempty(_field, value) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp validate_nonempty(field, _value),
    do: {:error, {:refused_ephemeral_projection, :invalid_option, field}}

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
