defmodule GgenIgniter.DoctrineAdmission.Recovery do
  @moduledoc "Routes a refusal to a lawful adjacent repair edge; never bypasses the failed guard."

  def route(%{boundary: :replay}), do: {:repair, :rebind_exact_subject}
  def route(%{boundary: :compatibility}), do: {:repair, :migrate_representation}
  def route(%{boundary: :evidence}), do: {:repair, :supply_bounded_evidence}
  def route(%{boundary: :origin_authority}), do: {:repair, :resolve_canonical_origin}
  def route(%{status: :refused}), do: {:repair, :reconstruct_candidate}
  def route(_), do: {:stop, :not_a_refusal}
end
