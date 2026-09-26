defmodule GgenIgniter.EnterpriseArchitectureTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.EnterpriseArchitecture, as: EA

  defp input(overrides \\ %{}) do
    Map.merge(
      %{
        abb_digest: "sha256:abb",
        contract_digest: "sha256:contract",
        sbb_digest: "sha256:sbb-a",
        qualification_digest: "sha256:qualification-a",
        origin_authority: :construct,
        requested_authority: :construct,
        standing: :qualified,
        mutable: false
      },
      overrides
    )
  end

  test "scaffolding is deterministic and never manufactures authority" do
    assert {:ok, first} = EA.scaffold(input())
    assert {:ok, second} = EA.scaffold(input())
    assert first == second
    assert first.generated_authority == :none
    assert first.brce_required_for_do
  end

  test "UNKNOWN, mutable subjects and authority widening fail closed" do
    assert {:error, {:refused, :unknown_standing}} = EA.admit(input(%{standing: :unknown}))
    assert {:error, {:refused, :mutable_subject}} = EA.admit(input(%{mutable: true}))

    assert {:error, {:refused, :authority_widening}} =
             EA.admit(input(%{origin_authority: :select, requested_authority: :construct}))

    assert {:error, {:refused, :do_authority_forbidden}} =
             EA.admit(input(%{origin_authority: :do, requested_authority: :do}))
  end

  test "substituting SBBs preserves architecture identity and emits a deterministic receipt" do
    replacement =
      input(%{
        sbb_digest: "sha256:sbb-b",
        qualification_digest: "sha256:qualification-b"
      })

    assert {:ok, one} = EA.migrate(input(), replacement)
    assert {:ok, two} = EA.migrate(input(), replacement)
    assert one == two
    assert one.architecture_id == EA.architecture_id(input())
    assert one.from_sbb_digest != one.to_sbb_digest
    assert one.generated_authority == :none
  end

  test "cross-ABB substitution is refused" do
    replacement = input(%{abb_digest: "sha256:other-abb"})
    assert {:error, {:refused, :abb_mismatch}} = EA.migrate(input(), replacement)
  end
end
