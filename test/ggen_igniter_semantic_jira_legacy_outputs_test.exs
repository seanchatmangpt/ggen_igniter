defmodule GgenIgniter.SemanticJiraLegacyOutputsTest do
  @moduledoc """
  Chicago-style: a real temporary git repository (real `git init`/`config`/
  `commit`), a real minimal pack on disk (real `ontology.ttl`, a real
  `gates/010_legacy.rq`, a real `templates/readme.md.eex` carrying `to:`
  frontmatter), a real ndjson standing ledger, and the real in-process
  `GgenIgniter.SemanticJira.Complete.run/1` -> `Execute.run/1` chain over
  them. Assertions are on real files the pipeline actuated, the real per-order
  receipt export bytes on disk, and the real ledger events. No doubles.

  What it proves (legacy-pack interop, the ggen-legacy leg): an admitted
  order's `outputs` spec WITHOUT an explicit `"out"` resolves its out path
  from the template's own `to:` frontmatter (execute.ex's `run_output/3`:
  explicit order `out` overrides; scope-checked at the target root either
  way). `Reconcile.run/1` still does NOT parse frontmatter — the execute hop
  parses only `to:`.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Complete, TransitionLog}

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @suite "legacy"
  @identity "LEGACY-1"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_legacy_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    target = git_repo!(Path.join(dir, "target"))
    pack = pack!(Path.join(dir, "pack"))
    # A dedicated clean git repo as the security gate's cwd (R1-5): the gate
    # must observe THIS repo, not the ggen_igniter checkout the test process
    # happens to run in — the suite asserts on verdicts, not on the host
    # repo's own diff posture.
    gate = git_repo!(Path.join(dir, "gate"))
    ledger = Path.join(dir, "standing-ledger.ndjson")
    receipts_dir = Path.join(dir, "receipts")

    %{
      dir: dir,
      target: target,
      pack: pack,
      gate: gate,
      ledger: ledger,
      receipts_dir: receipts_dir,
      work_orders: work_orders_file!(dir, target.head)
    }
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp git_repo!(dir) do
    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "legacy-test@example.invalid"])
    git!(dir, ["config", "user.name", "Legacy Test"])
    git!(dir, ["config", "commit.gpgsign", "false"])
    File.write!(Path.join(dir, "README"), "legacy test base\n")
    git!(dir, ["add", "README"])
    git!(dir, ["commit", "-q", "-m", "base"])
    %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
  end

  # A real minimal LEGACY-shaped pack: one gate (stem "legacy", the order's
  # required court, returning >=1 row), one EEx template whose `to:`
  # frontmatter names the target-relative out path — the template is the only
  # place the out path exists, because the order spec names no "out".
  defp pack!(pack_dir) do
    File.mkdir_p!(Path.join(pack_dir, "gates"))
    File.mkdir_p!(Path.join(pack_dir, "templates"))

    File.write!(
      Path.join(pack_dir, "ontology.ttl"),
      ~s(@prefix ex: <http://example.com/legacy-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:legacy-readme a ex:Report ; ex:title "legacy pack readme" .
)
    )

    File.write!(
      Path.join([pack_dir, "gates", "010_legacy.rq"]),
      ~s(PREFIX ex: <http://example.com/legacy-pack#>
SELECT DISTINCT ?subject WHERE {
  ?s a ex:Report ; ex:title ?subject .
}
)
    )

    File.write!(
      Path.join([pack_dir, "templates", "readme.md.eex"]),
      ~s(---
to: appliance/README.md
force: true
---
# legacy readme
<%= for row <- legacy do %>gate row: <%= row["subject"] %>
<% end %>)
    )

    pack_dir
  end

  defp work_orders_file!(dir, head, outputs \\ [%{"template" => "templates/readme.md.eex"}]) do
    path = Path.join(dir, "work_orders.json")

    order = %{
      "identity" => @identity,
      "title" => "Legacy-pack order with frontmatter-resolved outputs",
      "description" => "Known-class pack manufacture at the target HEAD.",
      "subject" => "legacy-test:subject",
      "repository" => "o/r",
      "base_sha" => head,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "repository-local",
      "promotion_rule" => "all_courts",
      "replay_identity" => "legacy:v1:#{@identity}",
      "required_courts" => [@suite],
      "required_evidence" => ["verification"],
      "acceptance" => ["urn:semantic-jira:acceptance:#{@identity}:a1"],
      "falsifiers" => ["urn:semantic-jira:falsifier:#{@identity}:f1"],
      "projections" => ["jira"],
      "origin_authority" => @origin_authority,
      "dependencies" => [],
      "outputs" => outputs
    }

    File.write!(path, Jason.encode!(%{"work_orders" => [order]}))

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
      receipts_dir: ctx.receipts_dir,
      # The security pre-step's cwd: a clean controlled repo, so the gate
      # verdict is deterministic and independent of the host checkout.
      cwd: ctx.gate.dir
    ]
  end

  describe "run/1 outputs without an explicit out (the to: frontmatter leg)" do
    test "actuates the frontmatter-named file into the real target tree", ctx do
      assert {0, result} = Complete.run(opts(ctx))

      assert result["status"] == "complete"
      assert result["closed"] == [@identity]
      assert result["closed_count"] == 1

      # The real file exists on disk at the template's own `to:` path,
      # rendered with the real gate rows.
      readme = Path.join(ctx.target.dir, "appliance/README.md")
      assert File.exists?(readme)

      # Frontmatter-stripped render fence: the actuated file must NOT carry
      # the template's frontmatter header bytes (witnessed live as real
      # pollution: 19 legacy appliance files gained frontmatter until the
      # :template_string seam landed).
      refute File.read!(readme) =~ ~r/^---/

      assert File.read!(readme) =~ "gate row: legacy pack readme"

      # The artifact metadata inside the real per-order receipt export on
      # disk carries the frontmatter-resolved, target-relative out.
      export =
        File.read!(Path.join(ctx.receipts_dir, "#{@identity}.json"))
        |> Jason.decode!()

      assert [%{"template" => "templates/readme.md.eex", "out" => "appliance/README.md"}] =
               export["artifacts"]

      assert is_binary(export["artifacts"] |> hd() |> Map.fetch!("sha256"))

      # The real standing transition is in the real ledger.
      assert {:ok, [%{"identity" => @identity, "to" => "PARTIAL_ALIVE", "seq" => 1}]} =
               TransitionLog.fetch(ctx.ledger)
    end

    test "an explicit order out overrides the template's to: (same scope law, reverse leg)",
         ctx do
      work_orders =
        work_orders_file!(ctx.dir, ctx.target.head, [
          %{"template" => "templates/readme.md.eex", "out" => "explicit/out.md"}
        ])

      assert {0, _} = Complete.run(opts(ctx, work_orders: work_orders))

      # The explicit out wins; the frontmatter path is NOT written.
      assert File.exists?(Path.join(ctx.target.dir, "explicit/out.md"))
      refute File.exists?(Path.join(ctx.target.dir, "appliance/README.md"))

      export =
        File.read!(Path.join(ctx.receipts_dir, "#{@identity}.json"))
        |> Jason.decode!()

      assert [%{"out" => "explicit/out.md"}] = export["artifacts"]
    end
  end
end
