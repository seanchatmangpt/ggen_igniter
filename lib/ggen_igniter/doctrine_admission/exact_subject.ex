defmodule GgenIgniter.DoctrineAdmission.ExactSubject do
  @moduledoc "Exact strategic-doctrine subject boundary."
  alias GgenIgniter.DoctrineAdmission.SourceIdentity

  def admit(value), do: SourceIdentity.admit(value)
end
