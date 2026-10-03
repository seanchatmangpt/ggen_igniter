defmodule Mix.Tasks.SemanticJira.AdmitCandidatesSovereignTest do
  @moduledoc """
  Chicago test of the sovereign ceiling gate in
  `mix semantic_jira.admit_candidates`: the real task module, the real
  canonical authority index, the REAL pack ontology digest (read from
  `priv/ggen/semantic-jira-pack/ontology.ttl` on disk), a real keys JSON file,
  and a real JSONL candidates file. Assertions are on printed verdicts and
  judge_line returns only; every digest is read from disk, never hard-coded.
  No doubles.
  """

  # async: false -- uses the global Mix.shell/captured IO/Mix tasks.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira.SovereignLease
  alias Mix.Tasks.SemanticJira.AdmitCandidates

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @objective @sj <> "objective-code-work-authority"
  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)

  # RFC 8032 Ed25519 TEST 1 and TEST 2 private keys: fixed, deterministic.
  @priv_alice Base.decode16!("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
                case: :lower
              )

  @priv_bob Base.decode16!("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
              case: :lower
            )

  # {public, private} on this toolchain (see SovereignLease moduledoc note).
  defp pub_for(priv), do: elem(:crypto.generate_key(:eddsa, :ed25519, priv), 0)

  defp keys_map, do: %{"alice" => pub_for(@priv_alice), "bob" => pub_for(@priv_bob)}

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_sov_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{
      dir: dir,
      current_digest: Digest.hex(File.read!("priv/ggen/semantic-jira-pack/ontology.ttl"))
    }
  end

  defp candidate(identity, origin, overrides \\ %{}) do
    @fixture
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("work_orders")
    |> Enum.find(&(&1["identity"] == "FRI-FMT-A"))
    |> Map.put("identity", identity)
    |> Map.put("replay_identity", "admit-candidates-sov:" <> identity)
    |> Map.put("origin_authority", origin)
    |> Map.merge(overrides)
  end

  defp write_keys_file!(dir, map) do
    path = Path.join(dir, "keys.json")

    File.write!(
      path,
      Jason.encode!(
        Map.new(map, fn {signer, pub} ->
          {signer, Base.encode16(pub, case: :lower)}
        end)
      )
    )

    path
  end

  defp leased(candidate) do
    lease = %{
      "lease_id" => "lease:" <> candidate["identity"],
      "subject_iri" => "urn:ggen:pack:semantic-jira-pack",
      "shapes" => ["#{@sj}WorkOrderShape"],
      # The pre-evolution digest: anything != the CURRENT real pack digest.
      "ontology_digest" => "sha256:" <> String.duplicate("9", 64),
      "granted_at" => "2026-10-02T00:00:00Z",
      "signatures" => []
    }

    signed =
      lease
      |> Map.update!("signatures", &[SovereignLease.sign(lease, "alice", @priv_alice) | &1])
      |> Map.update!("signatures", &[SovereignLease.sign(lease, "bob", @priv_bob) | &1])

    Map.put(candidate, "sovereign_lease", signed)
  end

  defp run_task(args) do
    Mix.Task.reenable("semantic_jira.admit_candidates")
    capture_io(fn -> AdmitCandidates.run(args) end)
  end

  describe "mix semantic_jira.admit_candidates --sovereign-keys (printed verdicts)" do
    test "SOVEREIGN without lease refused REQUIRED; valid 2-sig lease admitted; 1-sig refused INVALID",
         %{dir: dir} = ctx do
      keys_path =
        write_keys_file!(dir, %{"alice" => pub_for(@priv_alice), "bob" => pub_for(@priv_bob)})

      plain = candidate("X-PLAIN", @objective)
      no_lease = candidate("X-SOV-NOLEASE", @objective, %{"authority_requirement" => "SOVEREIGN"})

      one_sig =
        "X-SOV-1SIG"
        |> candidate(@objective, %{"authority_requirement" => "SOVEREIGN"})
        |> leased()
        |> update_in(["sovereign_lease", Access.key!("signatures")], &tl/1)

      valid =
        "X-SOV-OK"
        |> candidate(@objective, %{"authority_requirement" => "SOVEREIGN"})
        |> leased()

      unchanged =
        "X-SOV-UNCHANGED"
        |> candidate(@objective, %{"authority_requirement" => "SOVEREIGN"})
        |> leased()
        |> put_in(["sovereign_lease", Access.key!("ontology_digest")], ctx.current_digest)

      path = Path.join(dir, "candidates.jsonl")

      File.write!(
        path,
        Enum.map_join([plain, no_lease, valid, one_sig, unchanged], "\n", &Jason.encode!/1)
      )

      out = run_task(["--candidates", path, "--sovereign-keys", keys_path])

      assert out =~ ~s(admitted 1 X-PLAIN origin=#{@objective})
      assert out =~ "REFUSED:SOVEREIGN_LEASE_REQUIRED"
      assert out =~ "REFUSED:SOVEREIGN_LEASE_INVALID"
      assert out =~ "admitted 3 X-SOV-OK origin=#{@objective}"
      assert out =~ "insufficient_signatures"
      assert out =~ "shape_digest_unchanged"
      assert out =~ "summary admitted=2 refused=3"
    end

    test "fail closed: no --sovereign-keys flag refuses every SOVEREIGN candidate", %{dir: dir} do
      no_lease = candidate("X-SOV-NOKEYS", @objective, %{"authority_requirement" => "SOVEREIGN"})
      path = Path.join(dir, "candidates.jsonl")
      File.write!(path, Jason.encode!(no_lease) <> "\n")

      out = run_task(["--candidates", path])

      assert out =~ "REFUSED:SOVEREIGN_LEASE_REQUIRED"
      assert out =~ "summary admitted=0 refused=1"
    end

    test "fail closed: an unreadable keys file refuses SOVEREIGN but spares NONE", %{dir: dir} do
      missing = Path.join(dir, "absent-keys.json")

      plain = candidate("X-PLAIN2", @objective)

      sov =
        "X-SOV-NOFILE"
        |> candidate(@objective, %{"authority_requirement" => "SOVEREIGN"})
        |> leased()

      path = Path.join(dir, "candidates.jsonl")
      File.write!(path, Enum.map_join([plain, sov], "\n", &Jason.encode!/1))

      out = run_task(["--candidates", path, "--sovereign-keys", missing])

      assert out =~ "sovereign_keys_unavailable"
      assert out =~ "admitted 1 X-PLAIN2"
      assert out =~ "summary admitted=1 refused=1"
    end

    test "judge_line returns the typed tuples behind the printed codes", %{dir: dir} = ctx do
      _ = dir
      {:ok, index} = GgenIgniter.SemanticJira.Authority.index_from([])
      sovereign = [ontology_digest: ctx.current_digest, public_keys: keys_map()]

      no_lease =
        candidate("X-SOV-J1", @objective, %{"authority_requirement" => "SOVEREIGN"})

      assert {:refused, "X-SOV-J1",
              {:refused_candidate, {:sovereign_lease_required, :no_sovereign_lease}}} =
               AdmitCandidates.judge_line(Jason.encode!(no_lease), index, nil, sovereign)
    end
  end
end
