defmodule GgenIgniter.DoctrineAdmission.CandidateAdmission do
  @moduledoc "Strategic-doctrine candidate admission bound to the canonical source."
  alias GgenIgniter.DoctrineAdmission.SourceIdentity

  def admit(value) do
    with {:ok, admitted} <- SourceIdentity.admit(value) do
      {:ok, Map.put(admitted, "boundary", "candidate_admission")}
    end
  end
end
