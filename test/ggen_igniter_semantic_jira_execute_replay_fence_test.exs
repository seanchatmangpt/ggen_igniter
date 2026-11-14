defmodule GgenIgniter.SemanticJira.ExecuteReplayFenceTest do
  @moduledoc """
  Chicago, no doubles: real tmp git repo, real pack files on disk, real
  in-process `GgenIgniter.SemanticJira.Execute.run/1` chain, assertions on
  real ledger bytes, real receipt files, and the real refusal map.

  This file pins the `UNSUPPORTED(target_pack_digest_recheck)` residue of
  `GgenIgniter.SemanticJira.Execute`'s moduledoc as LIVE LAW, falsifiably:
  the local backend's target-pack gate pins the pack NAME only, so a pack
  whose content changed after sync but whose resolved name is unchanged
  executes without refusal. When the residue closes, the first test below
  fails and IS the signal to delete the UNSUPPORTED paragraph.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Execute, TransitionLog}

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
      "title" => "Replay-fence residue pin",
      "description" => "Name-only pack gate residue, pinned as live law.",
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

  describe "run/1 UNSUPPORTED(target_pack_digest_recheck) residue (pinned live law)" do
    test "a pack whose content changed after sync but whose name is unchanged executes WITHOUT refusal",
         ctx do
      # "Sync time": the digest the (never-persisted) sync stamp would have
      # recorded over this exact pack content.
      assert {:ok, sync_digest} = GgenIgniter.PackLock.digest_checked(ctx.pack)

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

      # The name gate passes (name is unchanged), and -- because the
      # sync-time digest stamp was never persisted -- NO digest comparison
      # runs. The order executes to PARTIAL_ALIVE over the tampered pack.
      assert {0, result} = Execute.run(local_opts(ctx))
      assert result["status"] == "executed"
      assert result["outcome"] == "partial_alive"

      # The tampered ontology actually rendered (the residue is live, not
      # theoretical): the actuated report carries the tampered title.
      report = Path.join(ctx.target.dir, "ggen-manufactured/report.md")
      assert File.exists?(report)
      assert File.read!(report) =~ "gate row: fence pack report TAMPERED"

      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE"}] =
               TransitionLog.read(ctx.ledger)
    end

    test "the moduledoc carries the typed UNSUPPORTED disclosure (regression fence on the residue note)",
         _ctx do
      # Real state assertion on the real compiled docs (read back from the
      # .beam on disk via Code.fetch_docs/1): the residue must stay
      # disclosed in the module itself, not only in a lane receipt.
      assert {:docs_v1, _, _elixir, _lang, %{"en" => text}, _meta, _docs} =
               Code.fetch_docs(GgenIgniter.SemanticJira.Execute)

      assert text =~ "UNSUPPORTED(target_pack_digest_recheck)"
      assert text =~ "PackLock.digest_checked/1"
      assert text =~ "TargetPack.enforce!/2"
      assert text =~ "never persisted"
    end
  end
end
