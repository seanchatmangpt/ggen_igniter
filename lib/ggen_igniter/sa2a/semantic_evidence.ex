defmodule GgenIgniter.SA2A.SemanticEvidence do
  @moduledoc """
  Authority-free consumer for the canonical SA2A semantic-evidence envelope.

  The canonical source is ggen-marketplace's sa2a-semantic-evidence-pack.
  This boundary verifies the portable AshR2RML envelope and projects only an
  inert evidence reference for generated consumers. It never grants standing,
  authorization, or DO authority.
  """

  @schema "sa2a.semantic-evidence-envelope.v1"
  @contract_version "v26.9.29"
  @canonicalization "RDFC-1.0"
  @domain "ashr2rml.vkg.canonical.v1\n"
  @marketplace_pack "packs/sa2a-semantic-evidence-pack"
  @graphlaw_contract_commit "4e4873ca377d50af5268e8736be4afe6badeb862"

  @type refusal :: {:refused_sa2a_semantic_evidence, atom(), map()}

  @spec contract() :: map()
  def contract do
    %{
      schema: @schema,
      contract_version: @contract_version,
      canonicalization: @canonicalization,
      authority: "NONE",
      consequence: "EVIDENCE_ONLY",
      marketplace_pack: @marketplace_pack,
      graphlaw_contract_commit: @graphlaw_contract_commit
    }
  end

  @spec admit(map() | binary()) :: {:ok, map()} | {:error, refusal()}
  def admit(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> admit(map)
      {:ok, other} -> refuse(:shape, %{observed: inspect(other)})
      {:error, error} -> refuse(:json, %{error: Exception.message(error)})
    end
  end

  def admit(envelope) when is_map(envelope) do
    with :ok <- constant(envelope, "schema", @schema, :schema),
         :ok <- constant(envelope, "contractVersion", @contract_version, :contract_version),
         :ok <- constant(envelope, "canonicalization", @canonicalization, :canonicalization),
         :ok <- constant(envelope, "authority", "NONE", :authority),
         :ok <- constant(envelope, "consequence", "EVIDENCE_ONLY", :consequence),
         :ok <- non_empty(envelope["subject"], :subject),
         :ok <- source(envelope["source"]),
         :ok <- sha256(envelope["graphDigest"], :graph_digest),
         :ok <- non_empty(envelope["replayIdentity"], :replay_identity),
         :ok <- provenance(envelope["provenance"]),
         :ok <- replay_digest(envelope) do
      {:ok, envelope}
    end
  end

  def admit(other), do: refuse(:shape, %{observed: inspect(other)})

  @doc "Project the admitted envelope to the powerless reference generated consumers carry."
  @spec reference(map() | binary()) :: {:ok, map()} | {:error, refusal()}
  def reference(envelope) do
    with {:ok, admitted} <- admit(envelope) do
      {:ok,
       %{
         "schema" => admitted["schema"],
         "contractVersion" => admitted["contractVersion"],
         "subject" => admitted["subject"],
         "sourceDigest" => admitted["source"]["digest"],
         "graphDigest" => admitted["graphDigest"],
         "replayIdentity" => admitted["replayIdentity"],
         "envelopeDigest" => admitted["envelopeDigest"],
         "authority" => "NONE",
         "consequence" => "EVIDENCE_ONLY"
       }}
    end
  end

  defp constant(map, key, expected, subject) do
    if map[key] == expected,
      do: :ok,
      else: refuse(subject, %{expected: expected, observed: map[key]})
  end

  defp source(%{
         "id" => id,
         "uri" => uri,
         "graph" => graph,
         "subjectTemplate" => template,
         "digest" => digest
       }) do
    with :ok <- non_empty(id, :source_id),
         :ok <- absolute(uri, :source_uri),
         :ok <- absolute(graph, :source_graph),
         :ok <- non_empty(template, :subject_template) do
      sha256(digest, :source_digest)
    end
  end

  defp source(other), do: refuse(:source, %{observed: inspect(other)})

  defp provenance(%{"producer" => producer}) when is_binary(producer) and producer != "", do: :ok
  defp provenance(other), do: refuse(:provenance, %{observed: inspect(other)})

  defp replay_digest(%{"envelopeDigest" => "sha256:" <> observed} = envelope)
       when byte_size(observed) == 64 do
    try do
      expected =
        envelope
        |> Map.delete("envelopeDigest")
        |> canonical_json()
        |> then(&:crypto.hash(:sha256, [@domain, &1]))
        |> Base.encode16(case: :lower)

      if observed == expected,
        do: :ok,
        else: refuse(:envelope_digest, %{expected: expected, observed: observed})
    rescue
      error in ArgumentError -> refuse(:envelope, %{error: Exception.message(error)})
    end
  end

  defp replay_digest(other), do: refuse(:envelope_digest, %{observed: inspect(other)})

  defp canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.map(fn
        {key, item} when is_binary(key) -> [Jason.encode!(key), ":", canonical_json(item)]
        {key, _} -> raise ArgumentError, "non-portable key: #{inspect(key)}"
      end)
      |> Enum.sort_by(&IO.iodata_to_binary/1)

    IO.iodata_to_binary(["{", Enum.intersperse(members, ","), "}"])
  end

  defp canonical_json(value) when is_list(value),
    do:
      IO.iodata_to_binary([
        "[",
        value |> Enum.map(&canonical_json/1) |> Enum.intersperse(","),
        "]"
      ])

  defp canonical_json(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: Jason.encode!(value)

  defp canonical_json(value),
    do: raise(ArgumentError, "non-JSON evidence value: #{inspect(value)}")

  defp sha256("sha256:" <> hex = value, subject) when byte_size(hex) == 64 do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, hex),
      do: :ok,
      else: refuse(subject, %{observed: value})
  end

  defp sha256(value, subject), do: refuse(subject, %{observed: value})

  defp absolute(value, subject) when is_binary(value) do
    if Regex.match?(~r/\A(urn:[A-Za-z0-9][A-Za-z0-9-]*:\S+|https?:\/\/[^\s\/?#]+\S*)\z/, value),
      do: :ok,
      else: refuse(subject, %{observed: value})
  end

  defp absolute(value, subject), do: refuse(subject, %{observed: value})

  defp non_empty(value, _subject) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp non_empty(value, subject), do: refuse(subject, %{observed: value})

  defp refuse(subject, evidence),
    do: {:error, {:refused_sa2a_semantic_evidence, subject, evidence}}
end
