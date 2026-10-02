defmodule GgenIgniter.SemanticJiraExecuteTest do
  @moduledoc """
  Chicago, no doubles: a real temporary git repository (real `git init`/
  `config`/`commit`), a real minimal pack on disk (real `ontology.ttl` +
  `gates/*.rq` + `templates/*.eex`), a real ndjson standing ledger, and the
  real in-process `GgenIgniter.SemanticJira.Execute.run/1` chain over them.
  Assertions are on real returned state, real ledger bytes, real receipt
  files, and the real `Descriptor.receipt_from_xaas/2` verdicts.

  The one external input that cannot be produced in-process is the sealed
  XaaS export of the external-backend case: per the documented contract of
  `Descriptor.receipt_from_xaas/2` it is written as data (the fabric lives in
  the xaas repository), and every step that consumes it is the real code.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Descriptor, Execute, Reconciler, TransitionLog}

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @suite "ci"
  @identity "EXEC-1"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_execute_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    target = git_repo!(Path.join(dir, "target"))
    pack = pack!(Path.join(dir, "pack"))
    ledger = Path.join(dir, "standing-ledger.ndjson")
    work_orders = work_orders_file!(dir, target.head)
    receipt_out = Path.join(dir, "receipt-export.json")

    %{
      dir: dir,
      target: target,
      pack: pack,
      ledger: ledger,
      work_orders: work_orders,
      receipt_out: receipt_out
    }
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp git_repo!(dir) do
    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "execute-test@example.invalid"])
    git!(dir, ["config", "user.name", "Execute Test"])
    git!(dir, ["config", "commit.gpgsign", "false"])
    File.write!(Path.join(dir, "README"), "execute test base\n")
    git!(dir, ["add", "README"])
    git!(dir, ["commit", "-q", "-m", "base"])
    %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
  end

  # A real minimal pack: one gate (`gates/010_ci.rq`, stem "ci" -- the work
  # order's required court), one EEx template that renders the gate rows (an
  # empty row list renders empty, so the gate-failure case fails at the GATE
  # hop, not in the pipeline), one ontology triple the gate needs.
  defp pack!(pack_dir) do
    File.mkdir_p!(Path.join(pack_dir, "gates"))
    File.mkdir_p!(Path.join(pack_dir, "templates"))

    File.write!(
      Path.join(pack_dir, "ontology.ttl"),
      ~s(@prefix ex: <http://example.com/execute-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:exec-report a ex:Report ; ex:title "execute pack report" .
)
    )

    File.write!(
      Path.join([pack_dir, "gates", "010_ci.rq"]),
      ~s(PREFIX ex: <http://example.com/execute-pack#>
SELECT DISTINCT ?subject WHERE {
  ?s a ex:Report ; ex:title ?subject .
}
)
    )

    File.write!(
      Path.join([pack_dir, "templates", "report.md.eex"]),
      ~s(# ggen-manufactured report
<%= for row <- ci do %>gate row: <%= row["subject"] %>
<% end %>)
    )

    pack_dir
  end

  defp work_orders_file!(dir, head) do
    path = Path.join(dir, "work_orders.json")

    File.write!(
      path,
      Jason.encode!(%{
        "work_orders" => [
          %{
            "identity" => @identity,
            "title" => "Execute one order through the local loop",
            "description" => "Known-class pack manufacture at the target HEAD.",
            "subject" => "execute-test:subject",
            "repository" => "o/r",
            "base_sha" => head,
            "standing" => "UNKNOWN",
            "evidence_ceiling" => "repository-local",
            "promotion_rule" => "all_courts",
            "replay_identity" => "execute:v1:EXEC-1",
            "required_courts" => [@suite],
            "required_evidence" => ["verification"],
            "acceptance" => ["urn:semantic-jira:acceptance:EXEC-1:a1"],
            "falsifiers" => ["urn:semantic-jira:falsifier:EXEC-1:f1"],
            "projections" => ["jira"],
            "origin_authority" => @origin_authority,
            "dependencies" => []
          }
        ]
      })
    )

    path
  end

  defp local_opts(ctx, extra \\ []) do
    [
      work_orders: ctx.work_orders,
      ledger: ctx.ledger,
      identity: @identity,
      verifier_suite: @suite,
      alias: "o/r=target",
      pack_dir: ctx.pack,
      target_dir: ctx.target.dir,
      receipt_out: ctx.receipt_out
    ] ++ extra
  end

  defp external_opts(ctx, receipt_path, extra \\ []) do
    [
      work_orders: ctx.work_orders,
      ledger: ctx.ledger,
      identity: @identity,
      verifier_suite: @suite,
      alias: "o/r=target",
      receipt: receipt_path
    ] ++ extra
  end

  defp ledger_bytes(ctx) do
    case File.read(ctx.ledger) do
      {:ok, bytes} -> bytes
      {:error, _} -> ""
    end
  end

  defp work_order_list(ctx),
    do: ctx.work_orders |> File.read!() |> Jason.decode!() |> Map.fetch!("work_orders")

  # The sealed XaaS export for a `partial_alive` outcome, written as data per
  # `Descriptor.receipt_from_xaas/2`'s documented contract: bridge echo, the
  # verifier suite step that judged the required court, and the court receipt
  # binding the order's acceptance/falsifier IRIs.
  defp sealed_partial_alive(bridge) do
    export = %{
      "epoch_id" => "epoch-external",
      "run_id" => "run-external",
      "receipt_id" => "receipt-external",
      "bridge" => bridge,
      "final_head" => "0123456789abcdef0123456789abcdef01234567",
      "outcome" => "partial_alive",
      "head_verified" => false,
      "fabric_verifier" => %{
        "status" => "pass",
        "steps" => [%{"id" => @suite, "status" => "pass"}],
        "court_receipt" => %{
          "acceptance_results" => Map.new(bridge["requires"]["acceptance"], &{&1, true}),
          "falsifier_results" => Map.new(bridge["requires"]["falsifiers"], &{&1, "survived"})
        }
      }
    }

    Map.put(export, "receipt_digest", Descriptor.receipt_digest(export))
  end

  describe "run/1 local backend (the full loop)" do
    test "executes one frontier order to PARTIAL_ALIVE: real event, real receipt, honest ceiling",
         ctx do
      assert {0, result} = Execute.run(local_opts(ctx))
      assert result["status"] == "executed"
      assert result["identity"] == @identity
      assert result["outcome"] == "partial_alive"
      assert result["head_verified"] == false
      assert result["target"] == "PARTIAL_ALIVE"
      assert result["receipt_out"] == ctx.receipt_out
      assert Regex.match?(~r/\A[0-9a-f]{40}\z/, result["final_head"])
      assert result["event"]["to"] == "PARTIAL_ALIVE"

      # The actuated set is real: the pipeline wrote the pack's report into
      # the target work tree, and final_head is its CONTENT identity.
      report = Path.join(ctx.target.dir, "ggen-manufactured/report.md")
      assert File.exists?(report)
      assert File.read!(report) =~ "gate row: execute pack report"

      # The real event is in the real ledger, and the projection stands at
      # PARTIAL_ALIVE for the executed order.
      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE", "seq" => 1}] =
               TransitionLog.read(ctx.ledger)

      assert {:ok, [order], _evidence} =
               Reconciler.project(work_order_list(ctx), TransitionLog.read(ctx.ledger))

      assert order["standing"] == "PARTIAL_ALIVE"

      # The receipt-out digest recomputes over its own content, and the real
      # consumer seam accepts the synthesized export against the same bridge.
      export = ctx.receipt_out |> File.read!() |> Jason.decode!()
      assert export["outcome"] == "partial_alive"
      assert export["head_verified"] == false
      assert export["receipt_digest"] == Descriptor.receipt_digest(export)
      assert {:ok, receipt} = Descriptor.receipt_from_xaas(export, export["bridge"])
      assert receipt["target"] == "PARTIAL_ALIVE"
      assert receipt["candidate_sha"] == result["final_head"]

      # Honest ceiling on the synthesis surface itself: no local export ever
      # claims ALIVE or an exact head.
      refute export["outcome"] == "alive"
      refute export["head_verified"] == true
    end

    test "replaying the same order refuses not_eligible and leaves the ledger byte-unchanged",
         ctx do
      assert {0, _} = Execute.run(local_opts(ctx))
      before = ledger_bytes(ctx)

      assert {1, refusal} = Execute.run(local_opts(ctx, out_dir: Path.join(ctx.dir, "out")))
      assert refusal["standing"] == "REFUSED"
      assert refusal["hop"] == "frontier"
      assert refusal["broken_term"] == "R_missing_standing"
      assert refusal["reason"] == ["not_eligible", @identity, "standing=PARTIAL_ALIVE"]

      # The refusal is also on disk where --out-dir asked for it.
      assert File.read!(Path.join([ctx.dir, "out", "refused.json"]))
             |> Jason.decode!() == refusal

      assert ledger_bytes(ctx) == before
    end
  end

  describe "run/1 honest-ceiling mutant (a local export claiming ALIVE is refused)" do
    test "outcome alive with head_verified false refuses alive_without_head_verification at the real seam",
         ctx do
      assert {0, _} = Execute.run(local_opts(ctx))
      export = ctx.receipt_out |> File.read!() |> Jason.decode!()
      bridge = export["bridge"]

      mutant =
        export
        |> Map.put("outcome", "alive")
        |> Map.put("head_verified", false)
        |> then(&Map.put(&1, "receipt_digest", Descriptor.receipt_digest(&1)))

      assert {:error, {:receipt_refused, :alive_without_head_verification}} =
               Descriptor.receipt_from_xaas(mutant, bridge)

      # And a mutated digest (tampered after sealing) refuses even earlier.
      tampered = Map.put(mutant, "head_verified", true)

      assert {:error, {:receipt_refused, :receipt_digest_mismatch}} =
               Descriptor.receipt_from_xaas(tampered, bridge)
    end
  end

  describe "run/1 external backend (--receipt PATH)" do
    test "consumes a sealed export as data and appends the transition", ctx do
      assert {:ok, descriptor} =
               Descriptor.build_xaas_contract(work_order_list(ctx), [], @identity,
                 verifier_suite: @suite,
                 aliases: %{"o/r" => "target"}
               )

      export = sealed_partial_alive(descriptor["bridge"])

      receipt_path = Path.join(ctx.dir, "external-export.json")
      File.write!(receipt_path, Jason.encode!(export))

      assert {0, result} = Execute.run(external_opts(ctx, receipt_path))
      assert result["status"] == "executed"
      assert result["target"] == "PARTIAL_ALIVE"
      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE"}] =
               TransitionLog.read(ctx.ledger)

      # Ambiguous execution input is invalid invocation, not a refusal.
      assert {2, %{"status" => "invalid_invocation"}} =
               Execute.run(external_opts(ctx, receipt_path, pack_dir: ctx.pack))
    end
  end

  describe "run/1 fail-closed refusals (the ledger is byte-unchanged, no receipt)" do
    test "a gate the broken ontology fails refuses verification_failed", ctx do
      File.write!(
        Path.join(ctx.pack, "ontology.ttl"),
        ~s(@prefix ex: <http://example.com/execute-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:exec-report a ex:Report .
)
      )

      before = ledger_bytes(ctx)

      assert {1, refusal} = Execute.run(local_opts(ctx))

      assert refusal["standing"] == "REFUSED"
      assert refusal["hop"] == "execute"
      assert refusal["broken_term"] == "admission_vacuous"
      assert ["verification_failed", _] = refusal["reason"]
      refute File.exists?(ctx.receipt_out)
      refute File.exists?(ctx.ledger)
      assert before == ""
    end

    test "a commit after the order's base_sha refuses base_drift", ctx do
      File.write!(Path.join(ctx.target.dir, "drift.txt"), "moved past the base\n")
      git!(ctx.target.dir, ["add", "drift.txt"])
      git!(ctx.target.dir, ["commit", "-q", "-m", "drift"])

      assert {1, refusal} = Execute.run(local_opts(ctx))
      assert refusal["hop"] == "execute"
      assert refusal["broken_term"] == "mu_on_O"
      assert ["base_drift", _] = refusal["reason"]
      refute File.exists?(ctx.ledger)
      refute File.exists?(ctx.receipt_out)
    end

    test "a tampered ledger refuses ledger_refused at step 1, byte-unchanged", ctx do
      TransitionLog.append(ctx.ledger, %{
        "kind" => "standing_transition_event",
        "identity" => @identity,
        "from" => "UNKNOWN",
        "to" => "PARTIAL_ALIVE",
        "authority" => "NONE"
      })

      before = ledger_bytes(ctx)
      forged = String.replace(before, "\"to\":\"PARTIAL_ALIVE\"", "\"to\":\"ALIVE\"")
      File.write!(ctx.ledger, forged)

      assert {1, refusal} = Execute.run(local_opts(ctx))
      assert refusal["hop"] == "frontier"
      assert refusal["broken_term"] == "R_missing_replay"
      assert ["ledger_refused", _] = refusal["reason"]
      assert ledger_bytes(ctx) == forged
      refute File.exists?(ctx.receipt_out)
    end
  end
end
