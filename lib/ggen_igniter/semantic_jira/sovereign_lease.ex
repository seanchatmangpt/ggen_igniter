defmodule GgenIgniter.SemanticJira.SovereignLease do
  @moduledoc """
  Sovereign ceiling lease (authority kind 0x04) — the multi-party EdDSA-signed
  grant that a work order with `authority_requirement: "SOVEREIGN"` must
  carry: strictly monotonic ontology evolution is leased, not self-declared.

  Laws (all enforced by `admit/3`):

    * Multi-party: at least 2 signature records from at least 2 DISTINCT
      signers. Every record is an Ed25519 (`:crypto` eddsa, `alg: "EdDSA"`)
      signature over the canonical lease bytes (see `canonical_json/1`),
      verified against the caller-supplied public keys.
    * Strictly monotonic evolution: a lease is granted over a pre-evolution
      `ontology_digest`; admitting it against the CURRENT pack ontology
      digest requires a real digest delta — `:shape_digest_unchanged`
      otherwise, because a lease over an unchanged ontology is a no-op.
    * No wall clock in the admit decision: `granted_at` is recorded and
      shape-checked, never evaluated. The time law lives in the presenting
      system.

  Refusals: `{:refused_sovereign, reason}` with `:insufficient_signatures`,
  `:signature_invalid`, `:shape_digest_unchanged`, plus the fail-closed shape
  guard `:invalid_lease` for input that is not even a well-formed lease.

  Toolchain note for tests and consumers: on this OTP 27.2.4 build
  `:crypto.generate_key(:eddsa, :ed25519)` returns `{public, private}`
  (element order verified against the RFC 8032 test vector), and the
  sign/verify key shape is `[key_binary, :ed25519]`.
  """

  @enforce_keys [:lease_id, :subject_iri, :shapes, :ontology_digest, :granted_at, :signatures]
  defstruct [:lease_id, :subject_iri, :shapes, :ontology_digest, :granted_at, :signatures]

  @alg "EdDSA"
  @curve :ed25519
  @min_signatures 2
  @scalar_fields ~w(lease_id subject_iri ontology_digest granted_at)
  @derived_keys ["signatures", "admitted", "verified_signers"]

  @type t :: %__MODULE__{
          lease_id: String.t(),
          subject_iri: String.t(),
          shapes: [String.t()],
          ontology_digest: String.t(),
          granted_at: String.t(),
          signatures: [map()]
        }

  @doc """
  Normalizes a struct or string-keyed map into the string-keyed lease map the
  JSONL candidate plane speaks. Non-map input normalizes to `nil` and fails
  closed in `admit/3`.
  """
  @spec normalize(t() | map()) :: map() | nil
  def normalize(%__MODULE__{} = lease) do
    %{
      "lease_id" => lease.lease_id,
      "subject_iri" => lease.subject_iri,
      "shapes" => lease.shapes,
      "ontology_digest" => lease.ontology_digest,
      "granted_at" => lease.granted_at,
      "signatures" => lease.signatures
    }
  end

  def normalize(lease) when is_map(lease), do: lease
  def normalize(_other), do: nil

  @doc """
  EdDSA-signs the canonical bytes of `lease` with the raw Ed25519 private key
  `priv`, returning one signature record.
  """
  @spec sign(t() | map(), String.t(), binary()) :: map()
  def sign(lease, signer, priv) when is_binary(priv) do
    msg = canonical_json(normalize(lease))
    sig = :crypto.sign(:eddsa, :none, msg, [priv, @curve])
    %{"signer" => signer, "alg" => @alg, "sig" => Base.encode16(sig, case: :lower)}
  end

  @doc """
  Admits `lease` for ontology evolution TO the current pack ontology digest
  `pack_ontology_digest`.

  `opts[:public_keys]` is `%{signer => raw 32-byte Ed25519 public key}`. Every
  signature record must verify against its signer's key, the lease must carry
  at least 2 signatures from at least 2 distinct signers, and the lease's
  recorded `ontology_digest` must differ from `pack_ontology_digest` (the
  strictly monotonic evolution law).

  Returns `{:ok, admitted_record}` — the lease minus the signatures key, plus
  `"admitted": true` and the sorted `"verified_signers"` — or
  `{:error, {:refused_sovereign, reason}}`. Pure; no wall clock.
  """
  @spec admit(term(), String.t(), keyword()) ::
          {:ok, map()} | {:error, {:refused_sovereign, atom()}}
  def admit(lease, pack_ontology_digest, opts \\ [])

  def admit(lease, pack_ontology_digest, opts) when is_binary(pack_ontology_digest) do
    keys = Keyword.get(opts, :public_keys, %{})

    with lease when is_map(lease) <- normalize(lease),
         :ok <- shape(lease),
         :ok <- digest_delta(lease, pack_ontology_digest),
         :ok <- signature_gate(lease, keys) do
      signers =
        lease["signatures"]
        |> Enum.map(& &1["signer"])
        |> Enum.uniq()
        |> Enum.sort()

      {:ok,
       lease
       |> Map.drop(["signatures"])
       |> Map.put("verified_signers", signers)
       |> Map.put("admitted", true)}
    else
      {:error, reason} -> {:error, {:refused_sovereign, reason}}
      _other -> {:error, {:refused_sovereign, :invalid_lease}}
    end
  end

  def admit(_lease, _pack_ontology_digest, _opts),
    do: {:error, {:refused_sovereign, :invalid_lease}}

  # ── gates ────────────────────────────────────────────────────────────────

  defp shape(lease) do
    scalar = Enum.all?(@scalar_fields, &is_binary(Map.get(lease, &1)))

    if scalar and
         is_list(Map.get(lease, "shapes")) and
         lease["shapes"] != [] and
         is_list(Map.get(lease, "signatures")) do
      :ok
    else
      {:error, :invalid_lease}
    end
  end

  defp digest_delta(lease, pack_ontology_digest) do
    if lease["ontology_digest"] == pack_ontology_digest do
      {:error, :shape_digest_unchanged}
    else
      :ok
    end
  end

  # The signature loop: the multi-party law (>= 2 signatures from >= 2
  # DISTINCT signers) and the EdDSA verification both live behind this one
  # gate — a single named seam so the anti-vacuity court can bypass exactly
  # this line and require the 1-signature test to fail.
  defp signature_gate(lease, keys) do
    with :ok <- count(lease), :ok <- verify_all(lease, keys), do: :ok
  end

  defp count(lease) do
    distinct =
      lease["signatures"]
      |> Enum.map(& &1["signer"])
      |> Enum.uniq()
      |> length()

    if length(lease["signatures"]) >= @min_signatures and distinct >= @min_signatures do
      :ok
    else
      {:error, :insufficient_signatures}
    end
  end

  defp verify_all(lease, keys) do
    msg = canonical_json(lease)

    if Enum.all?(lease["signatures"], &signature_record_ok?(&1, msg, keys)) do
      :ok
    else
      {:error, :signature_invalid}
    end
  end

  defp signature_record_ok?(sig, msg, keys) do
    pub = Map.get(keys, sig["signer"])
    sig64 = decode_sig(sig)

    is_binary(pub) and
      sig["alg"] == @alg and
      is_binary(sig64) and byte_size(sig64) == 64 and
      crypto_verify?(msg, sig64, pub)
  end

  defp crypto_verify?(msg, sig64, pub),
    do: :crypto.verify(:eddsa, :none, msg, sig64, [pub, @curve])

  defp decode_sig(%{"sig" => sig}) when is_binary(sig) do
    case Base.decode16(String.upcase(sig), padding: false) do
      {:ok, raw} -> raw
      :error -> nil
    end
  end

  defp decode_sig(_), do: nil

  @doc """
  The canonical lease bytes: sorted-key compact JSON of the lease map minus
  the `signatures` key and every derived key. `sign/3` and `admit/3` sign and
  verify exactly these bytes.
  """
  @spec canonical_json(map()) :: String.t()
  def canonical_json(lease) when is_map(lease) do
    body =
      lease
      |> Map.drop(@derived_keys)
      |> Enum.map(fn {k, v} -> Jason.encode!(k) <> ":" <> Jason.encode!(v) end)
      |> Enum.sort()
      |> Enum.join(",")

    "{" <> body <> "}"
  end
end
