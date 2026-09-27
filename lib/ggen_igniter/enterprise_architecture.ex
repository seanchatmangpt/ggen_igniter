defmodule GgenIgniter.EnterpriseArchitecture do
  @moduledoc """
  Pure admission kernel for RFC v26.9.26 enterprise-architecture ignition.

  The kernel binds an exact ABB, ArchitectureContract, qualified SBB and
  origin authority before project generation. It never grants consequential
  authority: generated metadata records an authority ceiling, while the
  generated project's own authority remains `:none`.

  Hardening (v26.9.26, `test/ggen_igniter/enterprise_architecture_hardening_test.exs`):
  a non-map input is a typed refusal (`:input_not_map`), every digest field
  must be `sha256:<64 lowercase hex>` (`{:invalid_digest, field}`), keys
  outside the admitted schema are refused (`{:unknown_field, key}`) so no
  caller key rides through admission, substituting an SBB with itself is
  refused (`:substitution_noop`), and `verify_receipt/1` recomputes a
  scaffold or migration receipt's digest (`:receipt_digest_mismatch`).
  """

  alias GgenIgniter.Digest

  @levels %{none: 0, observe: 1, select: 2, construct: 3, do: 4}
  @required [
    :abb_digest,
    :contract_digest,
    :sbb_digest,
    :qualification_digest,
    :origin_authority,
    :standing,
    :mutable,
    :requested_authority
  ]

  @digest_fields [:abb_digest, :contract_digest, :sbb_digest, :qualification_digest]
  @digest_re ~r/\Asha256:[0-9a-f]{64}\z/

  @type refusal ::
          {:refused,
           :input_not_map
           | :substitution_noop
           | :receipt_digest_mismatch
           | {:missing_field, atom()}
           | {:unknown_field, term()}
           | {:invalid_digest, atom()}
           | :missing_field
           | :unknown_standing
           | :unqualified_sbb
           | :mutable_subject
           | :invalid_authority
           | :authority_widening
           | :do_authority_forbidden
           | :abb_mismatch}

  @spec admit(map()) :: {:ok, map()} | {:error, refusal()}
  def admit(input) when is_map(input) do
    with :ok <- require_fields(input),
         :ok <- no_unknown_fields(input),
         :ok <- require_digests(input),
         :ok <- require_qualified(input),
         :ok <- require_immutable(input),
         :ok <- require_authority(input) do
      {:ok,
       Map.merge(input, %{
         architecture_id: architecture_id(input),
         generated_authority: :none,
         brce_required_for_do: true
       })}
    end
  end

  def admit(_), do: {:error, {:refused, :input_not_map}}

  @spec scaffold(map()) :: {:ok, map()} | {:error, refusal()}
  def scaffold(input) when is_map(input) do
    with {:ok, admitted} <- admit(input) do
      body = %{
        schema: "ggen-igniter.ea-bootstrap.v1",
        architecture_id: admitted.architecture_id,
        abb_digest: admitted.abb_digest,
        contract_digest: admitted.contract_digest,
        sbb_digest: admitted.sbb_digest,
        qualification_digest: admitted.qualification_digest,
        origin_authority: admitted.origin_authority,
        authority_ceiling: admitted.requested_authority,
        generated_authority: :none,
        brce_required_for_do: true
      }

      {:ok, Map.put(body, :receipt_digest, digest(body))}
    end
  end

  def scaffold(_), do: {:error, {:refused, :input_not_map}}

  @spec migrate(map(), map()) :: {:ok, map()} | {:error, refusal()}
  def migrate(current, replacement) when is_map(current) and is_map(replacement) do
    with {:ok, old} <- admit(current),
         {:ok, new} <- admit(replacement),
         :ok <- same_architecture(old, new),
         :ok <- changed_sbb(old, new) do
      body = %{
        schema: "ggen-igniter.ea-migration.v1",
        architecture_id: old.architecture_id,
        abb_digest: old.abb_digest,
        contract_digest: old.contract_digest,
        from_sbb_digest: old.sbb_digest,
        to_sbb_digest: new.sbb_digest,
        from_qualification_digest: old.qualification_digest,
        to_qualification_digest: new.qualification_digest,
        authority_ceiling: min_authority(old.requested_authority, new.requested_authority),
        generated_authority: :none,
        brce_required_for_do: true
      }

      {:ok, Map.put(body, :receipt_digest, digest(body))}
    end
  end

  def migrate(_, _), do: {:error, {:refused, :input_not_map}}

  @doc """
  Recompute a scaffold or migration receipt: the digest over every field
  except `:receipt_digest` must equal the recorded `:receipt_digest`.
  """
  @spec verify_receipt(map()) :: :ok | {:error, refusal()}
  def verify_receipt(%{receipt_digest: recorded} = receipt) do
    if digest(Map.delete(receipt, :receipt_digest)) == recorded,
      do: :ok,
      else: {:error, {:refused, :receipt_digest_mismatch}}
  end

  def verify_receipt(_), do: {:error, {:refused, :receipt_digest_mismatch}}

  @spec architecture_id(map()) :: String.t()
  def architecture_id(input) do
    digest({Map.get(input, :abb_digest), Map.get(input, :contract_digest)})
  end

  defp require_fields(input) do
    case Enum.find(@required, &(not Map.has_key?(input, &1))) do
      nil -> :ok
      field -> {:error, {:refused, {:missing_field, field}}}
    end
  end

  defp no_unknown_fields(input) do
    case input |> Map.keys() |> Enum.find(&(&1 not in @required)) do
      nil -> :ok
      key -> {:error, {:refused, {:unknown_field, key}}}
    end
  end

  defp require_digests(input) do
    case Enum.find(@digest_fields, &(not digest?(Map.get(input, &1)))) do
      nil -> :ok
      field -> {:error, {:refused, {:invalid_digest, field}}}
    end
  end

  defp digest?(v) when is_binary(v), do: Regex.match?(@digest_re, v)
  defp digest?(_), do: false

  defp changed_sbb(%{sbb_digest: sbb, qualification_digest: q}, %{
         sbb_digest: sbb,
         qualification_digest: q
       }),
       do: {:error, {:refused, :substitution_noop}}

  defp changed_sbb(_, _), do: :ok

  defp require_qualified(%{standing: :unknown}), do: {:error, {:refused, :unknown_standing}}
  defp require_qualified(%{standing: :qualified}), do: :ok
  defp require_qualified(_), do: {:error, {:refused, :unqualified_sbb}}

  defp require_immutable(%{mutable: false}), do: :ok
  defp require_immutable(_), do: {:error, {:refused, :mutable_subject}}

  defp require_authority(%{origin_authority: origin, requested_authority: requested}) do
    with {:ok, origin_level} <- authority_level(origin),
         {:ok, requested_level} <- authority_level(requested),
         true <- requested != :do || {:error, {:refused, :do_authority_forbidden}},
         true <- requested_level <= origin_level || {:error, {:refused, :authority_widening}},
         true <-
           requested_level <= @levels.construct ||
             {:error, {:refused, :do_authority_forbidden}} do
      :ok
    end
  end

  defp authority_level(authority) do
    case Map.fetch(@levels, authority) do
      {:ok, level} -> {:ok, level}
      :error -> {:error, {:refused, :invalid_authority}}
    end
  end

  defp same_architecture(%{abb_digest: abb, contract_digest: contract}, %{
         abb_digest: abb,
         contract_digest: contract
       }),
       do: :ok

  defp same_architecture(_, _), do: {:error, {:refused, :abb_mismatch}}

  defp min_authority(left, right) do
    if @levels[left] <= @levels[right], do: left, else: right
  end

  defp digest(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> Digest.sha256()
  end
end
