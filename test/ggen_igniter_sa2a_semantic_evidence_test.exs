defmodule GgenIgniter.SA2A.SemanticEvidenceTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SA2A.SemanticEvidence

  @domain "ashr2rml.vkg.canonical.v1\n"

  test "admits and projects only powerless evidence reference" do
    envelope = envelope()
    assert {:ok, ^envelope} = SemanticEvidence.admit(envelope)
    assert {:ok, ref} = SemanticEvidence.reference(envelope)
    assert ref["authority"] == "NONE"
    assert ref["consequence"] == "EVIDENCE_ONLY"
    refute Map.has_key?(ref, "payload")
  end

  test "refuses evidence that tries to acquire DO authority" do
    assert {:error, {:refused_sa2a_semantic_evidence, :authority, _}} =
             envelope() |> Map.put("authority", "DO") |> SemanticEvidence.admit()
  end

  test "refuses mutation under a retained envelope digest" do
    assert {:error, {:refused_sa2a_semantic_evidence, :envelope_digest, _}} =
             envelope() |> Map.put("subject", "urn:customer:43") |> SemanticEvidence.admit()
  end

  defp envelope do
    body = %{
      "schema" => "sa2a.semantic-evidence-envelope.v1",
      "contractVersion" => "v26.9.29",
      "canonicalization" => "RDFC-1.0",
      "authority" => "NONE",
      "consequence" => "EVIDENCE_ONLY",
      "subject" => "urn:customer:42",
      "source" => %{
        "id" => "customer",
        "uri" => "urn:source:customer",
        "graph" => "urn:graph:customer",
        "subjectTemplate" => "https://example.org/customer/{id}",
        "version" => "1",
        "digest" => "sha256:" <> String.duplicate("a", 64)
      },
      "graphDigest" => "sha256:" <> String.duplicate("b", 64),
      "replayIdentity" => "replay:customer:42",
      "receiptDigest" => nil,
      "provenance" => %{"producer" => "ash_r2rml"}
    }

    digest =
      body
      |> canonical_json()
      |> then(&:crypto.hash(:sha256, [@domain, &1]))
      |> Base.encode16(case: :lower)

    Map.put(body, "envelopeDigest", "sha256:" <> digest)
  end

  defp canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ":", canonical_json(item)] end)
      |> Enum.sort_by(&IO.iodata_to_binary/1)

    IO.iodata_to_binary(["{", Enum.intersperse(members, ","), "}"])
  end

  defp canonical_json(value) when is_list(value),
    do: IO.iodata_to_binary(["[", value |> Enum.map(&canonical_json/1) |> Enum.intersperse(","), "]"])

  defp canonical_json(value), do: Jason.encode!(value)
end
