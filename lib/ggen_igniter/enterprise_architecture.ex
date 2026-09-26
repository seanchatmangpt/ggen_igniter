defmodule GgenIgniter.EnterpriseArchitecture do
  @moduledoc """
  Pure admission kernel for RFC v26.9.26 enterprise-architecture ignition.

  The kernel binds an exact ABB, ArchitectureContract, qualified SBB and
  origin authority before project generation. It never grants consequential
  authority: generated metadata records an authority ceiling, while the
  generated project's own authority remains `:none`.
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

  @type refusal ::
          {:refused,
           :missing_field
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

  @spec migrate(map(), map()) :: {:ok, map()} | {:error, refusal()}
  def migrate(current, replacement) when is_map(current) and is_map(replacement) do
    with {:ok, old} <- admit(current),
         {:ok, new} <- admit(replacement),
         :ok <- same_architecture(old, new) do
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
         true <- requested_level <= @levels.construct ||
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
