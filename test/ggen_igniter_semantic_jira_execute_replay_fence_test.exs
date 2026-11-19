defmodule GgenIgniter.SemanticJira.ExecuteReplayFenceTest do
  @moduledoc """
  Chicago, no doubles: real tmp git repo, real pack files on disk, real
  in-process `GgenIgniter.SemanticJira.Execute.run/1` chain, assertions on
  real ledger bytes, real receipt files, and the real refusal map.

  Closes the former `UNSUPPORTED(target_pack_digest_recheck)` residue:
  post-sync pack content tamper with an unchanged resolved name must refuse
  at the execute hop (fail-closed digest recheck against the durable sync
  stamp). A green run that still executes over tampered bytes is the failure
  signal -- these tests flip red if the fence is removed.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Execute, TargetPack, TransitionLog}

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @suite "ci"
  @identity "EXEC-1"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_replay_fence_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    target = git_repo!(Path.join(dir, "target"))
    pack = pack!(Path.join(dir, "pack"))

    # The pack resolves to its manifest name, "pack" (same value the
    # work order's target_pack carries below).
    File.write!(Path.join(pack, "pack.toml"), ~s([pack]\nname = "pack"\n))

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
    git!(dir, ["config", "user.email", "fence-test@example.invalid"])
    git!(dir, ["config", "user.name", "Replay Fence Test"])
    git!(dir, ["config", "commit.gpgsign", "false"])
    File.write!(Path.join(dir, "README"), "replay fence test base\n")
    git!(dir, ["add", "README"])
    git!(dir, ["commit", "-q", "-m", "base"])
    %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
  end

  # A real minimal pack: one gate, one EEx template, one ontology triple.
  # Same shape as the parent execute test fixture, fence-pack namespace.
  defp pack!(pack_dir) do
    File.mkdir_p!(Path.join(pack_dir, "gates"))
    File.mkdir_p!(Path.join(pack_dir, "templates"))

    File.write!(
      Path.join(pack_dir, "ontology.ttl"),
      ~s(@prefix ex: <http://example.com/fence-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:exec-report a ex:Report ; ex:title "fence pack report" .
)
    )

    File.write!(
      Path.join([pack_dir, "gates", "010_ci.rq"]),
      ~s(PREFIX ex: <http://example.com/fence-pack#>
SELECT DISTINCT ?subject WHERE {
  ?s a ex:Report ; ex:title ?subject .
}
)
    )

    File.write!(
      Path.join([pack_dir, "templates", "report.md.eex"]),
      ~s(# fence report
<%= for row <- ci do %>gate row: <%= row["subject"] %>
<% end %>)
    )

    pack_dir
  end

  defp work_orders_file!(dir, head, target_pack \\ "pack") do
    path = Path.join(dir, "work_orders.json")

    order = %{
      "identity" => @identity,
      "title" => "Replay-fence digest recheck",
      "description" => "Fail-closed post-sync pack digest recheck.",
      "subject" => "fence-test:subject",
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
      "dependencies" => [],
      "target_pack" => target_pack
    }

    File.write!(path, Jason.encode!(%{"work_orders" => [order]}))

    path
  end

  defp local_opts(ctx, extra \\ []) do
    extra ++
      [
        work_orders: ctx.work_orders,
        ledger: ctx.ledger,
        identity: @identity,
        verifier_suite: @suite,
        alias: "o/r=target",
        pack_dir: ctx.pack,
        target_dir: ctx.target.dir,
        receipt_out: ctx.receipt_out
      ]
  end

  defp stamp_sync!(ctx) do
    assert {:ok, sync_digest} = GgenIgniter.PackLock.digest_checked(ctx.pack)
    :ok = TargetPack.write_stamp!(ctx.target.dir, %{"pack" => sync_digest})
    sync_digest
  end

  describe "run/1 target_pack_digest_recheck (fail-closed fence)" do
    test "a pack whose content changed after sync but whose name is unchanged REFUSES before actuation",
         ctx do
      sync_digest = stamp_sync!(ctx)

      # Post-sync tamper: content changes, resolved name ("pack" via
      # pack.toml) does not.
      File.write!(
        Path.join(ctx.pack, "ontology.ttl"),
        String.replace(
          File.read!(Path.join(ctx.pack, "ontology.ttl")),
          "fence pack report",
          "fence pack report TAMPERED"
        )
      )

      assert {:ok, tampered_digest} = GgenIgniter.PackLock.digest_checked(ctx.pack)
      refute tampered_digest == sync_digest

      before_ledger =
        case File.read(ctx.ledger) do
          {:ok, body} -> body
          {:error, :enoent} -> ""
        end

      assert {1, refusal} = Execute.run(local_opts(ctx))
      assert refusal["standing"] == "REFUSED(target_pack_digest_mismatch)"
      assert refusal["reason"] == "target_pack_digest_mismatch"
      assert refusal["broken_term"] == "mu_unlawful"
      assert refusal["hop"] == "execute"
      assert refusal["detail"]["pack"] == "pack"
      assert refusal["detail"]["expected"] == sync_digest
      assert refusal["detail"]["actual"] == tampered_digest

      # NOTHING executed: no actuated report, no receipt, ledger unchanged.
      refute File.exists?(Path.join(ctx.target.dir, "ggen-manufactured/report.md"))
      refute File.exists?(ctx.receipt_out)

      after_ledger =
        case File.read(ctx.ledger) do
          {:ok, body} -> body
          {:error, :enoent} -> ""
        end

      assert after_ledger == before_ledger
    end

    test "a matching stamp lets the untampered pack execute", ctx do
      stamp_sync!(ctx)

      assert {0, result} = Execute.run(local_opts(ctx))
      assert result["status"] == "executed"
      assert result["outcome"] == "partial_alive"

      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE"}] =
               TransitionLog.read(ctx.ledger)
    end

    test "target_pack without a sync stamp refuses unsupported (never executes unchecked)",
         ctx do
      before_ledger =
        case File.read(ctx.ledger) do
          {:ok, body} -> body
          {:error, :enoent} -> ""
        end

      assert {1, refusal} = Execute.run(local_opts(ctx))
      assert refusal["standing"] == "REFUSED(target_pack_digest_recheck_unsupported)"
      assert refusal["reason"] == "target_pack_digest_recheck_unsupported"
      assert refusal["broken_term"] == "mu_unlawful"
      assert refusal["hop"] == "execute"

      refute File.exists?(Path.join(ctx.target.dir, "ggen-manufactured/report.md"))
      refute File.exists?(ctx.receipt_out)

      after_ledger =
        case File.read(ctx.ledger) do
          {:ok, body} -> body
          {:error, :enoent} -> ""
        end

      assert after_ledger == before_ledger
    end

    test "the moduledoc no longer discloses UNSUPPORTED(target_pack_digest_recheck)", _ctx do
      assert {:docs_v1, _, _elixir, _lang, %{"en" => text}, _meta, _docs} =
               Code.fetch_docs(GgenIgniter.SemanticJira.Execute)

      refute text =~ "UNSUPPORTED(target_pack_digest_recheck)"
      assert text =~ "target_pack_digest_mismatch"
      assert text =~ "target_pack_digest_recheck_unsupported"
      assert text =~ "target_pack_digests.json"
    end
  end
end
