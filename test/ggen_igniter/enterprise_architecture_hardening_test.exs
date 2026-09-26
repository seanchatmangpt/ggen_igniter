defmodule GgenIgniter.EnterpriseArchitectureHardeningTest do
  @moduledoc """
  Adversarial falsifiers for `GgenIgniter.EnterpriseArchitecture` (the
  cloud-session kernel landed on the PR branch at cb9497b4). Chicago-style:
  the real module, real digests, assertions on returned values only.

  Each test names the defect class it guards: malformed input, wrong digest,
  unauthorized action smuggled through an unknown key, no-op substitution
  (duplicate delivery of the same SBB) and receipt tamper detection.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Digest
  alias GgenIgniter.EnterpriseArchitecture, as: EA

  defp input(overrides \\ %{}) do
    Map.merge(
      %{
        abb_digest: Digest.sha256("abb"),
        contract_digest: Digest.sha256("contract"),
        sbb_digest: Digest.sha256("sbb-a"),
        qualification_digest: Digest.sha256("qualification-a"),
        origin_authority: :construct,
        requested_authority: :construct,
        standing: :qualified,
        mutable: false
      },
      overrides
    )
  end

  defp replacement,
    do:
      input(%{
        sbb_digest: Digest.sha256("sbb-b"),
        qualification_digest: Digest.sha256("qualification-b")
      })

  test "malformed input: a non-map is a typed refusal, not a crash" do
    for v <- [nil, "input", [abb_digest: "x"], 42] do
      assert EA.admit(v) == {:error, {:refused, :input_not_map}}
      assert EA.scaffold(v) == {:error, {:refused, :input_not_map}}
    end

    assert EA.migrate(nil, input()) == {:error, {:refused, :input_not_map}}
  end

  test "wrong digest: every digest field must be sha256:<64 lowercase hex>" do
    bad = [
      "sha256:abb",
      "sha256:" <> String.duplicate("A", 64),
      "sha256:" <> String.duplicate("a", 63),
      String.duplicate("a", 64),
      nil,
      :sha256
    ]

    for field <- [:abb_digest, :contract_digest, :sbb_digest, :qualification_digest],
        v <- bad do
      assert EA.admit(input(%{field => v})) == {:error, {:refused, {:invalid_digest, field}}},
             "#{field}=#{inspect(v)} admitted"
    end
  end

  test "unauthorized action: an unknown key cannot ride through admission" do
    assert EA.admit(Map.put(input(), :grant, :do)) ==
             {:error, {:refused, {:unknown_field, :grant}}}

    assert EA.admit(Map.put(input(), :generated_authority, :do)) ==
             {:error, {:refused, {:unknown_field, :generated_authority}}}

    assert EA.admit(Map.put(input(), "requested_authority", :do)) ==
             {:error, {:refused, {:unknown_field, "requested_authority"}}}
  end

  test "admitted map exposes no authority beyond :none" do
    assert {:ok, admitted} = EA.admit(input())
    assert admitted.generated_authority == :none
    assert admitted.brce_required_for_do
  end

  test "duplicate delivery: substituting an SBB with itself is refused" do
    assert EA.migrate(input(), input()) == {:error, {:refused, :substitution_noop}}
  end

  test "substitution may not widen the ceiling beyond the current binding" do
    current = input(%{origin_authority: :construct, requested_authority: :select})
    widened = Map.put(replacement(), :requested_authority, :construct)
    assert {:ok, receipt} = EA.migrate(current, widened)
    assert receipt.authority_ceiling == :select
  end

  test "stale subject: a receipt is bound to its exact from/to SBB digests" do
    {:ok, ab} = EA.migrate(input(), replacement())

    c =
      input(%{
        sbb_digest: Digest.sha256("sbb-c"),
        qualification_digest: Digest.sha256("qualification-c")
      })

    {:ok, bc} = EA.migrate(replacement(), c)
    assert ab.to_sbb_digest == bc.from_sbb_digest
    assert ab.receipt_digest != bc.receipt_digest
    assert ab.architecture_id == bc.architecture_id
  end

  test "replay mismatch: recomputing a tampered receipt body gives a different digest" do
    {:ok, receipt} = EA.migrate(input(), replacement())
    assert EA.verify_receipt(receipt) == :ok

    tampered = %{receipt | to_sbb_digest: Digest.sha256("sbb-evil")}
    assert EA.verify_receipt(tampered) == {:error, {:refused, :receipt_digest_mismatch}}

    widened = %{receipt | authority_ceiling: :do}
    assert EA.verify_receipt(widened) == {:error, {:refused, :receipt_digest_mismatch}}

    assert EA.verify_receipt(Map.delete(receipt, :receipt_digest)) ==
             {:error, {:refused, :receipt_digest_mismatch}}

    {:ok, scaffold} = EA.scaffold(input())
    assert EA.verify_receipt(scaffold) == :ok

    assert EA.verify_receipt(%{scaffold | generated_authority: :do}) ==
             {:error, {:refused, :receipt_digest_mismatch}}
  end

  # Bounds ~30x the M3 Max medians in receipts/v26.9.26/ea-ignition-bench.json
  # (admit 6.8us, scaffold 15.3us, migrate 24.2us, verify_receipt 2.7us).
  # Median of 5 rounds of 2000 calls.
  test "benchmark regression bound" do
    {:ok, receipt} = EA.migrate(input(), replacement())

    bounds = [
      {"admit", 250, fn -> EA.admit(input()) end},
      {"scaffold", 500, fn -> EA.scaffold(input()) end},
      {"migrate", 750, fn -> EA.migrate(input(), replacement()) end},
      {"verify_receipt", 100, fn -> EA.verify_receipt(receipt) end}
    ]

    for {name, bound, f} <- bounds do
      Enum.each(1..200, fn _ -> f.() end)
      rounds = for _ <- 1..5, do: round_us(2_000, f)
      m = rounds |> Enum.sort() |> Enum.at(2)
      assert m < bound, "#{name} median #{m}us exceeds bound #{bound}us"
    end
  end

  defp round_us(n, f) do
    {us, _} = :timer.tc(fn -> Enum.each(1..n, fn _ -> f.() end) end)
    us / n
  end
end
