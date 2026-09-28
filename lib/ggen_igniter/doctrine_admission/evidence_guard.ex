defmodule GgenIgniter.DoctrineAdmission.EvidenceGuard do
  @moduledoc "Enforces candidate != standing != authority and CONSTRUCT as the actuation ceiling."

  @allowed ~w(SPECIFIED IMPLEMENTED_UNVERIFIED EXECUTED_VERIFIED LOCAL_RUN repository-local CONSTRUCT)

  def admit(candidate) when is_map(candidate) do
    standing = Map.get(candidate, "standing", "UNKNOWN")
    authority = Map.get(candidate, "authority_requirement", "NONE")
    ceiling = Map.get(candidate, "evidence_ceiling", "CONSTRUCT")

    cond do
      standing != "UNKNOWN" -> {:error, {:refused_doctrine, :evidence, {:literal_standing, standing}}}
      authority != "NONE" -> {:error, {:refused_doctrine, :evidence, {:authority, authority}}}
      ceiling not in @allowed -> {:error, {:refused_doctrine, :evidence, {:ceiling, ceiling}}}
      true -> {:ok, candidate}
    end
  end

  def admit(_), do: {:error, {:refused_doctrine, :evidence, :invalid_shape}}
end
