defmodule GgenIgniter.SemanticJiraCompleteTest do
  @moduledoc """
  Chicago-style: a real temporary git repository (real `git init`/`config`/
  `commit`), a real minimal pack on disk (real `ontology.ttl` + `gates/*.rq` +
  `templates/*.eex`), a real ndjson standing ledger, and the real in-process
  `GgenIgniter.SemanticJira.Complete.run/1` loop driving the real
  `GgenIgniter.SemanticJira.Execute.run/1` chain over them. Assertions are on
  real returned state, real ledger bytes, real per-order receipt files, and
  the real event count `TransitionLog.fetch/1` reports. No doubles anywhere.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Complete, TransitionLog}

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @suite "ci"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_complete_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    target = git_repo!(Path.join(dir, "target"))
    pack = pack!(Path.join(dir, "pack"))
    ledger = Path.join(dir, "standing-ledger.ndjson")
    receipts_dir = Path.join(dir, "receipts")

    work_orders = work_orders_file!(dir, target.head)

    %{
      dir: dir,
      target: target,
      pack: pack,
      ledger: ledger,
      receipts_dir: receipts_dir,
      work_orders: work_orders
    }
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp git_repo!(dir) do
    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "complete-test@example.invalid"])
    git!(dir, ["config", "user.name", "Complete Test"])
    git!(dir, ["config", "commit.gpgsign", "false"])
    File.write!(Path.join(dir, "README"), "complete test base\n")
    git!(dir, ["add", "README"])
    git!(dir, ["commit", "-q", "-m", "base"])
    %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
  end

  # A real minimal pack: one gate (stem "ci", the orders' required court),
  # one EEx template rendering the gate rows, one ontology triple the gate
  # needs (the same shape the execute test fixture uses).
  defp pack!(pack_dir) do
    File.mkdir_p!(Path.join(pack_dir, "gates"))
    File.mkdir_p!(Path.join(pack_dir, "templates"))

    File.write!(
      Path.join(pack_dir, "ontology.ttl"),
      ~s(@prefix ex: <http://example.com/complete-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:complete-report a ex:Report ; ex:title "complete pack report" .
)
    )

    File.write!(
      Path.join([pack_dir, "gates", "010_ci.rq"]),
      ~s(PREFIX ex: <http://example.com/complete-pack#>
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

  defp order(identity, head, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => identity,
        "title" => "Complete loop order #{identity}",
        "description" => "Known-class pack manufacture at the target HEAD.",
        "subject" => "complete-test:subject",
        "repository" => "o/r",
        "base_sha" => head,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "all_courts",
        "replay_identity" => "complete:v1:#{identity}",
        "required_courts" => [@suite],
        "required_evidence" => ["verification"],
        "acceptance" => ["urn:semantic-jira:acceptance:#{identity}:a1"],
        "falsifiers" => ["urn:semantic-jira:falsifier:#{identity}:f1"],
        "projections" => ["jira"],
        "origin_authority" => @origin_authority,
        "dependencies" => []
      },
      overrides
    )
  end

  defp work_orders_file!(dir, head, overrides_a \\ %{}, overrides_b \\ %{}) do
    path = Path.join(dir, "work_orders.json")

    orders = [
      order("COMPLETE-1", head, overrides_a),
      order("COMPLETE-2", head, overrides_b)
    ]

    File.write!(path, Jason.encode!(%{"work_orders" => orders}))

    path
  end

  defp opts(ctx, extra \\ []) do
    # `extra` FIRST: `Keyword.get/3` reads the first occurrence, so an
    # explicit override must precede the base list.
    extra ++
      [
        work_orders: ctx.work_orders,
        ledger: ctx.ledger,
        verifier_suite: @suite,
        alias: "o/r=target",
        pack_dir: ctx.pack,
        target_dir: ctx.target.dir,
        receipts_dir: ctx.receipts_dir
      ]
  end

  defp ledger_bytes(ctx) do
    case File.read(ctx.ledger) do
      {:ok, bytes} -> bytes
      {:error, _} -> ""
    end
  end

  describe "run/1 (the completion loop)" do
    test "drives two eligible orders to a complete frontier, in close order", ctx do
      assert {0, result} = Complete.run(opts(ctx))

      assert result["status"] == "complete"
      assert result["closed"] == ["COMPLETE-1", "COMPLETE-2"]
      assert result["closed_count"] == 2

      # The kernel reports the SETTLED orders as blocked rows with their own
      # standing reason — closed work, listed verbatim, never failures.
      # Closed orders stand PARTIAL_ALIVE, so the frontier lists them under
      # blocked -- but they are SETTLED, not blocked: the completion receipt
      # reports only genuinely-open blocked rows.
      assert result["blocked"] == []
      assert result["blocked_count"] == 0
      assert Enum.map(result["orders"], & &1["identity"]) == ["COMPLETE-1", "COMPLETE-2"]
      assert result["ledger"] == ctx.ledger

      # Both per-order receipt files are real files on disk.
      assert File.exists?(Path.join(ctx.receipts_dir, "COMPLETE-1.json"))
      assert File.exists?(Path.join(ctx.receipts_dir, "COMPLETE-2.json"))

      # The real ledger holds exactly the two real transitions.
      assert {:ok, events} = TransitionLog.fetch(ctx.ledger)
      assert length(events) == 2
      assert Enum.map(events, & &1["identity"]) == ["COMPLETE-1", "COMPLETE-2"]
      assert Enum.all?(events, &(&1["to"] == "PARTIAL_ALIVE"))
    end

    test "re-running a completed backlog is idempotent: nothing closed, ledger byte-identical",
         ctx do
      assert {0, _} = Complete.run(opts(ctx))
      before = ledger_bytes(ctx)

      assert {0, result} = Complete.run(opts(ctx))

      assert result["status"] == "complete"
      assert result["closed"] == []
      assert result["orders"] == []
      assert result["closed_count"] == 0
      assert ledger_bytes(ctx) == before
    end

    test "a per-order refusal stops the loop fail-closed: closed orders stay, nothing more runs",
         ctx do
      # COMPLETE-2's base_sha is deliberately wrong: order A closes, order B
      # refuses base_drift inside the real Execute.run/1.
      work_orders =
        work_orders_file!(ctx.dir, ctx.target.head, %{}, %{
          "base_sha" => String.duplicate("a", 40)
        })

      assert {1, refusal} = Complete.run(opts(ctx, work_orders: work_orders))
      assert refusal["status"] == "refused"
      assert refusal["reason"] == "order_refused"
      assert refusal["identity"] == "COMPLETE-2"
      assert refusal["closed"] == ["COMPLETE-1"]
      assert refusal["closed_count"] == 1
      assert refusal["verdict"]["broken_term"] == "mu_on_O"
      assert ["base_drift", _] = refusal["verdict"]["reason"]

      # The order verdict names the real drift: target HEAD != all-"a" sha.
      assert refusal["verdict"]["hop"] == "execute"
      refute File.exists?(Path.join(ctx.receipts_dir, "COMPLETE-2.json"))
    end

    test "first-order refusal leaves the ledger byte-unchanged by the failed iteration", ctx do
      # A two-order file whose SECOND order carries a broken base: COMPLETE-1
      # closes, the loop stops on COMPLETE-2, and the failed iteration writes
      # nothing — bytes recorded after the close equal the bytes after the
      # refusal.
      fresh_ledger = Path.join(ctx.dir, "fresh-ledger.ndjson")
      fresh_receipts = Path.join(ctx.dir, "fresh-receipts")

      fresh_orders = [
        order("COMPLETE-1", ctx.target.head),
        order("COMPLETE-2", String.duplicate("a", 40))
      ]

      fresh_path = Path.join(ctx.dir, "fresh_work_orders.json")
      File.write!(fresh_path, Jason.encode!(%{"work_orders" => fresh_orders}))

      fresh_opts = [
        work_orders: fresh_path,
        ledger: fresh_ledger,
        verifier_suite: @suite,
        alias: "o/r=target",
        pack_dir: ctx.pack,
        target_dir: ctx.target.dir,
        receipts_dir: fresh_receipts
      ]

      assert {1, refusal} = Complete.run(fresh_opts)

      assert refusal["status"] == "refused"
      assert refusal["reason"] == "order_refused"
      assert refusal["identity"] == "COMPLETE-2"
      assert refusal["closed"] == ["COMPLETE-1"]
      assert refusal["closed_count"] == 1
      assert ["base_drift", _] = refusal["verdict"]["reason"]

      {:ok, events} = TransitionLog.fetch(fresh_ledger)
      assert Enum.map(events, & &1["identity"]) == ["COMPLETE-1"]

      bytes_after_close = File.read!(fresh_ledger)
      assert {1, _} = Complete.run(fresh_opts)
      assert File.read!(fresh_ledger) == bytes_after_close
      refute File.exists?(Path.join(fresh_receipts, "COMPLETE-2.json"))
    end

    test "a target_pack mismatch on the second order stops the loop after the first close",
         ctx do
      work_orders =
        work_orders_file!(ctx.dir, ctx.target.head, %{}, %{"target_pack" => "some-other-pack"})

      assert {1, refusal} = Complete.run(opts(ctx, work_orders: work_orders))

      assert refusal["status"] == "refused"
      assert refusal["reason"] == "order_refused"
      assert refusal["identity"] == "COMPLETE-2"
      assert refusal["closed"] == ["COMPLETE-1"]
      assert refusal["closed_count"] == 1
      # The per-order verdict is Execute.run/1's own target-pack refusal.
      assert refusal["verdict"]["standing"] == "REFUSED(target_pack_mismatch)"
      assert refusal["verdict"]["broken_term"] == "mu_unlawful"

      {:ok, events} = TransitionLog.fetch(ctx.ledger)
      assert Enum.map(events, & &1["identity"]) == ["COMPLETE-1"]
      refute File.exists?(Path.join(ctx.receipts_dir, "COMPLETE-2.json"))
    end

    test "--max 1 with two eligible orders refuses max_iterations_exhausted after one close",
         ctx do
      assert {1, refusal} = Complete.run(Keyword.put(opts(ctx), :max, 1))

      assert refusal["status"] == "refused"
      assert refusal["reason"] == "max_iterations_exhausted"
      assert refusal["closed"] == ["COMPLETE-1"]
      assert refusal["remaining_eligible"] == 1

      # The one closed order really closed; the second never ran.
      {:ok, events} = TransitionLog.fetch(ctx.ledger)
      assert Enum.map(events, & &1["identity"]) == ["COMPLETE-1"]
      refute File.exists?(Path.join(ctx.receipts_dir, "COMPLETE-2.json"))
    end

    test "missing --ledger is invalid invocation before the loop starts", ctx do
      assert {2, reason} = Complete.run(Keyword.delete(opts(ctx), :ledger))
      assert reason["status"] == "invalid_invocation"
      assert reason["reason"] == "missing --ledger"
    end
  end
end
