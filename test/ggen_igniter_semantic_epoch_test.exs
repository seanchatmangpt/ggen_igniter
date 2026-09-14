defmodule GgenIgniter.SemanticEpochTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticEpoch

  test "v26.9.14 admits only the exact constitutional invariants" do
    declaration = SemanticEpoch.invariants(:constitutional)

    assert {:ok, admitted} = SemanticEpoch.admit(:constitutional, declaration)
    assert admitted.version == "26.9.14"
    assert admitted.epoch == :constitutional
  end

  test "v26.9.15 makes projection readability and persistence non-requirements" do
    declaration = SemanticEpoch.invariants(:ephemeral)

    assert declaration.human_readable_projection_required == false
    assert declaration.persistent_projection_required == false
    assert declaration.projection_disposition == :ephemeral
    assert declaration.handwritten_generated_edits == :refused
    assert declaration.generator_authority_ceiling == :construct
    assert declaration.consequence_do_authority == :external
  end

  test "required invariants fail closed" do
    declaration =
      SemanticEpoch.invariants(:ephemeral)
      |> Map.put(:generator_authority_ceiling, :do)

    assert {:error, {:refused_epoch_invariant, mismatches}} =
             SemanticEpoch.admit(:ephemeral, declaration)

    assert mismatches.generator_authority_ceiling == %{expected: :construct, observed: :do}
  end
end
