defmodule GgenIgniter.DoctrineAdmission.OriginAuthority do
  @moduledoc "Checks that doctrine origin authority is an explicit absolute IRI."

  def admit(origin) when is_binary(origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _ -> {:error, {:refused_doctrine, :origin_authority, :invalid_iri}}
    end
  end

  def admit(_), do: {:error, {:refused_doctrine, :origin_authority, :invalid_iri}}
end
