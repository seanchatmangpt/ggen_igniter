defmodule GgenIgniter.SemanticJira.SovereignLeaseTest do
  @moduledoc """
  Chicago-style proof of the Sovereign Ceiling Lease (authority kind 0x04):
  real Ed25519 keys (RFC 8032 test vectors, no generation), real canonical
  bytes, real SPARQL gate 066 execution, real kernel promotions. No doubles.

  Covers: the multi-party law, EdDSA verification over the canonical lease
  bytes, the strictly monotonic evolution law (digest delta required), the
  graph-level gate 066, the kernel authority check for SOVEREIGN orders, and
  a real source-level anti-vacuity mutation over the signature gate.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Ontology
  alias GgenIgniter.Query
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.SovereignLease

  @gate_query File.read!(
                Path.join(
                  File.cwd!(),
                  "priv/ggen/semantic-jira-pack/gates/066_monotonic_evolution.rq"
                )
              )
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @pinned @sj <> "objective-code-work-authority"

  # RFC 8032 Ed25519 test vectors (TEST 1 and TEST 2 private keys): fixed and
  # deterministic, no key generation anywhere in the suite.
  @priv_alice Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
                case: :lower
              )

  @priv_bob Base.decode16!("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
              case: :lower
            )

  # On this toolchain :crypto.generate_key(:eddsa, :ed25519, priv) returns
  # {public, private} (order verified against the RFC 8032 vector; see the
  # SovereignLease moduledoc note).
  defp pub_for(priv), do: elem(:crypto.generate_key(:eddsa, :ed25519, priv), 0)
  defp keys, do: %{"alice" => pub_for(@priv_alice), "bob" => pub_for(@priv_bob)}

  @prev_digest "sha256:" <> String.duplicate("1", 64)
  @current_digest "sha256:" <> String.duplicate("2", 64)

  defp lease(overrides \\ %{}) do
    Map.merge(
      %{
        "lease_id" => "lease:mono-1",
        "subject_iri" => "urn:ggen:pack:semantic-jira-pack",
        "shapes" => ["#{@sj}WorkOrderShape"],
        "ontology_digest" => @prev_digest,
        "granted_at" => "2026-10-02T00:00:00Z",
        "signatures" => []
      },
      overrides
    )
  end

  defp sign_as(base, signer, priv) do
    %{base | "signatures" => [SovereignLease.sign(base, signer, priv) | base["signatures"]]}
  end

  defp signed_lease, do: lease() |> sign_as("alice", @priv_alice) |> sign_as("bob", @priv_bob)

  # Flips the first hex nibble of the signature string: a real tamper.
  defp flip_hex(<<hex::binary-size(1), rest::binary>>),
    do: if(hex == "F", do: "0", else: "F") <> rest

  describe "SovereignLease.admit/3 (multi-party + EdDSA + monotonic digest)" do
    test "a lease with 2 distinct EdDSA signatures admits and records the signers" do
      assert {:ok, record} =
               SovereignLease.admit(signed_lease(), @current_digest, public_keys: keys())

      assert record["admitted"] == true
      assert record["verified_signers"] == ["alice", "bob"]
      refute Map.has_key?(record, "signatures")
      assert record["lease_id"] == "lease:mono-1"
      assert record["ontology_digest"] == @prev_digest
    end

    test "1 signature refuses :insufficient_signatures" do
      one_sig = signed_lease() |> Map.put("signatures", tl(signed_lease()["signatures"]))

      assert {:error, {:refused_sovereign, :insufficient_signatures}} =
               SovereignLease.admit(one_sig, @current_digest, public_keys: keys())
    end

    test "2 signatures from ONE signer is still :insufficient_signatures (distinct signers)" do
      base = lease()

      twice = %{
        base
        | "signatures" => [
            SovereignLease.sign(base, "alice", @priv_alice),
            SovereignLease.sign(base, "alice", @priv_alice)
          ]
      }

      assert {:error, {:refused_sovereign, :insufficient_signatures}} =
               SovereignLease.admit(twice, @current_digest, public_keys: keys())
    end

    test "wrong public key (or unconfigured signer) refuses :signature_invalid" do
      only_alice = %{"alice" => pub_for(@priv_alice)}

      assert {:error, {:refused_sovereign, :signature_invalid}} =
               SovereignLease.admit(signed_lease(), @current_digest, public_keys: only_alice)
    end

    test "a tampered signature value refuses :signature_invalid" do
      forged =
        signed_lease()
        |> update_in(["signatures", Access.at(0), "sig"], &flip_hex/1)

      assert {:error, {:refused_sovereign, :signature_invalid}} =
               SovereignLease.admit(forged, @current_digest, public_keys: keys())
    end

    test "alg other than EdDSA refuses :signature_invalid" do
      swapped =
        signed_lease()
        |> put_in(["signatures", Access.at(0), "alg"], "RS256")

      assert {:error, {:refused_sovereign, :signature_invalid}} =
               SovereignLease.admit(swapped, @current_digest, public_keys: keys())
    end

    test "a lease over the UNCHANGED digest is a no-op refusal (:shape_digest_unchanged)" do
      assert {:error, {:refused_sovereign, :shape_digest_unchanged}} =
               SovereignLease.admit(signed_lease(), @prev_digest, public_keys: keys())
    end

    test "a struct lease normalizes and admits; non-map input fails closed" do
      base = signed_lease()

      struct_lease =
        struct(SovereignLease, Map.new(base, fn {k, v} -> {String.to_atom(k), v} end))

      assert {:ok, _} = SovereignLease.admit(struct_lease, @current_digest, public_keys: keys())

      assert {:error, {:refused_sovereign, :invalid_lease}} =
               SovereignLease.admit("not a lease", @current_digest, public_keys: keys())
    end

    test "canonical_json is insertion-order independent (sorted-key bytes)" do
      a = %{
        "lease_id" => "l",
        "subject_iri" => "s",
        "ontology_digest" => "d",
        "granted_at" => "g",
        "shapes" => ["x"]
      }

      b = %{
        "shapes" => ["x"],
        "granted_at" => "g",
        "ontology_digest" => "d",
        "subject_iri" => "s",
        "lease_id" => "l"
      }

      assert SovereignLease.canonical_json(a) == SovereignLease.canonical_json(b)
      assert SovereignLease.canonical_json(a) =~ ~s({"granted_at":"g",)
    end

    test "no wall clock: granted_at is never evaluated, only recorded and signed" do
      # granted_at is part of the signed canonical bytes (tampering with it is
      # refused), but its CONTENT is never evaluated by the admit decision:
      # far-past and far-future grants admit identically when properly signed.
      l1 = lease(%{"granted_at" => "1999-01-01T00:00:00Z"})
      l2 = lease(%{"granted_at" => "2099-01-01T00:00:00Z"})

      l1 = l1 |> sign_as("alice", @priv_alice) |> sign_as("bob", @priv_bob)
      l2 = l2 |> sign_as("alice", @priv_alice) |> sign_as("bob", @priv_bob)

      assert match?({:ok, _}, SovereignLease.admit(l1, @current_digest, public_keys: keys()))
      assert match?({:ok, _}, SovereignLease.admit(l2, @current_digest, public_keys: keys()))
    end
  end

  describe "gate 066_monotonic_evolution (graph-level multi-party law)" do
    defp order_ttl(requirement) do
      """
      @prefix sj: <#{@sj}> .
      @prefix dcterms: <http://purl.org/dc/terms/> .

      sj:order-under-test a sj:WorkOrder ;
        dcterms:identifier "SJ-MONO-GATE" ;
        sj:authorityRequirement "#{requirement}" .
      """
      |> String.replace("\n      ", "\n")
      |> String.replace("\n    \"\"\"", "\n\"\"\"")
    end

    defp gate_rows(ttl) do
      path = Path.join(System.tmp_dir!(), "gate066_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, ttl)
      on_exit(fn -> File.rm_rf!(path) end)
      Query.run(Ontology.load!(path), @gate_query)
    end

    defp with_two_sig_lease(order_ttl) do
      order_ttl <>
        """
        sj:lease-ok a sj:SovereignLease ;
          sj:leaseFor sj:order-under-test ;
          sj:leaseId "lease:gate" ;
          sj:leaseOntologyDigest "sha256:#{"1" |> String.duplicate(64)}" ;
          sj:signature sj:sig-a, sj:sig-b .

        sj:sig-a a sj:LeaseSignature .
        sj:sig-b a sj:LeaseSignature .
        """
    end

    test "a SOVEREIGN order with no lease row: gate 066 rows" do
      assert [%{"order" => _}] = gate_rows(order_ttl("SOVEREIGN"))
    end

    test "a SOVEREIGN order with a 1-signature lease row: gate 066 rows" do
      ttl =
        order_ttl("SOVEREIGN") <>
          """
          sj:lease-thin a sj:SovereignLease ;
            sj:leaseFor sj:order-under-test ;
            sj:signature sj:sig-a .
          sj:sig-a a sj:LeaseSignature .
          """

      assert [%{"order" => _}] = gate_rows(ttl)
    end

    test "a SOVEREIGN order with a 2-signature lease: zero rows (pass)" do
      assert [] = gate_rows(with_two_sig_lease(order_ttl("SOVEREIGN")))
    end

    test "a NONE-requirement order: zero rows (gate only binds SOVEREIGN)" do
      assert [] = gate_rows(order_ttl("NONE"))
    end

    test "the real pack ontology is clean under gate 066" do
      assert [] = Query.run(Ontology.load!(@ontology_path), @gate_query)
    end
  end

  describe "kernel authority check (SemanticJira.promote/3, SOVEREIGN requirement)" do
    defp sov_order do
      Map.merge(
        %{
          "identity" => "SJ-SOV-001",
          "title" => "Sovereign evolution subject",
          "description" => "Exercise the sovereign lease authority law.",
          "subject" => "urn:subject:sov",
          "repository" => "seanchatmangpt/ggen_igniter",
          "base_sha" => String.duplicate("a", 40),
          "standing" => "UNKNOWN",
          "evidence_ceiling" => "repository-local",
          "promotion_rule" => "exact subject and independent evidence",
          "replay_identity" => "semantic-jira:sov:1",
          "dependencies" => [],
          "required_courts" => ["court:sov"],
          "required_evidence" => ["source", "verification"],
          "acceptance" => ["acceptance:sov"],
          "falsifiers" => ["falsifier:sov"],
          "projections" => SemanticJira.projection_types(),
          "required_receipt_classes" => ["verification"],
          "path_scope" => ["lib/ggen_igniter"],
          "authority_requirement" => "SOVEREIGN",
          "origin_authority" => @pinned,
          "replay_required" => false
        },
        %{}
      )
    end

    defp promote_evidence(order, extra \\ %{}) do
      {:ok, admitted} = SemanticJira.admit_work_order(order)

      Map.merge(
        %{
          "work_order_digest" => admitted["work_order_digest"],
          "subject" => admitted["subject"],
          "repository" => admitted["repository"],
          "base_sha" => admitted["base_sha"],
          "dependency_evidence" => %{},
          "court_results" => %{"court:sov" => %{"passed" => true}},
          "evidence_types" => admitted["required_evidence"],
          "acceptance_results" => Map.new(admitted["acceptance"], &{&1, true}),
          "falsifier_results" => Map.new(admitted["falsifiers"], &{&1, "survived"}),
          "receipt_classes" => admitted["required_receipt_classes"],
          "evidence_ceiling" => admitted["evidence_ceiling"],
          "observed_execution" => true,
          "inherited_standing" => false
        },
        extra
      )
    end

    test "SOVEREIGN + admitted lease record in evidence: authority check passes" do
      {:ok, record} = SovereignLease.admit(signed_lease(), @current_digest, public_keys: keys())

      assert {:ok, intent} =
               SemanticJira.promote(
                 sov_order(),
                 "PARTIAL_ALIVE",
                 promote_evidence(sov_order(), %{"sovereign_lease" => record})
               )

      assert intent["checks"].authority == true
    end

    test "SOVEREIGN without a lease record: promotion refused on authority" do
      assert {:error, {:promotion_refused, [:authority]}} =
               SemanticJira.promote(sov_order(), "PARTIAL_ALIVE", promote_evidence(sov_order()))
    end

    test "SOVEREIGN with only a prepared authority receipt is NOT satisfied" do
      {:ok, admitted} = SemanticJira.admit_work_order(sov_order())

      receipt = %{
        "status" => "prepared",
        "work_order_digest" => admitted["work_order_digest"],
        "subject" => admitted["subject"],
        "replay_identity" => admitted["replay_identity"],
        "authority_identity" => "authority:x"
      }

      evidence = promote_evidence(sov_order(), %{"authority_receipt" => receipt})

      assert {:error, {:promotion_refused, [:authority]}} =
               SemanticJira.promote(sov_order(), "PARTIAL_ALIVE", evidence)
    end

    test "NONE requirement is unaffected by the sovereign clause" do
      order = Map.put(sov_order(), "authority_requirement", "NONE")
      assert {:ok, intent} = SemanticJira.promote(order, "PARTIAL_ALIVE", promote_evidence(order))
      assert intent["checks"].authority == true
    end
  end

  describe "anti-vacuity: source-level signature-gate mutation" do
    @target_line "with :ok <- count(lease), :ok <- verify_all(lease, keys), do: :ok"
    @module_line "defmodule GgenIgniter.SemanticJira.SovereignLease do"

    test "bypassing the signature gate makes the 1-signature refusal disappear (compile-time executed)" do
      source =
        File.read!(Path.join(File.cwd!(), "lib/ggen_igniter/semantic_jira/sovereign_lease.ex"))

      assert source =~ @target_line,
             "the mutation anchor moved: repoint the anti-vacuity mutation at the real signature_gate line"

      one_sig = signed_lease() |> Map.put("signatures", tl(signed_lease()["signatures"]))

      # Control: the REAL module refuses the 1-signature lease.
      assert {:error, {:refused_sovereign, :insufficient_signatures}} =
               SovereignLease.admit(one_sig, @current_digest, public_keys: keys())

      # The mutant: the exact signature_gate line replaced by a pass-through,
      # compiled as a real, differently-named module.
      mutant_source =
        source
        |> String.replace(@module_line, "defmodule SovereignLeaseBypassMutant do")
        |> String.replace(@target_line, ":ok")

      assert mutant_source != source

      Code.compile_string(mutant_source, "sovereign_lease_bypass_mutant.ex")
      mutant = String.to_atom("Elixir.SovereignLeaseBypassMutant")

      assert {:ok, _} = apply(mutant, :admit, [one_sig, @current_digest, [public_keys: %{}]])

      # And the mutant also lets a WRONG-KEY lease through, proving the real
      # refusal is caused by exactly the bypassed law, not by shape checks.
      assert {:ok, _} =
               apply(mutant, :admit, [signed_lease(), @current_digest, [public_keys: %{}]])
    end
  end
end
