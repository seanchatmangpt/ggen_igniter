defmodule GgenIgniter.DoctrineAdmission.Provenance do
  @moduledoc "Canonical strategic-doctrine provenance boundary."
  alias GgenIgniter.DoctrineAdmission.SourceIdentity

  def admit(value) do
    with {:ok, admitted} <- SourceIdentity.admit(value) do
      {:ok, Map.put(admitted, "boundary", "provenance")}
    end
  end
end
