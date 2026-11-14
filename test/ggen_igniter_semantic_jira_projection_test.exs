defmodule GgenIgniter.SemanticJiraProjectionTest do
  @moduledoc """
  Chicago-style: a real temporary git repository (real `git init`/`commit`),
  a real pack copied from `test/fixtures/projection-pack/` (real ontology,
  gates, projections scope queries, templates on disk), a real pack.lock
  written with `GgenIgniter.PackLock.entry/3`, and the real in-process
  `GgenIgniter.SemanticJira.Projection.project/2` and
  `GgenIgniter.SemanticJira.Execute.run/1` chains over them. Assertions are
  on real returned state, real file bytes in the target tree, real receipt
  JSON on disk, and the real standing ledger. No test doubles anywhere: the
  one external input (the sealed export) is synthesized by the real
  `Execute` local-synthesis path itself.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.PackLock
  alias GgenIgniter.SemanticJira.{Execute, Projection, TransitionLog}

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @suite "ci"
  @identity "PROJ-1"
  @capability "demo-capability"
  @fixture_pack Path.expand("fixtures/projection-pack", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_projection_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    target = git_repo!(Path.join(dir, "target"))
    pack = pack_with_lock!(Path.join(dir, "pack"))
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

  # ── real collaborators ──────────────────────────────────────────────────────

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp git_repo!(dir) do
    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "projection-test@example.invalid"])
    git!(dir, ["config", "user.name", "Projection Test"])
    git!(dir, ["config", "commit.gpgsign", "false"])
    File.write!(Path.join(dir, "README"), "projection test base\n")
    git!(dir, ["add", "README"])
    git!(dir, ["commit", "-q", "-m", "base"])
    %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
  end

  # A real pack copy + a real pack.lock pinning its digest. The fixture is
  # COPIED (never mutated in place): several tests mutate their copy.
  defp pack_with_lock!(pack_dir) do
    File.rm_rf!(pack_dir)
    File.cp_r!(@fixture_pack, pack_dir)
    relock!(pack_dir)
    pack_dir
  end

  defp relock!(pack_dir) do
    lock_path = Path.join(Path.dirname(pack_dir), "ggen_igniter.pack.lock")

    lock =
      PackLock.empty() |> PackLock.put(Path.basename(pack_dir), PackLock.entry(pack_dir, "test"))

    PackLock.write(lock_path, lock)
    lock_path
  end

  defp order_map(head, overrides \\ %{}) do
    base = %{
      "identity" => @identity,
      "title" => "Project one capability through the projection backend",
      "description" => "Pack-locked, capability-scoped manufacture at the target HEAD.",
      "subject" => "projection-test:subject",
      "repository" => "o/r",
      "base_sha" => head,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "repository-local",
      "promotion_rule" => "all_courts",
      "replay_identity" => "projection:v1:PROJ-1",
      "required_courts" => [@suite],
      "required_evidence" => ["verification"],
      "acceptance" => ["urn:semantic-jira:acceptance:PROJ-1:a1"],
      "falsifiers" => ["urn:semantic-jira:falsifier:PROJ-1:f1"],
      "projections" => ["worker"],
      "origin_authority" => @origin_authority,
      "dependencies" => [],
      "capability_id" => @capability,
      "target_path" => "ggen-manufactured/demo-capability.md"
    }

    Map.merge(base, overrides)
  end

  defp work_orders_file!(dir, head, overrides \\ %{}) do
    path = Path.join(dir, "work_orders.json")
    File.write!(path, Jason.encode!(%{"work_orders" => [order_map(head, overrides)]}))
    path
  end

  defp projection_opts(ctx, overrides \\ []) do
    # `overrides` FIRST: `Keyword.get/3` reads the first occurrence.
    overrides ++
      [
        work_orders: ctx.work_orders,
        ledger: ctx.ledger,
        identity: @identity,
        verifier_suite: @suite,
        alias: "o/r=target",
        pack_dir: ctx.pack,
        target_dir: ctx.target.dir,
        pack_lock: Path.join(Path.dirname(ctx.pack), "ggen_igniter.pack.lock"),
        receipt_out: ctx.receipt_out
      ]
  end

  defp ledger_bytes(ctx) do
    case File.read(ctx.ledger) do
      {:ok, bytes} -> bytes
      {:error, _} -> ""
    end
  end

  defp artifact_path(ctx), do: Path.join(ctx.target.dir, "ggen-manufactured/demo-capability.md")

  # ── end-to-end: the projection backend through Execute.run/1 ────────────────

  describe "run/1 projection backend (--pack-lock)" do
    test "executes one order end to end: scoped render, guarded write, gates, projection receipt",
         ctx do
      assert {0, result} = Execute.run(projection_opts(ctx))
      assert result["status"] == "executed"
      assert result["outcome"] == "partial_alive"
      assert result["event"]["to"] == "PARTIAL_ALIVE"

      # The scoped render: exactly the demo-capability row, not the other one.
      content = File.read!(artifact_path(ctx))
      assert content =~ "capability row: projection fixture row"
      refute content =~ "another row"

      # The receipt-out export carries the D4 projection receipt and the
      # honest-ceiling invariants of the synthesized local export.
      export = ctx.receipt_out |> File.read!() |> Jason.decode!()
      assert export["projection_write_outcome"] == "written"
      assert export["head_verified"] == false
      assert export["outcome"] == "partial_alive"

      proj = export["projection"]
      assert proj["order_id"] == @identity
      assert proj["capability_id"] == @capability
      assert proj["pack_digest"] == PackLock.digest(ctx.pack)
      assert proj["render_digest"] == GgenIgniter.SemanticJira.digest_exact(content)
      assert proj["gate_results"]["status"] == "pass"
      assert proj["target_path"] == "ggen-manufactured/demo-capability.md"

      # The projected falsifier gate exists for the order's one falsifier and
      # is annotated with its URN.
      gate_file =
        Path.join([ctx.pack, "verify", "#{@capability}-falsifier-1.unbound.rq"])

      # (the gate lives in the staging copy, which is cleaned up; the pack
      # itself stays byte-identical to its lock)
      refute File.exists?(gate_file)
      assert :ok = PackLock.check(ctx.pack, projection_opts(ctx)[:pack_lock])

      # The real event is in the real ledger.
      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE", "seq" => 1}] =
               TransitionLog.read(ctx.ledger)
    end

    test "replaying the executed order refuses not_eligible, ledger byte-unchanged", ctx do
      assert {0, _} = Execute.run(projection_opts(ctx))
      before = ledger_bytes(ctx)

      assert {1, refusal} = Execute.run(projection_opts(ctx))
      assert refusal["hop"] == "frontier"
      assert refusal["reason"] == ["not_eligible", @identity, "standing=PARTIAL_ALIVE"]
      assert ledger_bytes(ctx) == before
    end

    test "an order for an unknown capability refuses capability_unknown at the execute hop",
         ctx do
      ctx = %{
        ctx
        | work_orders: work_orders_file!(ctx.dir, ctx.target.head, %{"capability_id" => "nope"})
      }

      assert {1, refusal} = Execute.run(projection_opts(ctx))
      assert refusal["hop"] == "execute"
      assert refusal["reason"] == ["capability_unknown", "nope"]
      assert refusal["broken_term"] == "R_missing_identity"
      assert ledger_bytes(ctx) == ""
      refute File.exists?(ctx.receipt_out)
    end
  end

  # ── the module contract, exercised directly ─────────────────────────────────

  describe "Projection.project/2" do
    defp proj_opts(ctx, overrides \\ []) do
      overrides ++
        [
          pack_dir: ctx.pack,
          target_dir: ctx.target.dir,
          lock_path: Path.join(Path.dirname(ctx.pack), "ggen_igniter.pack.lock"),
          capability_id: @capability,
          target_path: "ggen-manufactured/demo-capability.md",
          falsifiers: ["urn:semantic-jira:falsifier:PROJ-1:f1"]
        ]
    end

    test "idempotent: :written then :unchanged on an identical re-run, bytes stable", ctx do
      assert {:ok, :written, receipt} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      content = File.read!(artifact_path(ctx))
      assert receipt["render_digest"] == GgenIgniter.SemanticJira.digest_exact(content)

      assert {:ok, :unchanged, _} = Projection.project(order_map(ctx.target.head), proj_opts(ctx))
      assert File.read!(artifact_path(ctx)) == content
    end

    test ":skipped_exists honors unless_exists even when content would differ", ctx do
      assert {:ok, :written, _} = Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      # Mutate the pack's rendered content (row title), re-pin the lock: the
      # render now differs, but unless_exists skips the write.
      ontology = Path.join(ctx.pack, "ontology.ttl")

      File.write!(
        ontology,
        String.replace(File.read!(ontology), "projection fixture row", "mutated row")
      )

      relock!(ctx.pack)

      assert {:ok, :skipped_exists, _} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx, unless_exists: true))

      assert File.read!(artifact_path(ctx)) =~ "projection fixture row"
    end

    test "a changed pack re-writes (:written) after the lock is re-pinned", ctx do
      assert {:ok, :written, first} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      ontology = Path.join(ctx.pack, "ontology.ttl")

      File.write!(
        ontology,
        String.replace(File.read!(ontology), "projection fixture row", "mutated row")
      )

      relock!(ctx.pack)

      assert {:ok, :written, second} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      assert second["pack_digest"] != first["pack_digest"]
      assert second["render_digest"] != first["render_digest"]
      assert File.read!(artifact_path(ctx)) =~ "mutated row"
    end

    test "a tampered pack (digest mismatch vs lock) refuses before any byte", ctx do
      File.write!(Path.join(ctx.pack, "TAMPERED"), "x")

      assert {:error, {:pack_lock_failed, {:pack_digest_mismatch, _}}} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      refute File.exists?(artifact_path(ctx))
    end

    test "a target path escaping the target root refuses before any byte", ctx do
      assert {:error, {:bad_output_path, _}} =
               Projection.project(
                 order_map(ctx.target.head),
                 proj_opts(ctx, target_path: "../escape.md")
               )

      refute File.exists?(Path.join(Path.dirname(ctx.target.dir), "escape.md"))
    end

    test "the projected falsifier gate FIRES: a row violating the falsified state refuses verification",
         ctx do
      # Non-vacuity: inject a capability row lacking ex:title (the pack's
      # falsified-state query binds it), re-pin the lock honestly, run.
      ontology = Path.join(ctx.pack, "ontology.ttl")
      File.write!(ontology, File.read!(ontology) <> "\nex:bad-row a ex:Row .\n")
      relock!(ctx.pack)

      assert {:error, {:verification_failed, message}} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))

      assert message =~ "unbound_facts"
      # The gate ran; the write already happened (D4 order: write, then
      # post-render gates) and standing was never advanced by this module.
      assert File.exists?(artifact_path(ctx))
    end

    test "a capability with falsifiers but no falsified-state query refuses", ctx do
      File.rm_rf!(Path.join(ctx.pack, "projections/#{@capability}.unbound.rq"))
      relock!(ctx.pack)

      assert {:error, {:falsifier_gates_missing, @capability}} =
               Projection.project(order_map(ctx.target.head), proj_opts(ctx))
    end

    test "no falsifiers means no falsified-state query is required", ctx do
      assert {:ok, :written, receipt} =
               Projection.project(
                 order_map(ctx.target.head),
                 proj_opts(ctx, falsifiers: [])
               )

      assert receipt["gate_results"]["status"] == "pass"
    end

    test "missing capability_id refuses", ctx do
      order = order_map(ctx.target.head) |> Map.delete("capability_id")

      assert {:error, {:capability_unknown, ""}} =
               Projection.project(order, proj_opts(ctx, capability_id: ""))
    end
  end
end
