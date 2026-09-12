defmodule GgenIgniter.EDS.ClaimTest do
  @moduledoc """
  Chicago-style: real `Claim.execute/2`/`verify/1` state transitions and a
  real `GgenIgniter.EDS.Receipt` (real sha256 fingerprint) are produced and
  asserted on directly; no mock of the claim lifecycle.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.EDS.{Claim, Falsifier}

  defp minimal_falsifier do
    Falsifier.new("positive", "the value is not positive", fn v ->
      if v > 0, do: {:survived, v}, else: {:falsified, v}
    end)
  end

  test "new/1 refuses an ERC with no falsifier -- a demonstration is not an executable research claim" do
    assert_raise ArgumentError, ~r/demonstration, not an executable research claim/, fn ->
      Claim.new(%{
        hypothesis: "1 > 0",
        artifact: 1,
        protocol: "identity",
        identity: %{},
        verifier: fn _e, _v -> {:verified, %{}} end
      })
    end
  end

  test "verify/1 refuses a claim that has not been executed -- no evidence to check" do
    claim =
      Claim.new(%{
        hypothesis: "1 > 0",
        artifact: 1,
        falsifiers: [minimal_falsifier()],
        protocol: "identity",
        identity: %{},
        verifier: fn _e, _v -> {:verified, %{}} end
      })

    assert_raise ArgumentError, ~r/call execute\/2 first/, fn -> Claim.verify(claim) end
  end

  test "a real end-to-end claim: proposed -> observed -> verified, with a real receipt" do
    claim =
      Claim.new(%{
        hypothesis: "the identity function on a positive integer returns a positive integer",
        artifact: 42,
        falsifiers: [minimal_falsifier()],
        protocol: "apply identity/1 to the artifact",
        identity: %{source: "inline test", environment: %{}, inputs: %{}},
        verifier: fn _evidence, verdicts ->
          if Falsifier.all_survived?(verdicts), do: {:verified, %{}}, else: {:falsified, %{}}
        end
      })

    assert claim.state == :proposed

    claim = Claim.execute(claim, fn n -> n end)
    assert claim.state == :observed
    assert claim.evidence == 42

    claim = Claim.verify(claim)
    assert claim.state == :verified
    assert claim.receipt.state == :verified
    assert claim.receipt.fingerprint =~ ~r/^[0-9a-f]{64}$/
  end

  test "a real falsified claim: a falsifier that genuinely fails drives the claim to :falsified, not silently to :verified" do
    always_fails = Falsifier.new("impossible", "1 equals 2", fn _ -> {:falsified, "1 != 2"} end)

    claim =
      Claim.new(%{
        hypothesis: "1 equals 2",
        artifact: 1,
        falsifiers: [always_fails],
        protocol: "compare to 2",
        identity: %{},
        verifier: fn _evidence, verdicts ->
          if Falsifier.all_survived?(verdicts), do: {:verified, %{}}, else: {:falsified, %{}}
        end
      })

    claim = claim |> Claim.execute(& &1) |> Claim.verify()

    assert claim.state == :falsified
    assert claim.receipt.state == :falsified
    refute Falsifier.all_survived?(claim.receipt.falsifier_verdicts)
  end
end
