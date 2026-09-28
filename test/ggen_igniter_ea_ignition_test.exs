defmodule GgenIgniter.EA.IgnitionTest do
  @moduledoc """
  Chicago-style: real `GgenIgniter.EA.Ignition` over real input maps, real
  SHA-256 digests; assertions on returned state only.

  Covers RFC v26.9.26 abb-sbb-implementation DoD 1/3/4/5/6/8: positive and
  negative fixtures, a substitute SBB satisfying the same ABB, and the
  adversarial classes malformed input, wrong digest, stale subject,
  unauthorized action (authority widening), replay mismatch, duplicate
  delivery and reordering.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Digest
  alias GgenIgniter.EA.Ignition

  defp d(s), do: Digest.sha256(s)

  defp input(overrides \\ %{}) do
    base = %{
      "architectureContract" => %{"iri" => "urn:ea:contract:payments", "digest" => d("contract")},
      "abb" => %{"iri" => "urn:ea:abb:message-broker", "digest" => d("abb")},
      "sbb" => %{
        "iri" => "urn:ea:sbb:rabbitmq",
        "digest" => d("sbb-rabbitmq"),
        "realizes" => "urn:ea:abb:message-broker",
        "standing" => "ALIVE",
        "qualification" => %{"digest" => d("qual-rabbitmq"), "mutable" => false}
      },
      "originAuthority" => %{"iri" => "urn:ea:authority:arb", "digest" => d("arb")},
      "authorityCeiling" => "CONSTRUCT",
      "provenance" => %{"digest" => d("prov")}
    }

    deep_merge(base, overrides)
  end

  defp deep_merge(a, b) do
    Map.merge(a, b, fn
      _k, x, y when is_map(x) and is_map(y) -> deep_merge(x, y)
      _k, _x, y -> y
    end)
  end

  defp kafka_sbb do
    %{
      "sbb" => %{
        "iri" => "urn:ea:sbb:kafka",
        "digest" => d("sbb-kafka"),
        "qualification" => %{"digest" => d("qual-kafka"), "mutable" => false}
      }
    }
  end

  describe "admit/1 positive" do
    test "admits a complete input and binds exact digests" do
      assert {:ok, b} = Ignition.admit(input())
      assert b.origin == %{iri: "urn:ea:authority:arb", digest: d("arb")}
      assert b.sbb.qualification == d("qual-rabbitmq")
      assert b.ceiling == "CONSTRUCT"
      assert b.binding_identity =~ ~r/\Asha256:[0-9a-f]{64}\z/
      assert b.architecture_identity != b.binding_identity
    end

    test "is deterministic: map ordering does not change identity" do
      {:ok, a} = Ignition.admit(input())
      reordered = input() |> Enum.reverse() |> Map.new()
      {:ok, b} = Ignition.admit(reordered)
      assert a == b
    end

    test "SELECT ceiling is admitted (narrower than CONSTRUCT)" do
      assert {:ok, %{ceiling: "SELECT"}} =
               Ignition.admit(input(%{"authorityCeiling" => "SELECT"}))
    end
  end

  describe "admit/1 negative (DoD 4)" do
    test "non-map input" do
      assert Ignition.admit(nil) == {:error, :input_not_map}
      assert Ignition.admit("{}") == {:error, :input_not_map}
      assert Ignition.admit([]) == {:error, :input_not_map}
    end

    test "missing originAuthority is refused, never self-declared" do
      assert Ignition.admit(Map.delete(input(), "originAuthority")) ==
               {:error, :origin_authority_missing}

      assert Ignition.admit(%{input() | "originAuthority" => %{}}) ==
               {:error, :origin_authority_missing}
    end

    test "origin authority without digest is refused" do
      i = put_in(input(), ["originAuthority"], %{"iri" => "urn:ea:authority:arb"})
      assert Ignition.admit(i) == {:error, {:missing_field, "originAuthority.digest"}}
    end

    test "UNKNOWN and every non-ALIVE standing is refused" do
      for s <- ["UNKNOWN", "PARTIAL_ALIVE", "BLOCKED", "alive", nil, 1] do
        i = put_in(input(), ["sbb", "standing"], s)
        assert Ignition.admit(i) == {:error, {:standing_not_admitted, s}}
      end

      i = update_in(input(), ["sbb"], &Map.delete(&1, "standing"))
      assert Ignition.admit(i) == {:error, {:missing_field, "sbb.standing"}}
    end

    test "mutable qualification is refused" do
      for q <- [
            %{"digest" => d("q"), "mutable" => true},
            %{"digest" => d("q")},
            %{"digest" => d("q"), "mutable" => "false"},
            %{"digest" => d("q"), "mutable" => false, "ref" => "main"},
            %{"digest" => d("q"), "mutable" => false, "branch" => "main"},
            %{"digest" => d("q"), "mutable" => false, "latest" => true},
            %{"digest" => d("q"), "mutable" => false, "tag" => "v1"}
          ] do
        i = put_in(input(), ["sbb", "qualification"], q)
        assert {:error, {:qualification_mutable, _}} = Ignition.admit(i)
      end
    end

    test "authority widening (DO or unknown ceiling) is refused" do
      for c <- ["DO", "do", "ADMIN", "", nil, :CONSTRUCT] do
        assert Ignition.admit(%{input() | "authorityCeiling" => c}) ==
                 {:error, {:authority_widening, c}}
      end
    end

    test "unknown top-level key cannot smuggle an authority grant" do
      assert Ignition.admit(Map.put(input(), "grant", "DO")) ==
               {:error, {:unknown_field, "grant"}}

      assert Ignition.admit(Map.put(input(), :authorityCeiling, "DO")) ==
               {:error, {:unknown_field, "authorityCeiling"}}
    end

    test "SBB realizing a different ABB is refused (DoD 8 negative fixture)" do
      i = put_in(input(), ["sbb", "realizes"], "urn:ea:abb:object-store")

      assert Ignition.admit(i) ==
               {:error,
                {:sbb_does_not_realize_abb, "urn:ea:abb:object-store",
                 "urn:ea:abb:message-broker"}}
    end

    test "wrong or malformed digests are refused" do
      bad = [
        "sha256:" <> String.duplicate("A", 64),
        "sha256:" <> String.duplicate("a", 63),
        "sha256:" <> String.duplicate("a", 65),
        "sha1:" <> String.duplicate("a", 40),
        String.duplicate("a", 64),
        "sha256:" <> String.duplicate("a", 64) <> "\n",
        123
      ]

      for v <- bad do
        assert Ignition.admit(put_in(input(), ["abb", "digest"], v)) ==
                 {:error, {:digest_invalid, "abb.digest"}}

        assert Ignition.admit(put_in(input(), ["provenance", "digest"], v)) ==
                 {:error, {:digest_invalid, "provenance.digest"}}
      end
    end

    test "IRIs that could forge a canonical line are refused" do
      for v <- ["", "not an iri", "urn:x\nsbb.iri=urn:evil", "urn:a=b", "urn:x ", 5] do
        assert Ignition.admit(put_in(input(), ["architectureContract", "iri"], v)) ==
                 {:error, {:field_invalid, "architectureContract.iri"}}
      end
    end

    test "non-map sections are refused" do
      assert Ignition.admit(%{input() | "sbb" => "urn:ea:sbb:rabbitmq"}) ==
               {:error, {:field_invalid, "sbb"}}

      assert Ignition.admit(%{input() | "provenance" => d("prov")}) ==
               {:error, {:field_invalid, "provenance"}}
    end

    test "every single-field deletion is refused (no vacuous field)" do
      paths = [
        ["architectureContract"],
        ["architectureContract", "iri"],
        ["architectureContract", "digest"],
        ["abb"],
        ["abb", "iri"],
        ["abb", "digest"],
        ["sbb"],
        ["sbb", "iri"],
        ["sbb", "digest"],
        ["sbb", "realizes"],
        ["sbb", "standing"],
        ["sbb", "qualification"],
        ["sbb", "qualification", "digest"],
        ["authorityCeiling"],
        ["provenance"],
        ["provenance", "digest"]
      ]

      for path <- paths do
        {_, i} = pop_in(input(), path)
        assert {:error, _} = Ignition.admit(i), "deleting #{inspect(path)} was admitted"
      end
    end
  end

  describe "identity sensitivity (mutation-found guard)" do
    # Found by mutation: dropping `sbb.iri` from the canonical encoding
    # survived every other test. Every bound field must move
    # binding_identity; only contract/ABB/origin may move
    # architecture_identity.
    test "every bound field moves binding_identity; only architecture fields move architecture_identity" do
      {:ok, base} = Ignition.admit(input())

      changes = [
        {["architectureContract", "iri"], "urn:ea:contract:other", true},
        {["architectureContract", "digest"], d("c2"), true},
        {["abb", "digest"], d("abb2"), true},
        {["originAuthority", "iri"], "urn:ea:authority:other", true},
        {["originAuthority", "digest"], d("arb2"), true},
        {["sbb", "iri"], "urn:ea:sbb:other", false},
        {["sbb", "digest"], d("sbb2"), false},
        {["sbb", "qualification", "digest"], d("q2"), false},
        {["authorityCeiling"], "SELECT", false},
        {["provenance", "digest"], d("prov2"), false}
      ]

      for {path, value, arch?} <- changes do
        {:ok, b} = Ignition.admit(put_in(input(), path, value))
        assert b.binding_identity != base.binding_identity, "#{inspect(path)} not bound"
        assert Ignition.lock(b) != Ignition.lock(base)
        assert Ignition.verify_lock(Ignition.lock(base), b) != :ok

        assert b.architecture_identity != base.architecture_identity == arch?,
               "#{inspect(path)} architecture_identity sensitivity wrong"
      end

      abb_moved =
        input()
        |> put_in(["abb", "iri"], "urn:ea:abb:other")
        |> put_in(["sbb", "realizes"], "urn:ea:abb:other")

      {:ok, b} = Ignition.admit(abb_moved)
      assert b.architecture_identity != base.architecture_identity
    end
  end

  describe "lock/1 + verify_lock/2 (DoD 3)" do
    test "lock round-trips and is byte-deterministic" do
      {:ok, b} = Ignition.admit(input())
      text = Ignition.lock(b)
      assert text == Ignition.lock(elem(Ignition.admit(input()), 1))
      assert Ignition.verify_lock(text, b) == :ok
      assert text =~ "architecture_identity=#{b.architecture_identity}\n"
      assert text =~ "binding_identity=#{b.binding_identity}\n"
    end

    test "tampered, truncated, duplicated and stale locks are refused" do
      {:ok, b} = Ignition.admit(input())
      text = Ignition.lock(b)

      tampered = String.replace(text, d("sbb-rabbitmq"), d("sbb-evil"))
      assert Ignition.verify_lock(tampered, b) == {:error, {:lock_mismatch, "sbb.digest"}}

      truncated = text |> String.split("\n", trim: true) |> Enum.drop(-1) |> Enum.join("\n")
      assert Ignition.verify_lock(truncated, b) == {:error, {:lock_mismatch, "keys"}}

      assert Ignition.verify_lock(text <> "ceiling=DO\n", b) ==
               {:error, {:lock_mismatch, "ceiling"}}

      assert Ignition.verify_lock(text <> "garbage\n", b) == {:error, {:lock_mismatch, "keys"}}

      {:ok, stale} = Ignition.admit(deep_merge(input(), kafka_sbb()))
      assert {:error, {:lock_mismatch, _}} = Ignition.verify_lock(text, stale)
    end
  end

  describe "substitute/2 + apply_migration/3 (DoD 5/6/8)" do
    test "substitute SBB for the same ABB preserves architecture identity" do
      {:ok, old} = Ignition.admit(input())
      assert {:ok, new, receipt} = Ignition.substitute(old, deep_merge(input(), kafka_sbb()))
      assert new.architecture_identity == old.architecture_identity
      assert new.binding_identity != old.binding_identity
      assert receipt["from"] == old.binding_identity
      assert receipt["to"] == new.binding_identity
      assert receipt["fromSbb"] == d("sbb-rabbitmq")
      assert receipt["toSbb"] == d("sbb-kafka")
      assert {:ok, ^new} = Ignition.apply_migration(old, receipt, new)
    end

    test "migration receipt is deterministic (replay recomputes byte-equal)" do
      {:ok, old} = Ignition.admit(input())
      {:ok, _, r1} = Ignition.substitute(old, deep_merge(input(), kafka_sbb()))
      {:ok, _, r2} = Ignition.substitute(old, deep_merge(input(), kafka_sbb()))
      assert r1 == r2
    end

    test "substitution may not change contract, ABB or origin" do
      {:ok, old} = Ignition.admit(input())

      for change <- [
            %{"architectureContract" => %{"digest" => d("contract-v2")}},
            %{"originAuthority" => %{"iri" => "urn:ea:authority:self"}},
            %{
              "abb" => %{"digest" => d("abb-v2")},
              "sbb" => kafka_sbb()["sbb"]
            }
          ] do
        assert {:error, {:architecture_identity_changed, _}} =
                 Ignition.substitute(old, deep_merge(input(), change))
      end
    end

    test "substitution may narrow but never widen the ceiling" do
      {:ok, select} = Ignition.admit(input(%{"authorityCeiling" => "SELECT"}))
      widened = deep_merge(input(), kafka_sbb())
      assert Ignition.substitute(select, widened) == {:error, {:authority_widening, "CONSTRUCT"}}

      {:ok, construct} = Ignition.admit(input())
      narrowed = deep_merge(input(%{"authorityCeiling" => "SELECT"}), kafka_sbb())
      assert {:ok, %{ceiling: "SELECT"}, _} = Ignition.substitute(construct, narrowed)
    end

    test "no-op substitution and unadmitted substitute are refused" do
      {:ok, old} = Ignition.admit(input())
      assert Ignition.substitute(old, input()) == {:error, :substitution_noop}

      unknown = deep_merge(input(), kafka_sbb()) |> put_in(["sbb", "standing"], "UNKNOWN")
      assert Ignition.substitute(old, unknown) == {:error, {:standing_not_admitted, "UNKNOWN"}}
    end

    test "duplicate delivery of a receipt is refused as stale subject" do
      {:ok, a} = Ignition.admit(input())
      {:ok, b, r} = Ignition.substitute(a, deep_merge(input(), kafka_sbb()))
      {:ok, ^b} = Ignition.apply_migration(a, r, b)

      assert Ignition.apply_migration(b, r, b) ==
               {:error, {:stale_subject, a.binding_identity, b.binding_identity}}
    end

    test "reordered receipts are refused" do
      {:ok, a} = Ignition.admit(input())
      {:ok, b, r_ab} = Ignition.substitute(a, deep_merge(input(), kafka_sbb()))

      nats = %{
        "sbb" => %{
          "iri" => "urn:ea:sbb:nats",
          "digest" => d("sbb-nats"),
          "qualification" => %{"digest" => d("qual-nats"), "mutable" => false}
        }
      }

      {:ok, c, r_bc} = Ignition.substitute(b, deep_merge(input(), nats))
      assert {:error, {:stale_subject, _, _}} = Ignition.apply_migration(a, r_bc, c)
      assert {:ok, ^b} = Ignition.apply_migration(a, r_ab, b)
      assert {:ok, ^c} = Ignition.apply_migration(b, r_bc, c)
    end

    test "tampered receipt (replay mismatch) is refused" do
      {:ok, a} = Ignition.admit(input())
      {:ok, b, r} = Ignition.substitute(a, deep_merge(input(), kafka_sbb()))

      assert Ignition.apply_migration(a, %{r | "toSbb" => d("sbb-evil")}, b) ==
               {:error, :receipt_digest_mismatch}

      assert Ignition.apply_migration(a, Map.put(r, "grant", "DO"), b) ==
               {:error, :receipt_malformed}

      assert Ignition.apply_migration(a, Map.delete(r, "abb"), b) == {:error, :receipt_malformed}
      assert Ignition.apply_migration(a, "receipt", b) == {:error, :receipt_malformed}
    end

    test "receipt applied with a different target binding is refused" do
      {:ok, a} = Ignition.admit(input())
      {:ok, b, r} = Ignition.substitute(a, deep_merge(input(), kafka_sbb()))
      assert {:error, {:stale_subject, _, _}} = Ignition.apply_migration(a, r, a)
      _ = b
    end
  end

  describe "benchmark regression bound" do
    # Bounds are ~30x the medians recorded on an Apple M3 Max in
    # receipts/v26.9.26/ea-ignition-bench.json (admit 34.7us, substitute
    # 67.3us, verify_lock 16.3us, apply_migration 19.9us) so a hosted
    # runner passes while an accidental O(n^2) or per-call recompilation
    # regression fails. Median of 5 rounds, never a single sample.
    defp median_us(n, f) do
      for(_ <- 1..200, do: f.())

      rounds = for _ <- 1..5, do: round_us(n, f)

      rounds |> Enum.sort() |> Enum.at(2)
    end

    defp round_us(n, f) do
      {us, _} = :timer.tc(fn -> Enum.each(1..n, fn _ -> f.() end) end)
      us / n
    end

    test "admit/lock/substitute/apply_migration stay within bound" do
      {:ok, b} = Ignition.admit(input())
      k = deep_merge(input(), kafka_sbb())
      {:ok, nb, r} = Ignition.substitute(b, k)
      lock = Ignition.lock(b)

      bounds = [
        {"admit", 1_000, fn -> Ignition.admit(input()) end},
        {"verify_lock", 500, fn -> Ignition.verify_lock(lock, b) end},
        {"substitute", 2_000, fn -> Ignition.substitute(b, k) end},
        {"apply_migration", 600, fn -> Ignition.apply_migration(b, r, nb) end}
      ]

      for {name, bound, f} <- bounds do
        m = median_us(2_000, f)
        assert m < bound, "#{name} median #{m}us exceeds bound #{bound}us"
      end
    end
  end
end
