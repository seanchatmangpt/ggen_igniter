defmodule GgenIgniter.EDS.ReceiptTest do
  @moduledoc """
  Chicago-style: exercises the real `:crypto.hash/2` sha256 fingerprint and
  real `Jason.encode!/2` canonicalization, asserting on the real resulting
  fingerprint string, not a call-was-made check.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.EDS.Receipt

  defp base_fields(overrides \\ %{}) do
    Map.merge(
      %{
        hypothesis: "2 + 2 == 4",
        artifact_identity: "arithmetic",
        source_identity: "sha256:abc123",
        environment: %{erlang: "28.3.1"},
        inputs: %{a: 2, b: 2},
        execution: %{fn: "Kernel.+/2"},
        outputs: %{result: 4},
        falsifier_verdicts: [{"sum is 4", {:survived, 4}}],
        state: :verified
      },
      overrides
    )
  end

  test "new!/1 rejects an invalid state" do
    assert_raise ArgumentError, ~r/invalid EDS evidence state/, fn ->
      Receipt.new!(base_fields(%{state: :done}))
    end
  end

  test "new!/1 computes a real 64-hex-char sha256 fingerprint" do
    receipt = Receipt.new!(base_fields())
    assert receipt.fingerprint =~ ~r/^[0-9a-f]{64}$/
  end

  test "fingerprint is identical for two receipts built from identical fields" do
    r1 = Receipt.new!(base_fields())
    r2 = Receipt.new!(base_fields())
    assert r1.fingerprint == r2.fingerprint
  end

  test "fingerprint changes when any single field changes -- real content-addressed identity" do
    baseline = Receipt.new!(base_fields())
    changed_output = Receipt.new!(base_fields(%{outputs: %{result: 5}}))
    changed_state = Receipt.new!(base_fields(%{state: :falsified}))

    changed_verdict =
      Receipt.new!(base_fields(%{falsifier_verdicts: [{"sum is 4", {:falsified, 5}}]}))

    refute baseline.fingerprint == changed_output.fingerprint
    refute baseline.fingerprint == changed_state.fingerprint
    refute baseline.fingerprint == changed_verdict.fingerprint
  end

  test "summary/1 names the real state and falsifier survival, not a hardcoded string" do
    verified = Receipt.new!(base_fields())
    assert summary = Receipt.summary(verified)
    assert summary =~ "state=verified"
    assert summary =~ "survived=true"

    falsified =
      Receipt.new!(
        base_fields(%{state: :falsified, falsifier_verdicts: [{"x", {:falsified, "y"}}]})
      )

    assert Receipt.summary(falsified) =~ "state=falsified"
    assert Receipt.summary(falsified) =~ "survived=false"
  end
end
