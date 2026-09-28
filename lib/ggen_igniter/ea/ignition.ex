defmodule GgenIgniter.EA.Ignition do
  @moduledoc """
  EA-aware ignition admission (RFC `docs/rfc/v26.9.26/abb-sbb-implementation.md`).

  The admission kernel for DoD items 1, 3, 4, 5, 6 and 8 of that RFC. It is a
  pure function over an ignition input map (string keys, as decoded from
  JSON/TOML); it performs no I/O, grants no authority and never actuates.

  ## Input shape (every key required, no other top-level key admitted)

      %{
        "architectureContract" => %{"iri" => iri, "digest" => "sha256:<64 hex>"},
        "abb"                  => %{"iri" => iri, "digest" => digest},
        "sbb"                  => %{"iri" => iri, "digest" => digest,
                                     "realizes" => abb_iri,
                                     "standing" => "ALIVE",
                                     "qualification" => %{"digest" => digest,
                                                          "mutable" => false}},
        "originAuthority"      => %{"iri" => iri, "digest" => digest},
        "authorityCeiling"     => "SELECT" | "CONSTRUCT",
        "provenance"           => %{"digest" => digest}
      }

  ## Laws

    * the origin authority is REQUIRED and bound by digest; ignition never
      self-declares origin (`:origin_authority_missing`);
    * qualification must be immutable: `"mutable" => false` and a pinned
      digest; any movable ref key (`"ref"`, `"branch"`, `"tag"`,
      `"latest"`) is refused (`{:qualification_mutable, reason}`);
    * only `"ALIVE"` SBB standing is admitted; `UNKNOWN` and every other
      value is refused (`{:standing_not_admitted, s}`);
    * the authority ceiling is `SELECT` or `CONSTRUCT`; `DO` or anything
      else is `{:authority_widening, c}` -- no generated project
      manufactures consequential authority;
    * the SBB must realize the bound ABB (`{:sbb_does_not_realize_abb, ..}`);
    * unknown top-level keys are refused (`{:unknown_field, k}`) so an
      input cannot smuggle an authority grant past the kernel.

  ## Identity

  `architecture_identity` digests contract + ABB + origin authority only;
  it is invariant under SBB substitution (DoD 5). `binding_identity`
  additionally covers SBB, qualification, ceiling and provenance. Both are
  `"sha256:" <> hex` over a line-oriented canonical encoding (fixed key
  order, one `key=value` per line), so any runtime can recompute them.

  `lock/1` renders the persisted lock text (DoD 3); `verify_lock/2` refuses
  a lock whose recorded digests do not recompute (`{:lock_mismatch, key}`).
  `substitute/2` admits a replacement SBB for the same ABB and returns a
  deterministic migration receipt (DoD 6); `apply_migration/2` refuses a
  stale or replayed receipt (`{:stale_subject, expected, actual}`) and a
  receipt whose digest does not recompute (`:receipt_digest_mismatch`).
  """

  alias GgenIgniter.Digest

  @top_keys ~w(architectureContract abb sbb originAuthority authorityCeiling provenance)
  @admitted_ceilings ~w(SELECT CONSTRUCT)
  @ceiling_rank %{"SELECT" => 1, "CONSTRUCT" => 2}
  @admitted_standings ~w(ALIVE)
  @movable_ref_keys ~w(ref branch tag latest)
  @digest_re ~r/\Asha256:[0-9a-f]{64}\z/
  @receipt_context "ea-sbb-migration:v1"
  @receipt_keys Enum.sort(
                  ~w(context architectureIdentity from to fromSbb toSbb abb receiptDigest)
                )

  @type refusal ::
          :input_not_map
          | :origin_authority_missing
          | {:missing_field, String.t()}
          | {:unknown_field, String.t()}
          | {:field_invalid, String.t()}
          | {:digest_invalid, String.t()}
          | {:qualification_mutable, String.t()}
          | {:standing_not_admitted, term()}
          | {:authority_widening, term()}
          | {:sbb_does_not_realize_abb, String.t(), String.t()}

  @type binding :: %{
          contract: %{iri: String.t(), digest: String.t()},
          abb: %{iri: String.t(), digest: String.t()},
          sbb: %{iri: String.t(), digest: String.t(), qualification: String.t()},
          origin: %{iri: String.t(), digest: String.t()},
          ceiling: String.t(),
          provenance: String.t(),
          architecture_identity: String.t(),
          binding_identity: String.t()
        }

  @doc "Admit an ignition input or return the first typed refusal."
  @spec admit(term()) :: {:ok, binding()} | {:error, refusal()}
  def admit(input) when is_map(input) do
    with :ok <- no_unknown_keys(input),
         {:ok, origin} <- origin(input),
         {:ok, contract} <- iri_digest(input, "architectureContract"),
         {:ok, abb} <- iri_digest(input, "abb"),
         {:ok, sbb} <- sbb(input, abb),
         {:ok, ceiling} <- ceiling(input),
         {:ok, provenance} <- provenance(input) do
      {:ok,
       finalize(%{
         contract: contract,
         abb: abb,
         sbb: sbb,
         origin: origin,
         ceiling: ceiling,
         provenance: provenance
       })}
    end
  end

  def admit(_), do: {:error, :input_not_map}

  @doc "Persisted lock text for a generated project (DoD 3). Deterministic."
  @spec lock(binding()) :: String.t()
  def lock(b) do
    lines(b) <>
      "architecture_identity=#{b.architecture_identity}\n" <>
      "binding_identity=#{b.binding_identity}\n"
  end

  @doc """
  Verify a persisted lock against an admitted binding: every line must
  equal the binding's own rendering, and the recorded identities must
  recompute from the recorded fields (detects tamper and stale locks).
  """
  @spec verify_lock(String.t(), binding()) :: :ok | {:error, {:lock_mismatch, String.t()}}
  def verify_lock(text, b) when is_binary(text) do
    recorded = parse_lock(text)
    expected = parse_lock(lock(b))

    keys = expected |> Map.keys() |> Enum.sort()

    if recorded |> Map.keys() |> Enum.sort() != keys do
      {:error, {:lock_mismatch, "keys"}}
    else
      case Enum.find(keys, &(recorded[&1] != expected[&1])) do
        nil -> :ok
        k -> {:error, {:lock_mismatch, k}}
      end
    end
  end

  @doc """
  Admit a substitute SBB for the SAME ABB (DoD 5/6/8). The new input must
  bind the same contract, ABB and origin authority, must not widen the
  ceiling, and must change the SBB digest. Returns the new binding and a
  deterministic migration receipt.
  """
  @spec substitute(binding(), map()) ::
          {:ok, binding(), map()}
          | {:error,
             refusal()
             | :substitution_noop
             | {:architecture_identity_changed, String.t()}}
  def substitute(old, new_input) do
    with {:ok, new} <- admit(new_input),
         :ok <- same_architecture(old, new),
         :ok <- no_widening(old.ceiling, new.ceiling),
         :ok <- changed_sbb(old, new) do
      {:ok, new, receipt(old, new)}
    end
  end

  @doc """
  Apply a migration receipt to the current binding. Refuses a receipt whose
  digest does not recompute, a receipt whose `from` is not the current
  binding (stale / duplicate / reordered delivery), and a `to` binding that
  does not match the receipt.
  """
  @spec apply_migration(binding(), map(), binding()) ::
          {:ok, binding()}
          | {:error,
             :receipt_malformed
             | :receipt_digest_mismatch
             | {:stale_subject, String.t(), String.t()}}
  def apply_migration(current, receipt, to) do
    cond do
      not is_map(receipt) or Enum.sort(Map.keys(receipt)) != @receipt_keys ->
        {:error, :receipt_malformed}

      receipt_digest(Map.delete(receipt, "receiptDigest")) != receipt["receiptDigest"] ->
        {:error, :receipt_digest_mismatch}

      receipt["from"] != current.binding_identity ->
        {:error, {:stale_subject, receipt["from"], current.binding_identity}}

      receipt["to"] != to.binding_identity or
          receipt["architectureIdentity"] != to.architecture_identity ->
        {:error, {:stale_subject, receipt["to"], to.binding_identity}}

      true ->
        {:ok, to}
    end
  end

  # -- admission helpers ----------------------------------------------------

  defp no_unknown_keys(input) do
    case Enum.find(Enum.sort(Map.keys(input)), &(&1 not in @top_keys)) do
      nil -> :ok
      k -> {:error, {:unknown_field, to_string(k)}}
    end
  end

  defp origin(input) do
    case Map.get(input, "originAuthority") do
      nil -> {:error, :origin_authority_missing}
      m when m == %{} -> {:error, :origin_authority_missing}
      _ -> iri_digest(input, "originAuthority")
    end
  end

  defp iri_digest(input, key) do
    with {:ok, m} <- fetch_map(input, key, key),
         {:ok, iri} <- fetch_iri(m, "iri", key <> ".iri"),
         {:ok, d} <- fetch_digest(m, "digest", key <> ".digest") do
      {:ok, %{iri: iri, digest: d}}
    end
  end

  defp sbb(input, abb) do
    with {:ok, %{iri: iri, digest: d}} <- iri_digest(input, "sbb"),
         m = input["sbb"],
         {:ok, realizes} <- fetch_iri(m, "realizes", "sbb.realizes"),
         :ok <- realizes_abb(realizes, abb.iri),
         :ok <- standing(m),
         {:ok, q} <- qualification(m) do
      {:ok, %{iri: iri, digest: d, qualification: q}}
    end
  end

  defp realizes_abb(r, r), do: :ok
  defp realizes_abb(r, abb), do: {:error, {:sbb_does_not_realize_abb, r, abb}}

  defp standing(m) do
    case Map.fetch(m, "standing") do
      {:ok, s} when s in @admitted_standings -> :ok
      {:ok, s} -> {:error, {:standing_not_admitted, s}}
      :error -> {:error, {:missing_field, "sbb.standing"}}
    end
  end

  defp qualification(m) do
    with {:ok, q} <- fetch_map(m, "qualification", "sbb.qualification") do
      movable = Enum.find(@movable_ref_keys, &Map.has_key?(q, &1))

      cond do
        movable != nil -> {:error, {:qualification_mutable, "movable ref: " <> movable}}
        Map.get(q, "mutable") != false -> {:error, {:qualification_mutable, "mutable not false"}}
        true -> fetch_digest(q, "digest", "sbb.qualification.digest")
      end
    end
  end

  defp ceiling(input) do
    case Map.fetch(input, "authorityCeiling") do
      {:ok, c} when c in @admitted_ceilings -> {:ok, c}
      {:ok, c} -> {:error, {:authority_widening, c}}
      :error -> {:error, {:missing_field, "authorityCeiling"}}
    end
  end

  defp provenance(input) do
    with {:ok, m} <- fetch_map(input, "provenance", "provenance") do
      fetch_digest(m, "digest", "provenance.digest")
    end
  end

  defp fetch_map(m, key, path) do
    case Map.fetch(m, key) do
      {:ok, v} when is_map(v) -> {:ok, v}
      {:ok, _} -> {:error, {:field_invalid, path}}
      :error -> {:error, {:missing_field, path}}
    end
  end

  # An IRI must be a non-empty absolute IRI with no whitespace, newline or
  # `=` (the canonical encoding is line/`=` delimited; admitting either
  # would let one field forge another field's line).
  defp fetch_iri(m, key, path) do
    case Map.fetch(m, key) do
      {:ok, v} when is_binary(v) ->
        if Regex.match?(~r/\A[a-zA-Z][a-zA-Z0-9+.-]*:[^\s=]+\z/, v),
          do: {:ok, v},
          else: {:error, {:field_invalid, path}}

      {:ok, _} ->
        {:error, {:field_invalid, path}}

      :error ->
        {:error, {:missing_field, path}}
    end
  end

  defp fetch_digest(m, key, path) do
    case Map.fetch(m, key) do
      {:ok, v} when is_binary(v) ->
        if Regex.match?(@digest_re, v), do: {:ok, v}, else: {:error, {:digest_invalid, path}}

      {:ok, _} ->
        {:error, {:digest_invalid, path}}

      :error ->
        {:error, {:missing_field, path}}
    end
  end

  # -- identity -------------------------------------------------------------

  defp finalize(b) do
    Map.merge(b, %{
      architecture_identity: Digest.sha256(arch_lines(b)),
      binding_identity: Digest.sha256(lines(b))
    })
  end

  defp arch_lines(b) do
    "contract.iri=#{b.contract.iri}\n" <>
      "contract.digest=#{b.contract.digest}\n" <>
      "abb.iri=#{b.abb.iri}\n" <>
      "abb.digest=#{b.abb.digest}\n" <>
      "origin.iri=#{b.origin.iri}\n" <>
      "origin.digest=#{b.origin.digest}\n"
  end

  defp lines(b) do
    arch_lines(b) <>
      "sbb.iri=#{b.sbb.iri}\n" <>
      "sbb.digest=#{b.sbb.digest}\n" <>
      "sbb.qualification=#{b.sbb.qualification}\n" <>
      "ceiling=#{b.ceiling}\n" <>
      "provenance=#{b.provenance}\n"
  end

  defp parse_lock(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, &put_lock_line/2)
  end

  # A duplicated key is itself a mismatch: record a sentinel no real
  # rendering can equal.
  defp put_lock_line(line, acc) do
    case String.split(line, "=", parts: 2) do
      [k, v] -> Map.update(acc, k, v, fn _ -> :duplicate end)
      [k] -> Map.put(acc, k, :malformed)
    end
  end

  defp same_architecture(old, new) do
    if old.architecture_identity == new.architecture_identity,
      do: :ok,
      else: {:error, {:architecture_identity_changed, new.architecture_identity}}
  end

  defp no_widening(old, new) do
    if @ceiling_rank[new] <= @ceiling_rank[old],
      do: :ok,
      else: {:error, {:authority_widening, new}}
  end

  defp changed_sbb(old, new) do
    if old.sbb.digest == new.sbb.digest and old.sbb.iri == new.sbb.iri,
      do: {:error, :substitution_noop},
      else: :ok
  end

  defp receipt(old, new) do
    body = %{
      "context" => @receipt_context,
      "architectureIdentity" => new.architecture_identity,
      "from" => old.binding_identity,
      "to" => new.binding_identity,
      "fromSbb" => old.sbb.digest,
      "toSbb" => new.sbb.digest,
      "abb" => new.abb.iri
    }

    Map.put(body, "receiptDigest", receipt_digest(body))
  end

  defp receipt_digest(body) do
    body
    |> Enum.sort()
    |> Enum.map_join(fn {k, v} -> "#{k}=#{inspect(v)}\n" end)
    |> Digest.sha256()
  end
end
