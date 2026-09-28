defmodule GgenIgniter.DoctrineAdmission.TypedRefusalTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.TypedRefusal

  test "normalizes refusal without inventing a retry" do
    refusal = TypedRefusal.normalize({:refused_doctrine, :replay, :subject_mismatch})
    assert refusal == %{status: :refused, boundary: :replay, reason: :subject_mismatch, retry: false}
  end
end
