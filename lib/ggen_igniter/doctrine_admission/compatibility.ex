defmodule GgenIgniter.DoctrineAdmission.Compatibility do
  @moduledoc "Fail-closed compatibility gate for doctrine-admission representations."

  @supported ["doctrine-admission/v1"]

  def admit(%{"schema_version" => version} = artifact) when version in @supported,
    do: {:ok, artifact}

  def admit(%{"schema_version" => version}),
    do: {:error, {:refused_doctrine, :compatibility, {:unsupported_version, version}}}

  def admit(_), do: {:error, {:refused_doctrine, :compatibility, :missing_version}}
end
