defmodule GgenIgniter.SemanticJiraBootstrapTest do
  @moduledoc """
  Chicago, no doubles (GC-26.9.23 gate GC23-1, lane V23-B; PRD section 8.1,
  PR-006, PR-013; ARD sections 7, 16 and 26 F5/F6): the real
  `GgenIgniter.SemanticJira.Bootstrap.run/1`, the real
  `mix semantic_jira.bootstrap` task and the real
  `scripts/sjira/bootstrap_court.sh`, over a real temporary git repository
  (real `git init`/`commit`), the committed fixture goal graph
  `test/fixtures/semantic-jira-bootstrap/goal.ttl`, real R-schema receipt
  files, a real file-backed TransitionLog and real fleet files. The two-run
  tests spawn real `mix` subprocesses under `env -i` with a fresh `HOME`.

  Assertions are on the reconstructed state (derived standing, frontier
  class, invalidation records, digests, refusal codes, exit codes, file
  bytes) -- never on which functions ran.

  In-process calls pass `env: %{}` explicitly: the refusal of LLM
  credentials is a function of that environment map and has its own test,
  so these tests do not depend on the variables of the shell running them.
  """
  # async: false -- the subprocess tests run `mix` in this checkout, which
  # shares the _build directory with the test VM.
  use ExUnit.Case, async: false

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira.Bootstrap
  alias GgenIgniter.SemanticJira.Bootstrap.Graph
  alias GgenIgniter.SemanticJira.TransitionLog

  @fixture_goal Path.expand("fixtures/semantic-jira-bootstrap/goal.ttl", __DIR__)
  @pack_dir "priv/ggen/semantic-jira-pack"
  # Every order's sj:originAuthority (SJ-002): the pinned canonical objective,
  # restated verbatim in the fixture goal (G1 trust-root pin law; the fixture
  # root GoalCheckpoint t:GC-T is self-stamped and not pinned).
  @origin_iri "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  # Independent witness: python3 json.dumps(tuple, sort_keys=True,
  # separators=(",", ":"), ensure_ascii=False) over T-A's contract tuple.
  @t_a_tuple_digest "sha256:531183e0033603b9ff0fbde841dde6400a9738143d8665eac2e3d005e16f2100"
  # Same witness over T-Z's tuple, which has no sj:exclusion: sj:exclusion is
  # 0..n and the digest carries "exclusions":[] (semantic-jira-pack
  # FridayWorkOrderShape; xaas Xaas.Sa2a.Route admit_field/2).
  @t_z_tuple_digest "sha256:62fa02612af7ad1ae413d1738a230f650059c0e6b4f713cb179cedb3b1399517"
  @repository "fixture/subject"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_bootstrap_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    repo = Path.join(dir, "subject")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q"])
    # The "unreadable covered commit" cases corrupt the object store by
    # deleting a tree. A commit-graph with changed-path Bloom filters (written
    # by the runner's git maintenance, or explicitly) lets `git log -- <path>`
    # answer without reading that tree, so the corruption would be invisible
    # and the fixture nondeterministic across git versions (CI 35933570910).
    # Pin the fixture repository to plain object reads.
    git!(repo, ["config", "core.commitGraph", "false"])
    git!(repo, ["config", "maintenance.auto", "false"])
    git!(repo, ["config", "gc.auto", "0"])
    git!(repo, ["config", "user.email", "v23-b@example.invalid"])
    git!(repo, ["config", "user.name", "V23-B"])
    git!(repo, ["config", "commit.gpgsign", "false"])
    covered = commit!(repo, "lib/a.ex", "defmodule A do\nend\n", "lib: covered by T-A")
    commit!(repo, "docs/readme.md", "fixture\n", "docs: outside T-A's scope")

    receipt = receipt(covered, "ALIVE", @t_a_tuple_digest)
    receipt_commit = commit!(repo, "receipts/T-A.json", Jason.encode!(receipt), "receipt: T-A")

    universe = Path.join(dir, "universe.json")

    File.write!(
      universe,
      Jason.encode!(%{
        "repositories" => [%{"name" => "subject", "github" => @repository, "path" => repo}]
      })
    )

    %{
      dir: dir,
      repo: repo,
      covered: covered,
      receipt_commit: receipt_commit,
      universe: universe,
      receipts: Path.join(repo, "receipts"),
      ledger: Path.join(dir, "ledger/standing-ledger.ndjson")
    }
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp commit!(repo, path, content, message) do
    full = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
    git!(repo, ["add", path])
    git!(repo, ["commit", "-q", "-m", message])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp receipt(subject_sha, standing, tuple_digest, id \\ "T-A") do
    %{
      "identity" => %{
        "subject" => id,
        "repo" => @repository,
        "subject_sha" => subject_sha,
        "base_sha" => subject_sha,
        "work_order" => "t:WO-" <> id,
        "tuple_digest" => tuple_digest
      },
      "authority" => %{"ceiling" => "CONSTRUCT", "grant" => "NONE", "actor" => "fixture"},
      "consequence" => %{
        "commits" => [subject_sha],
        "files_changed" => [],
        "remote_effects" => []
      },
      "replay" => %{"commands" => [%{"cmd" => "mix test", "cwd" => ".", "exit" => 0}]},
      "standing" => %{"value" => standing, "derived_from" => "fixture run at #{subject_sha}"}
    }
  end

  defp opts(ctx, extra \\ []) do
    Keyword.merge(
      [
        fleet: ctx.universe,
        goal: @fixture_goal,
        ledger: ctx.ledger,
        receipts_dirs: [ctx.receipts],
        checkouts: ["#{@repository}=#{ctx.repo}"],
        env: %{}
      ],
      extra
    )
  end

  defp run!(ctx, extra \\ []) do
    assert {:ok, result} = Bootstrap.run(opts(ctx, extra))
    result
  end

  defp order(result, id), do: result.state["orders"][id]

  # A work graph (--graphs) with two orders under the fixture root's gate
  # G-1: T-Z (covers lib/, no sj:exclusion at all) and T-N (a path scope no
  # commit ever touched). Each declares its own capability node, because the
  # pack queries read one graph at a time.
  defp extra_graph!(ctx) do
    path = Path.join(ctx.dir, "extra-orders.ttl")

    File.write!(path, """
    @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
    @prefix t: <https://ggen-igniter.dev/sjira/bootstrap-fixture#> .
    @prefix dcterms: <http://purl.org/dc/terms/> .
    t:cap-z a sj:Capability ; sj:capabilityId "recipe:fixture-z" .
    t:WO-T-Z a sj:WorkOrder ;
      dcterms:identifier "T-Z" ; dcterms:title "Fixture order Z" ;
      dcterms:description "No sj:exclusion: the tuple carries exclusions = []." ;
      sj:repository "fixture/subject" ;
      sj:baseSha "1111111111111111111111111111111111111111" ;
      sj:subject "fixture:order-z" ; sj:pathScope "lib/" ;
      sj:evidenceCeiling "EXECUTED_VERIFIED" ; sj:authorityCeiling "CONSTRUCT" ;
      sj:authorityRequirement "NONE" ;
      sj:promotionRule "Standing advances only from receipts." ;
      sj:replayIdentity "semantic-jira:fixture:T-Z" ;
      sj:requiresCourt t:court-T-Z ; sj:requiresEvidence sj:receipt-evidence ;
      sj:requiresReceiptClass "verification" ; sj:acceptance t:acceptance-T-Z ;
      sj:falsifier t:falsifier-T-Z ; sj:projection sj:markdown-projection ;
      sj:checkpointOf t:G-1 ; sj:originAuthority sj:objective-code-work-authority ;
      sj:postcondition "Order Z postcondition." ;
      sj:requiresCapability t:cap-z ; sj:evidenceHorizon "EXECUTED_VERIFIED" ;
      sj:consequenceClass "verification" ;
      sj:successorPolicy "discovered work -> t:GC-T-next" .
    t:cap-n a sj:Capability ; sj:capabilityId "recipe:fixture-n" .
    t:WO-T-N a sj:WorkOrder ;
      dcterms:identifier "T-N" ; dcterms:title "Fixture order N" ;
      dcterms:description "Covers a path no commit ever touched." ;
      sj:repository "fixture/subject" ;
      sj:baseSha "1111111111111111111111111111111111111111" ;
      sj:subject "fixture:order-n" ; sj:pathScope "never/" ;
      sj:evidenceCeiling "EXECUTED_VERIFIED" ; sj:authorityCeiling "CONSTRUCT" ;
      sj:authorityRequirement "NONE" ;
      sj:promotionRule "Standing advances only from receipts." ;
      sj:replayIdentity "semantic-jira:fixture:T-N" ;
      sj:requiresCourt t:court-T-N ; sj:requiresEvidence sj:receipt-evidence ;
      sj:requiresReceiptClass "verification" ; sj:acceptance t:acceptance-T-N ;
      sj:falsifier t:falsifier-T-N ; sj:projection sj:markdown-projection ;
      sj:checkpointOf t:G-1 ; sj:originAuthority sj:objective-code-work-authority ;
      sj:postcondition "Order N postcondition." ;
      sj:requiresCapability t:cap-n ; sj:evidenceHorizon "EXECUTED_VERIFIED" ;
      sj:exclusion "No LLM on the path." ; sj:consequenceClass "verification" ;
      sj:successorPolicy "discovered work -> t:GC-T-next" .
    """)

    path
  end

  defp input(result, role, ref),
    do: Enum.find(result.state["inputs"], &(&1["role"] == role and &1["ref"] == ref))

  # ── the court environment: env -i, fresh HOME, no LLM variable ────────────

  # The toolchain dirs are resolved here, independently of the product's
  # Bootstrap.Guard: a test helper that called product code would crash
  # before its assertions whenever that code is absent or mutated.
  defp court_path do
    [System.find_executable("elixir"), System.find_executable("erl")]
    |> Enum.map(&(&1 |> resolve_link(0) |> Path.dirname()))
    |> then(&Enum.join(["/usr/bin", "/bin" | &1], ":"))
  end

  defp resolve_link(path, hops) when hops < 40 do
    case File.read_link(path) do
      {:ok, target} -> target |> Path.expand(Path.dirname(path)) |> resolve_link(hops + 1)
      {:error, _not_a_link} -> path
    end
  end

  defp cold_env(home) do
    [
      "PATH=#{court_path()}",
      "HOME=#{home}",
      "MIX_HOME=#{System.get_env("MIX_HOME") || Path.expand("~/.mix")}",
      "HEX_HOME=#{System.get_env("HEX_HOME") || Path.expand("~/.hex")}",
      "LANG=en_US.UTF-8",
      "MIX_ENV=test"
    ]
  end

  defp cold_mix!(ctx, args, extra_env \\ []) do
    home = Path.join(ctx.dir, "home-#{System.unique_integer([:positive])}")
    File.mkdir_p!(home)

    System.cmd("env", ["-i"] ++ cold_env(home) ++ extra_env ++ ["mix" | args],
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  defp task_args(ctx, out) do
    [
      "semantic_jira.bootstrap",
      "--fleet",
      ctx.universe,
      "--goal",
      @fixture_goal,
      "--receipts-dir",
      ctx.receipts,
      "--ledger",
      ctx.ledger,
      "--checkout",
      "#{@repository}=#{ctx.repo}",
      "--out",
      out
    ]
  end

  describe "mix semantic_jira.bootstrap (two cold processes)" do
    test "two runs under env -i with fresh HOMEs write byte-identical, digest-bound state", ctx do
      out1 = Path.join(ctx.dir, "run1/state.json")
      out2 = Path.join(ctx.dir, "run2/state.json")

      {log1, code1} = cold_mix!(ctx, task_args(ctx, out1))
      {log2, code2} = cold_mix!(ctx, task_args(ctx, out2))
      assert code1 == 0, log1
      assert code2 == 0, log2

      bytes = File.read!(out1)
      assert bytes == File.read!(out2)
      assert byte_size(bytes) > 1000

      %{"state" => state, "state_digest" => digest} = Jason.decode!(bytes)
      assert digest == Digest.sha256(Bootstrap.canonical_json(state))
      assert log1 =~ "STATE_DIGEST #{digest}"

      assert bytes ==
               Bootstrap.canonical_json(%{"state" => state, "state_digest" => digest}) <> "\n"

      # the reconstruction: active GoalCheckpoint, subjects, capabilities,
      # authority, receipts, derived standing and frontier
      assert state["checkpoint"]["root"]["id"] == "GC-T"
      assert Enum.map(state["checkpoint"]["gates"], & &1["id"]) == ["G-1", "G-2"]
      assert [%{"id" => "GC-T-next", "orders" => ["T-S"]}] = state["checkpoint"]["successors"]

      assert [%{"repository" => @repository, "head_sha" => head, "status" => "observed"}] =
               state["subjects"]

      assert head == ctx.receipt_commit

      assert Enum.map(state["capabilities"], & &1["id"]) == [
               "construct:fixture-b",
               "recipe:fixture-a"
             ]

      assert state["authority"]["orders"]["T-A"]["ceiling"] == "CONSTRUCT"

      assert %{"standing" => "ALIVE", "standing_source" => "receipt", "frontier" => "settled"} =
               state["orders"]["T-A"]

      assert state["orders"]["T-A"]["tuple_digest"] == @t_a_tuple_digest
      assert state["orders"]["T-A"]["origin_authority"] == @origin_iri
      assert state["orders"]["T-B"]["origin_authority"] == @origin_iri
      assert state["orders"]["T-S"]["origin_authority"] == @origin_iri
      assert state["orders"]["T-A"]["covered_commit"] == ctx.covered
      assert %{"frontier" => "eligible", "critical_path" => true} = state["orders"]["T-B"]
      assert %{"critical_path" => false, "successor" => true} = state["orders"]["T-S"]
      assert Enum.map(state["frontier"]["eligible"], & &1["identity"]) == ["T-B", "T-S"]

      # no timestamp, no host path: the fixture's tmp paths never appear
      refute bytes =~ ctx.dir
      refute bytes =~ System.tmp_dir!()
    end

    test "a forbidden path argument is refused by the task and nothing is written", ctx do
      claude = Path.join(ctx.dir, ".claude")
      File.mkdir_p!(claude)
      File.cp!(@fixture_goal, Path.join(claude, "goal.ttl"))
      out = Path.join(ctx.dir, "refused/state.json")

      args =
        task_args(ctx, out)
        |> Enum.map(fn
          @fixture_goal -> Path.join(claude, "goal.ttl")
          other -> other
        end)

      {log, code} = cold_mix!(ctx, args)
      assert code == 1
      assert log =~ "REFUSED(forbidden_input) goal:"
      refute File.exists?(out)
    end

    test "an LLM credential variable in the task's environment is refused (mu_on_O)", ctx do
      out = Path.join(ctx.dir, "llm/state.json")

      {log, code} =
        cold_mix!(ctx, task_args(ctx, out), ["ANTHROPIC_API_KEY=sk-fixture-not-a-key"])

      assert code == 1
      assert log =~ "REFUSED(llm_credential_present)"
      assert log =~ "ANTHROPIC_API_KEY"
      assert log =~ "mu_on_O"
      refute log =~ "sk-fixture-not-a-key"
      refute File.exists?(out)
    end
  end

  describe "run/1 derived standing (PR-006)" do
    test "deleting a receipt changes the derived standing, the frontier and the digest (F5)",
         ctx do
      before = run!(ctx)
      assert order(before, "T-A")["standing"] == "ALIVE"
      assert order(before, "T-B")["frontier"] == "eligible"

      File.rm!(Path.join(ctx.receipts, "T-A.json"))
      after_delete = run!(ctx)

      assert after_delete.digest != before.digest

      assert %{"standing" => "UNKNOWN", "standing_source" => "none", "receipt" => nil} =
               order(after_delete, "T-A")

      assert order(after_delete, "T-A")["frontier"] == "eligible"
      assert order(after_delete, "T-B")["frontier"] == "blocked"
      assert order(after_delete, "T-B")["frontier_reason"] == "dependencies_unsatisfied"
      assert after_delete.state["receipts"] == []
    end

    test "a commit on the covered path demotes ALIVE and re-admits the order (F6)", ctx do
      assert order(run!(ctx), "T-A")["standing"] == "ALIVE"

      advanced =
        commit!(ctx.repo, "lib/a.ex", "defmodule A do\n  def b, do: :c\nend\n", "lib: advance")

      result = run!(ctx)
      t_a = order(result, "T-A")

      assert t_a["standing"] == "UNKNOWN"
      assert t_a["frontier"] == "eligible"

      assert [
               %{
                 "reason" => "subject_advanced",
                 "receipt_subject_sha" => covered,
                 "receipt_covered_commit" => covered,
                 "current_covered_commit" => ^advanced
               }
             ] = t_a["invalidated"]

      assert covered == ctx.covered
      assert order(result, "T-B")["frontier"] == "blocked"
    end

    test "a commit outside the covered path (and the receipt commit itself) keeps ALIVE", ctx do
      commit!(ctx.repo, "docs/readme.md", "changed\n", "docs: unrelated")
      commit!(ctx.repo, "src/b.ex", "defmodule B do\nend\n", "src: T-B's scope, not T-A's")
      t_a = order(run!(ctx), "T-A")

      assert t_a["standing"] == "ALIVE"
      assert t_a["covered_scope"] == ["lib/"]
      assert t_a["cross_repository_scope"] == ["other:docs/x.md"]
      assert t_a["invalidated"] == []
    end

    test "a receipt bound to another tuple digest or failing R admission confers nothing", ctx do
      File.write!(
        Path.join(ctx.receipts, "T-A.json"),
        Jason.encode!(receipt(ctx.covered, "ALIVE", "sha256:" <> String.duplicate("0", 64)))
      )

      assert %{"standing" => "UNKNOWN", "unlinked" => [%{"reason" => "tuple_digest_mismatch"}]} =
               order(run!(ctx), "T-A")

      vacuous =
        receipt(ctx.covered, "ALIVE", @t_a_tuple_digest)
        |> put_in(["replay", "commands"], [%{"cmd" => "mix test", "cwd" => ".", "exit" => 1}])

      File.write!(Path.join(ctx.receipts, "T-A.json"), Jason.encode!(vacuous))
      result = run!(ctx)
      assert [%{"reason" => "refused: " <> why}] = order(result, "T-A")["unlinked"]
      assert why =~ "admission_vacuous"
      assert [%{"verdict" => "refused"}] = result.state["receipts"]
      assert Enum.any?(result.state["exceptions"]["refused"], &(&1["kind"] == "receipt"))
    end

    test "the tuple digest is byte-compatible with the stop court's Python encoding", ctx do
      assert order(run!(ctx), "T-A")["tuple_digest"] == @t_a_tuple_digest

      assert Graph.tuple_digest(%{
               "subject" => "fixture:order-a",
               "postcondition" => "Order A postcondition.",
               "capability" => "recipe:fixture-a",
               "evidence_ceiling" => "EXECUTED_VERIFIED",
               "authority_ceiling" => "CONSTRUCT",
               "consequence_class" => "verification",
               "exclusions" => ["No LLM on the path.", "Another exclusion."]
             }) == @t_a_tuple_digest
    end
  end

  describe "run/1 TransitionLog (frontier_from_events/3)" do
    # Independent of the product: the sha256 of the receipt file bytes.
    defp file_digest(path),
      do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

    # TransitionLog's event_digest omits receipt_digest and definition_digest
    # (SemanticJira.digest/1 drops them), so two events that differ only
    # there are one event; a test that needs both writes a second ledger.
    defp transition!(ledger, id, definition, to, receipt_digest) do
      {:ok, _event, :appended} =
        TransitionLog.append(ledger, %{
          "kind" => "standing_transition_event",
          "identity" => id,
          "definition_digest" => definition,
          "from" => "UNKNOWN",
          "to" => to,
          "receipt_digest" => receipt_digest,
          "authority" => "NONE"
        })
    end

    defp inapplicable(result),
      do: Enum.map(result.state["ledger"]["inapplicable"], &{&1["identity"], &1["reason"]})

    test "a ledger ALIVE with no current receipt behind it confers nothing; a stale definition neither",
         ctx do
      File.rm!(Path.join(ctx.receipts, "T-A.json"))
      before = run!(ctx)
      definition = order(before, "T-A")["definition_digest"]
      assert order(before, "T-B")["frontier"] == "blocked"

      # a fabricated receipt digest: no receipt file has these bytes
      transition!(ctx.ledger, "T-A", definition, "ALIVE", "sha256:" <> String.duplicate("a", 64))

      transition!(
        ctx.ledger,
        "T-B",
        "sha256:" <> String.duplicate("b", 64),
        "ALIVE",
        "sha256:" <> String.duplicate("c", 64)
      )

      result = run!(ctx)

      assert %{"standing" => "UNKNOWN", "standing_source" => "none", "frontier" => "eligible"} =
               order(result, "T-A")

      assert order(result, "T-A") == order(before, "T-A")
      assert order(result, "T-B")["frontier"] == "blocked"
      assert order(result, "T-B")["frontier_reason"] == "dependencies_unsatisfied"
      assert %{"events" => 2, "applied" => 0, "present" => true} = result.state["ledger"]

      assert inapplicable(result) == [
               {"T-A", "receipt_digest_unresolved"},
               {"T-B", "definition_digest_mismatch"}
             ]
    end

    test "a ledger event bound to a current receipt applies; deleting the receipt (F5) or a covered-path commit (F6) withdraws it",
         ctx do
      receipt_path = Path.join(ctx.receipts, "T-A.json")
      receipt_bytes = File.read!(receipt_path)
      receipt_digest = file_digest(receipt_path)
      before = run!(ctx)
      assert order(before, "T-A")["receipt"]["sha256"] == receipt_digest
      definition = order(before, "T-A")["definition_digest"]

      transition!(ctx.ledger, "T-A", definition, "ALIVE", receipt_digest)
      # the same receipt does not carry BLOCKED: this event confers nothing
      transition!(ctx.ledger, "T-A", definition, "BLOCKED", receipt_digest)

      bound = run!(ctx)

      assert %{"standing" => "ALIVE", "standing_source" => "ledger", "frontier" => "settled"} =
               order(bound, "T-A")

      assert order(bound, "T-B")["frontier"] == "eligible"
      assert %{"events" => 2, "applied" => 1} = bound.state["ledger"]
      assert inapplicable(bound) == [{"T-A", "receipt_standing_mismatch"}]

      # F5: the receipt the event names is deleted -> the event is unresolved
      File.rm!(receipt_path)
      deleted = run!(ctx)

      assert %{"standing" => "UNKNOWN", "standing_source" => "none", "frontier" => "eligible"} =
               order(deleted, "T-A")

      assert order(deleted, "T-B")["frontier"] == "blocked"
      assert %{"applied" => 0} = deleted.state["ledger"]

      assert inapplicable(deleted) == [
               {"T-A", "receipt_digest_unresolved"},
               {"T-A", "receipt_digest_unresolved"}
             ]

      # restoring the same bytes restores the binding
      File.write!(receipt_path, receipt_bytes)
      assert run!(ctx).digest == bound.digest

      # F6: a commit on the covered path invalidates the receipt -> not current
      advanced =
        commit!(ctx.repo, "lib/a.ex", "defmodule A do\n  def f6, do: :ok\nend\n", "lib: advance")

      stale = run!(ctx)
      t_a = order(stale, "T-A")

      assert %{"standing" => "UNKNOWN", "standing_source" => "none", "frontier" => "eligible"} =
               t_a

      assert [
               %{
                 "reason" => "subject_advanced",
                 "sha256" => ^receipt_digest,
                 "current_covered_commit" => ^advanced
               }
             ] = t_a["invalidated"]

      assert order(stale, "T-B")["frontier"] == "blocked"
      assert %{"applied" => 0} = stale.state["ledger"]

      assert inapplicable(stale) == [
               {"T-A", "receipt_not_current"},
               {"T-A", "receipt_not_current"}
             ]
    end

    test "a ledger UNKNOWN (a demotion) applies without a receipt and returns the order to the frontier",
         ctx do
      definition = order(run!(ctx), "T-A")["definition_digest"]
      transition!(ctx.ledger, "T-A", definition, "UNKNOWN", nil)
      result = run!(ctx)

      assert %{"standing" => "UNKNOWN", "standing_source" => "ledger", "frontier" => "eligible"} =
               order(result, "T-A")

      assert %{"applied" => 1, "inapplicable" => []} = result.state["ledger"]
      assert order(result, "T-B")["frontier"] == "blocked"
    end

    # T-C carries sj:candidateSha = the first covered commit; its receipt is
    # re-bound to each new covered commit so the receipt stays current while
    # only the candidate goes stale.
    defp candidate_graph!(ctx) do
      path = Path.join(ctx.dir, "candidate-order.ttl")

      File.write!(path, """
      @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
      @prefix t: <https://ggen-igniter.dev/sjira/bootstrap-fixture#> .
      @prefix dcterms: <http://purl.org/dc/terms/> .
      t:cap-c a sj:Capability ; sj:capabilityId "recipe:fixture-c" .
      t:WO-T-C a sj:WorkOrder ;
        dcterms:identifier "T-C" ; dcterms:title "Fixture order C" ;
        dcterms:description "Carries a candidate SHA over lib/." ;
        sj:repository "fixture/subject" ;
        sj:baseSha "1111111111111111111111111111111111111111" ;
        sj:candidateSha "#{ctx.covered}" ;
        sj:subject "fixture:order-c" ; sj:pathScope "lib/" ;
        sj:evidenceCeiling "EXECUTED_VERIFIED" ; sj:authorityCeiling "CONSTRUCT" ;
        sj:authorityRequirement "NONE" ;
        sj:promotionRule "Standing advances only from receipts." ;
        sj:replayIdentity "semantic-jira:fixture:T-C" ;
        sj:requiresCourt t:court-T-C ; sj:requiresEvidence sj:receipt-evidence ;
        sj:requiresReceiptClass "verification" ; sj:acceptance t:acceptance-T-C ;
        sj:falsifier t:falsifier-T-C ; sj:projection sj:markdown-projection ;
        sj:checkpointOf t:G-1 ; sj:originAuthority sj:objective-code-work-authority ;
        sj:postcondition "Order C postcondition." ;
        sj:requiresCapability t:cap-c ; sj:evidenceHorizon "EXECUTED_VERIFIED" ;
        sj:consequenceClass "verification" ;
        sj:successorPolicy "discovered work -> t:GC-T-next" .
      """)

      path
    end

    test "an ALIVE event of an order with sj:candidateSha applies only while the candidate covers its scope",
         ctx do
      graph = candidate_graph!(ctx)
      first = order(run!(ctx, graphs: [graph]), "T-C")
      assert "sha256:" <> _ = tuple = first["tuple_digest"]
      definition = first["definition_digest"]
      receipt_path = Path.join(ctx.receipts, "T-C.json")

      File.write!(receipt_path, Jason.encode!(receipt(ctx.covered, "ALIVE", tuple, "T-C")))
      transition!(ctx.ledger, "T-C", definition, "ALIVE", file_digest(receipt_path))

      assert %{"standing" => "ALIVE", "standing_source" => "ledger"} =
               order(run!(ctx, graphs: [graph]), "T-C")

      # the covered path advances; the receipt is re-bound to the new commit
      # (current), the candidate SHA is not
      advanced =
        commit!(ctx.repo, "lib/a.ex", "defmodule A do\n  def c, do: :ok\nend\n", "lib: advance")

      File.write!(receipt_path, Jason.encode!(receipt(advanced, "ALIVE", tuple, "T-C")))

      # the first event names the replaced receipt bytes: unresolved; the
      # current receipt alone confers ALIVE
      rebound = run!(ctx, graphs: [graph])

      assert %{"standing" => "ALIVE", "standing_source" => "receipt", "invalidated" => []} =
               order(rebound, "T-C")

      assert order(rebound, "T-C")["receipt"]["subject_sha"] == advanced

      assert Enum.filter(inapplicable(rebound), &(elem(&1, 0) == "T-C")) == [
               {"T-C", "receipt_digest_unresolved"}
             ]

      # an ALIVE event bound to the CURRENT receipt is still refused, because
      # the order's candidate SHA no longer covers lib/ at HEAD
      ledger2 = Path.join(ctx.dir, "ledger2/standing-ledger.ndjson")
      transition!(ledger2, "T-C", definition, "ALIVE", file_digest(receipt_path))
      result = run!(ctx, graphs: [graph], ledger: ledger2)

      assert %{"standing" => "ALIVE", "standing_source" => "receipt"} = order(result, "T-C")
      assert %{"events" => 1, "applied" => 0} = result.state["ledger"]
      assert inapplicable(result) == [{"T-C", "candidate_subject_advanced"}]
    end

    test "a tampered ledger is refused", ctx do
      {:ok, _event, :appended} =
        TransitionLog.append(ctx.ledger, %{
          "identity" => "T-A",
          "to" => "ALIVE",
          "from" => "UNKNOWN"
        })

      File.write!(ctx.ledger, String.replace(File.read!(ctx.ledger), "ALIVE", "BLOCKED"))

      assert {:refused, [%{code: :ledger_refused}]} = Bootstrap.run(opts(ctx))
    end
  end

  describe "run/1 forbidden dependencies (ARD section 16)" do
    test "paths under .claude / .zcode, transcript paths and symlinks to them are refused", ctx do
      claude = Path.join(ctx.dir, ".claude/projects")
      File.mkdir_p!(claude)
      File.cp!(@fixture_goal, Path.join(claude, "goal.ttl"))
      zcode = Path.join(ctx.dir, ".zcode/receipts")
      File.mkdir_p!(zcode)
      transcripts = Path.join(ctx.dir, "session-transcripts")
      File.mkdir_p!(transcripts)
      link = Path.join(ctx.dir, "innocent.ttl")
      File.ln_s!(Path.join(claude, "goal.ttl"), link)

      for {extra, role} <- [
            {[goal: Path.join(claude, "goal.ttl")], "goal"},
            {[goal: link], "goal"},
            {[receipts_dirs: [zcode]], "receipts_dir"},
            {[ledger: Path.join(transcripts, "log.ndjson")], "ledger"},
            {[graphs: [Path.join(claude, "goal.ttl")]], "graphs"}
          ] do
        assert {:refused, refusals} = Bootstrap.run(opts(ctx, extra))
        assert [%{code: :forbidden_input, subject: ^role}] = refusals
      end
    end

    test "a forbidden file inside an allowed receipts directory is refused", ctx do
      claude = Path.join(ctx.dir, ".claude")
      File.mkdir_p!(claude)
      File.write!(Path.join(claude, "memory.json"), "{}")
      File.ln_s!(Path.join(claude, "memory.json"), Path.join(ctx.receipts, "planted.json"))

      assert {:refused, [%{code: :forbidden_input, detail: detail}]} = Bootstrap.run(opts(ctx))
      assert detail =~ ".claude"
    end

    test "LLM credential variables are refused by name, never by value", ctx do
      env = %{"ZAI_API_KEY" => "secret-value", "OPENAI_API_KEY" => "x", "PATH" => "/usr/bin"}

      assert {:refused, [%{code: :llm_credential_present, detail: detail}]} =
               Bootstrap.run(opts(ctx, env: env))

      assert detail =~ "OPENAI_API_KEY, ZAI_API_KEY"
      assert detail =~ "mu_on_O"
      refute detail =~ "secret-value"
    end
  end

  describe "run/1 tuple contract (sj:exclusion is 0..n)" do
    test "an order with no sj:exclusion digests exclusions = [] and its receipt links", ctx do
      graph = extra_graph!(ctx)

      File.write!(
        Path.join(ctx.receipts, "T-Z.json"),
        Jason.encode!(receipt(ctx.covered, "ALIVE", @t_z_tuple_digest, "T-Z"))
      )

      result = run!(ctx, graphs: [graph])
      t_z = order(result, "T-Z")

      assert %{"tuple" => "complete", "tuple_digest" => @t_z_tuple_digest} = t_z
      assert %{"standing" => "ALIVE", "standing_source" => "receipt", "unlinked" => []} = t_z
      assert t_z["receipt"]["ref"] == "fixture/subject:receipts/T-Z.json"
      assert t_z["critical_path"] == true
      assert result.state["authority"]["orders"]["T-Z"]["exclusions"] == []

      assert Graph.tuple_digest(%{
               "subject" => "fixture:order-z",
               "postcondition" => "Order Z postcondition.",
               "capability" => "recipe:fixture-z",
               "evidence_ceiling" => "EXECUTED_VERIFIED",
               "authority_ceiling" => "CONSTRUCT",
               "consequence_class" => "verification",
               "exclusions" => []
             }) == @t_z_tuple_digest
    end
  end

  describe "run/1 receipt directories" do
    test "an absent receipts dir is recorded as absent in the state inputs", ctx do
      missing = Path.join(ctx.dir, "missing-receipts")
      result = run!(ctx, receipts_dirs: [ctx.receipts, missing])

      assert %{"status" => "read", "receipts" => 1} =
               input(result, "receipts_dir", "fixture/subject:receipts")

      assert %{"status" => "absent", "receipts" => 0} =
               input(result, "receipts_dir", "receipts-dir-1:missing-receipts")

      assert order(result, "T-A")["standing"] == "ALIVE"
      assert result.digest != run!(ctx).digest
    end

    test "a receipts dir that is a file, or unreadable, or holds an unreadable receipt is refused",
         ctx do
      file = Path.join(ctx.dir, "not-a-dir.json")
      File.write!(file, "{}")

      assert {:refused, [%{code: :input_unreadable, subject: subject, detail: detail}]} =
               Bootstrap.run(opts(ctx, receipts_dirs: [ctx.receipts, file]))

      assert subject == "receipts-dir-1:not-a-dir.json"
      assert detail =~ "not a directory"

      locked = Path.join(ctx.dir, "locked-receipts")
      File.mkdir_p!(locked)
      File.chmod!(locked, 0o000)

      try do
        assert {:refused, [%{code: :input_unreadable, detail: detail}]} =
                 Bootstrap.run(opts(ctx, receipts_dirs: [locked]))

        assert detail =~ "permission denied"
      after
        File.chmod!(locked, 0o755)
      end

      unreadable = Path.join(ctx.receipts, "T-A.json")
      File.chmod!(unreadable, 0o000)

      try do
        assert {:refused, [%{code: :input_unreadable, subject: subject, detail: detail}]} =
                 Bootstrap.run(opts(ctx))

        assert subject == "fixture/subject:receipts/T-A.json"
        assert detail =~ "permission denied"
      after
        File.chmod!(unreadable, 0o644)
      end
    end

    test "a *.json entry that is not a readable file (dangling symlink, directory) is refused, not skipped",
         ctx do
      dangling = Path.join(ctx.receipts, "dangling.json")
      File.ln_s!(Path.join(ctx.dir, "gone.json"), dangling)

      assert {:refused, [%{code: :input_unreadable, subject: subject, detail: detail}]} =
               Bootstrap.run(opts(ctx))

      assert subject == "fixture/subject:receipts/dangling.json"
      assert detail =~ "no such file or directory"

      File.rm!(dangling)
      File.mkdir_p!(Path.join(ctx.receipts, "nested.json"))

      assert {:refused, [%{code: :input_unreadable, subject: subject}]} = Bootstrap.run(opts(ctx))
      assert subject == "fixture/subject:receipts/nested.json"
    end
  end

  describe "run/1 covered-path currency reasons" do
    test "a scope no commit ever touched invalidates as scope_never_committed", ctx do
      graph = extra_graph!(ctx)
      digest = order(run!(ctx, graphs: [graph]), "T-N")["tuple_digest"]
      assert "sha256:" <> _ = digest

      File.write!(
        Path.join(ctx.receipts, "T-N.json"),
        Jason.encode!(receipt(ctx.covered, "ALIVE", digest, "T-N"))
      )

      t_n = order(run!(ctx, graphs: [graph]), "T-N")

      assert %{
               "standing" => "UNKNOWN",
               "receipt" => nil,
               "covered_commit" => nil,
               "covered_commit_status" => "none_in_scope",
               "frontier" => "eligible"
             } = t_n

      assert [
               %{
                 "reason" => "scope_never_committed",
                 "receipt_covered_commit" => nil,
                 "current_covered_commit" => nil
               }
             ] = t_n["invalidated"]
    end

    test "an unreadable current covered commit is reported as such, not as subject_advanced",
         ctx do
      # Remove the root tree object of the commit between the receipt's
      # subject and HEAD: `git log -1 HEAD -- lib/` must read it and fails,
      # while the receipt's own subject history stays readable.
      tree = git!(ctx.repo, ["rev-parse", "HEAD~1^{tree}"])
      {prefix, rest} = String.split_at(tree, 2)
      File.rm!(Path.join([ctx.repo, ".git", "objects", prefix, rest]))

      t_a = order(run!(ctx), "T-A")

      assert %{
               "standing" => "UNKNOWN",
               "receipt" => nil,
               "covered_commit" => nil,
               "covered_commit_status" => "unreadable"
             } = t_a

      assert [
               %{
                 "reason" => "current_covered_commit_unreadable",
                 "receipt_covered_commit" => covered,
                 "current_covered_commit" => nil
               }
             ] = t_a["invalidated"]

      assert covered == ctx.covered
    end

    test "the unreadable corruption stays unreadable when a changed-path commit-graph exists",
         ctx do
      # CI run 35933570910 (git 2.55.0): the case above saw "observed". With
      # changed-path Bloom filters in a commit-graph, `git log -1 HEAD -- lib/`
      # skips the commits that did not touch lib/ WITHOUT reading their trees,
      # so deleting HEAD~1's root tree no longer makes the read fail. Write
      # such a graph explicitly, then corrupt exactly as above.
      git!(ctx.repo, ["commit-graph", "write", "--reachable", "--changed-paths"])
      tree = git!(ctx.repo, ["rev-parse", "HEAD~1^{tree}"])
      {prefix, rest} = String.split_at(tree, 2)
      File.rm!(Path.join([ctx.repo, ".git", "objects", prefix, rest]))

      t_a = order(run!(ctx), "T-A")
      assert %{"covered_commit" => nil, "covered_commit_status" => "unreadable"} = t_a
    end

    test "an observed covered commit is reported with its status", ctx do
      t_a = order(run!(ctx), "T-A")
      assert %{"covered_commit_status" => "observed", "standing" => "ALIVE"} = t_a
      assert t_a["covered_commit"] == ctx.covered
    end
  end

  describe "run/1 fleet matrix form" do
    test "non-required matrix rows keep their recorded SHA; required and checkout rows are live",
         ctx do
      matrix = Path.join(ctx.dir, "matrix.ttl")

      File.write!(matrix, """
      @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
      @prefix dcterms: <http://purl.org/dc/terms/> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      <urn:row:subject> a sj:FleetMatrixRow ; dcterms:identifier "subject" ;
        sj:repositoryPath "#{ctx.repo}" ; sj:fleetClass sj:CriticalPath ;
        sj:requiredForCheckpoint true ; sj:observedSha "#{ctx.covered}" .
      <urn:row:elsewhere> a sj:FleetMatrixRow ; dcterms:identifier "elsewhere" ;
        sj:repositoryPath "#{Path.join(ctx.dir, "absent")}" ; sj:fleetClass sj:Refused ;
        sj:requiredForCheckpoint false ; sj:observedSha "#{String.duplicate("d", 40)}" .
      """)

      result = run!(ctx, fleet: matrix, checkouts: [])
      subjects = Map.new(result.state["subjects"], &{&1["name"], &1})

      assert %{"status" => "observed", "head_sha" => head, "class" => "CriticalPath"} =
               subjects["subject"]

      assert head == ctx.receipt_commit

      assert %{"status" => "recorded", "head_sha" => nil, "recorded_sha" => recorded} =
               subjects["elsewhere"]

      assert recorded == String.duplicate("d", 40)

      assert %{"kind" => "fleet", "id" => "elsewhere", "class" => "Refused"} in result.state[
               "exceptions"
             ]["refused"]

      # T-A still resolves its repository through the matrix row name
      assert order(result, "T-A")["standing"] == "ALIVE"
    end
  end

  describe "run/1 origin authority (SJ-002)" do
    test "work_orders.rq extracts sj:originAuthority for every order into fields and kernel" do
      {:ok, graph} = Graph.parse(File.read!(@fixture_goal))
      {:ok, queries} = Graph.read_queries(@pack_dir)

      orders = Graph.orders(graph, queries, @fixture_goal)
      assert Enum.map(orders, & &1.id) == ["T-A", "T-B", "T-S"]

      for order <- orders do
        # IRI-valued row stringified by Graph.term/1, like checkpoint_of
        assert order.fields["origin_authority"] == [@origin_iri]
        assert order.kernel["origin_authority"] == @origin_iri
      end
    end

    test "an order without sj:originAuthority is blocked by kernel admission naming the field",
         ctx do
      goal = Path.join(ctx.dir, "no-origin-goal.ttl")

      File.write!(
        goal,
        Regex.replace(~r/^    sj:originAuthority [^\n]*;\n/m, File.read!(@fixture_goal), "",
          global: false
        )
      )

      t_a = order(run!(ctx, goal: goal), "T-A")

      assert %{"frontier" => "blocked", "frontier_reason" => reason} = t_a
      assert reason =~ "origin_authority"
    end
  end

  describe "scripts/sjira/bootstrap_court.sh" do
    defp court!(ctx, extra_env) do
      env =
        [
          "PATH=#{court_path()}",
          "HOME=#{System.user_home!()}",
          "TMPDIR=#{ctx.dir}",
          "GGEN_IGNITER_DIR=#{File.cwd!()}",
          "XAAS_DIR=#{ctx.dir}",
          "BOOTSTRAP_GOAL=#{@fixture_goal}",
          "BOOTSTRAP_FLEET=#{ctx.universe}",
          "BOOTSTRAP_GRAPHS=",
          "BOOTSTRAP_RECEIPTS_DIRS=#{ctx.receipts}",
          "BOOTSTRAP_LEDGER=#{ctx.ledger}",
          "BOOTSTRAP_CHECKOUTS=#{@repository}=#{ctx.repo}",
          "BOOTSTRAP_MIX_ENV=test",
          "BOOTSTRAP_OUT_DIR=#{Path.join(ctx.dir, "court")}"
        ] ++ extra_env

      System.cmd("env", ["-i" | env] ++ ["sh", Path.expand("scripts/sjira/bootstrap_court.sh")],
        stderr_to_stdout: true
      )
    end

    test "passes on two identical cold runs reconstructing every critical-path order", ctx do
      {log, code} = court!(ctx, [])
      assert code == 0, log
      assert log =~ "OK: GC23-1 two cold bootstrap runs byte-identical"
      assert log =~ "critical-path orders reconstructed: T-A T-B"
      refute log =~ "T-S"

      assert File.read!(Path.join(ctx.dir, "court/run1/state.json")) ==
               File.read!(Path.join(ctx.dir, "court/run2/state.json"))
    end

    test "refuses an LLM credential in its environment and reports absent machinery", ctx do
      {log, code} = court!(ctx, ["CLAUDE_CODE_SESSION_ID=fixture"])
      assert code == 1
      assert log =~ "REFUSED(llm_credential_present) GC23-1"

      {log, code} = court!(ctx, ["GGEN_IGNITER_DIR=#{ctx.dir}"])
      assert code == 75
      assert log =~ "UNKNOWN: GC23-1 machinery lands in lane V23-B"
    end
  end
end
