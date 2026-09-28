defmodule GgenIgniter.DoctrineAdmission.TypedRefusal do
  @moduledoc "Normalizes doctrine failures into stable refusal records."

  def normalize({:refused_doctrine, boundary, reason}),
    do: %{status: :refused, boundary: boundary, reason: reason, retry: false}

  def normalize(reason),
    do: %{status: :refused, boundary: :unknown, reason: reason, retry: false}
end
