defmodule GgenIgniter.SemanticJiraProseTest do
  @moduledoc """
  Chicago-style: proof of the first-mile compiler (GC-26.9.23 GC23-0 / GC23-2;
  PRD PR-002..PR-005, ARD sections 5 and 17), `GgenIgniter.SemanticJira.Prose`
  and `mix semantic_jira.compile_prose`.

  Real collaborators only: the committed fixture prose, candidates and goal
  under `test/fixtures/semantic-jira-prose/` (the candidates were emitted by
  the real xaas `scripts/sjira/prose_spans.py emit` from `extract.json`),
  copied into unique tmp trees and mutated as real files; the real pack
  ontology, `shapes/*.shacl.ttl` and `prose/*.rq` rules; the real
  `GgenIgniter.SemanticJira.Shacl` court; real R-schema receipt JSON files in
  a real receipts dir; and real `mix semantic_jira.compile_prose`
  subprocesses (with every LLM credential variable unset). No mocks, stubs or
  test doubles.
  """

  # async: false -- the CLI subprocesses share this checkout's _build.
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.SemanticJira.{Prose, Shacl}

  @fixture_dir "test/fixtures/semantic-jira-prose"
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @work_order_shapes "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @ns "https://ggen-igniter.dev/sjira/fixture-prose#"
  @source_sha "sha256:a08df167fb31a4493373cd19c70249acc722cdc5e8253c2632a3aa461380f5d6"

  # Fixture propositions (IRIs recompute per PVOCAB from the committed spans).
  @actor @ns <> "P-93e73ffcc7345c79"
  @format_post @ns <> "P-a9d665f1e22ef256"
  @invariant @ns <> "P-cd9ee31a70d470ae"
  @exclusion @ns <> "P-e3a10ad82ca48d34"
  @replay_post @ns <> "P-e169d0fdca152ff4"
  @falsifier @ns <> "P-83afd960b0459690"
  @metric @ns <> "P-d5f6ba90710b016d"
  @root_post @ns <> "P-05d08155a5fcc6c8"
  @successor @ns <> "P-f22085da12196d3b"

  @all [
    @actor,
    @format_post,
    @invariant,
    @exclusion,
    @replay_post,
    @falsifier,
    @metric,
    @root_post,
    @successor
  ]
  @delta [@format_post, @invariant, @replay_post, @falsifier, @root_post]

  # F1 table: every tuple field an emitted order must carry. Deleting any one
  # from an emitted order must make the FRI-T1 shapes refuse it, naming it.
  @f1_fields ~w(subject repository baseSha pathScope evidenceCeiling authorityCeiling postcondition
                requiresCapability evidenceHorizon consequenceClass successorPolicy acceptance
                falsifier requiresCourt)

  # sj:checkpointOf is what opts an order into the tuple (sj:FridayWorkOrderShape
  # targets its subjects), so it is asserted present but is not in the F1 table.
  @tuple_fields @f1_fields ++ ["checkpointOf"]

  @llm_env ~w(ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN OPENAI_API_KEY
              ZAI_API_KEY Z_AI_API_KEY GLM_API_KEY ZCODE_API_KEY)

  setup do
    tmp = Path.join(System.tmp_dir!(), "gi-prose-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  describe "compile/1 (admission + delta over the committed fixture)" do
    test "admits every candidate and manufactures one order per required unwitnessed delta proposition" do
      assert {:ok, result} = Prose.compile(fixture_opts())

      assert result.summary.admitted == 9
      assert result.summary.required == 7
      assert result.summary.not_required == 2

      assert result.summary.required_by == %{
               "GC-PROSE" => 1,
               "GCP-0" => 3,
               "GCP-1" => 2,
               "GCP-2" => 1
             }

      assert result.summary.delta_required == 5
      assert result.summary.orders == 5

      assert order_iris(result) == MapSet.new(@delta, &Prose.order_iri(@ns, &1))

      admitted = RDF.Turtle.read_string!(result.propositions_ttl)
      assert length(instances(admitted, "Proposition")) == 9
      assert objects(admitted, "candidateStanding") == []
      assert length(objects(admitted, "admissionDigest")) == 9
      assert Enum.all?(objects(admitted, "admissionDigest"), &(&1 =~ ~r/\Asha256:[0-9a-f]{64}\z/))
    end

    test "every emitted order carries the full FRI-T1 tuple, the gate's admitted exclusions and resolved capability" do
      assert {:ok, result} = Prose.compile(fixture_opts())
      orders = RDF.Turtle.read_string!(result.orders_ttl)

      for proposition <- @delta do
        order = RDF.iri(Prose.order_iri(@ns, proposition))
        description = RDF.Graph.get(orders, order)
        assert description, "no order for #{proposition}"

        for field <- @tuple_fields do
          assert RDF.Description.get(description, RDF.iri(@sj <> field), []) != [],
                 "#{proposition}'s order lacks sj:#{field}"
        end

        assert value(description, "subject") == proposition
        assert value(description, "authorityCeiling") == "CONSTRUCT"
        assert value(description, "standing") == "UNKNOWN"
      end

      format_order = RDF.Graph.get(orders, RDF.iri(Prose.order_iri(@ns, @format_post)))

      assert value(format_order, "postcondition") ==
               "The formatter check exits 0 on the exact subject."

      assert value(format_order, "checkpointOf") == @ns <> "GCP-0"
      assert value(format_order, "consequenceClass") == "verification"
      assert value(format_order, "requiresCapability") == @ns <> "cap-recipe-mix-format"
      assert value(format_order, "falsifier") == @format_post <> "-falsifier-1"

      assert values(format_order, "exclusion") == [
               "Network access during the episode is not permitted."
             ]

      invariant_order = RDF.Graph.get(orders, RDF.iri(Prose.order_iri(@ns, @invariant)))
      assert value(invariant_order, "consequenceClass") == "manufacture"

      assert values(invariant_order, "exclusion") == [
               "Network access during the episode is not permitted."
             ]

      unassigned = RDF.Graph.get(orders, RDF.iri(value(invariant_order, "requiresCapability")))
      assert value(unassigned, "capabilityId") == "construct:unassigned"
      assert value(unassigned, "standing") == "UNKNOWN"

      replay_order = RDF.Graph.get(orders, RDF.iri(Prose.order_iri(@ns, @replay_post)))
      assert values(replay_order, "exclusion") == []

      root_order = RDF.Graph.get(orders, RDF.iri(Prose.order_iri(@ns, @root_post)))
      assert value(root_order, "checkpointOf") == @ns <> "GC-PROSE"

      assert value(root_order, "successorPolicy") ==
               "Discovered work that falsifies no GC-PROSE proposition is typed Successor under fx:GC-PROSE-NEXT."
    end

    test "a second run is byte-identical and check/2 confirms written outputs", %{tmp: tmp} do
      assert {:ok, first} = Prose.compile(fixture_opts())
      assert {:ok, second} = Prose.compile(fixture_opts())

      assert first.propositions_ttl == second.propositions_ttl
      assert first.orders_ttl == second.orders_ttl

      out = Path.join(tmp, "out")
      Prose.write!(first, out)
      assert :ok = Prose.check(second, out)

      File.write!(Path.join(out, "orders.ttl"), first.orders_ttl <> "\n")
      assert {:refused, [refusal]} = Prose.check(second, out)
      assert refusal.code == :output_drift
      assert refusal.subject == Path.join(out, "orders.ttl")
    end
  end

  describe "compile/1 provenance admission (step a)" do
    test "one changed source byte refuses every proposition and the root, each by IRI", %{
      tmp: tmp
    } do
      opts =
        fixture_copy(tmp,
          source: [{"exits 0 on the exact subject", "exits 1 on the exact subject"}]
        )

      assert {:refused, refusals} = Prose.compile(opts)

      for proposition <- @all do
        assert Enum.any?(
                 refusals,
                 &(&1.code == :provenance_mismatch and &1.subject == proposition and
                     &1.detail =~ "sj:sourceSha256")
               ),
               "#{proposition} was not refused for the source digest"
      end

      assert Enum.any?(
               refusals,
               &(&1.subject == @ns <> "GC-PROSE" and &1.code == :provenance_mismatch)
             )
    end

    test "a changed sj:sourceText refuses exactly that proposition", %{tmp: tmp} do
      opts =
        fixture_copy(tmp,
          candidates: [
            {~s(sj:sourceText "No LLM runs on the KNOWN path."),
             ~s(sj:sourceText "No LLM runs on any path.")}
          ]
        )

      assert {:refused, refusals} = Prose.compile(opts)
      assert [%{code: :provenance_mismatch, subject: @invariant} = refusal] = provenance(refusals)
      assert refusal.detail =~ "!= sj:sourceText"
    end

    test "a shifted offset refuses the proposition (span bytes and IRI no longer recompute)", %{
      tmp: tmp
    } do
      opts = fixture_copy(tmp, candidates: [{"sj:sourceStart 258 ;", "sj:sourceStart 259 ;"}])

      assert {:refused, refusals} = Prose.compile(opts)
      mismatches = provenance(refusals)
      assert Enum.all?(mismatches, &(&1.subject == @invariant))
      assert Enum.any?(mismatches, &(&1.detail =~ "!= sj:sourceText"))
      assert Enum.any?(mismatches, &(&1.detail =~ "IRI does not recompute"))
    end

    test "a renamed candidate IRI refuses (the IRI must recompute per PVOCAB)", %{tmp: tmp} do
      opts =
        fixture_copy(tmp, candidates: [{"fx:P-cd9ee31a70d470ae a", "fx:P-0000000000000000 a"}])

      assert {:refused, refusals} = Prose.compile(opts)
      assert [refusal] = provenance(refusals)
      assert refusal.subject == @ns <> "P-0000000000000000"
      assert refusal.detail == "IRI does not recompute per PVOCAB: expected #{@invariant}"
    end

    test "an anonymous (blank-node) candidate has no identity and is refused", %{tmp: tmp} do
      anonymous =
        exclusion_candidate("Replays never reach an LLM provider.")
        |> String.replace(~r/<[^>]+> a sj:Proposition/, "[] a sj:Proposition", global: false)

      assert anonymous =~ "[] a sj:Proposition"

      assert {:refused, refusals} =
               Prose.compile(fixture_copy(tmp, candidates: [{:append, anonymous}]))

      assert Enum.any?(refusals, fn refusal ->
               refusal.code == :provenance_mismatch and String.starts_with?(refusal.subject, "_:") and
                 refusal.detail =~ "IRI does not recompute"
             end)
    end

    test "a candidate file cannot smuggle a non-proposition subject past admission", %{tmp: tmp} do
      smuggled = """

      fx:WO-SMUGGLED a sj:WorkOrder ;
          sj:subject "work nobody admitted" .
      """

      opts = fixture_copy(tmp, candidates: [{:append, smuggled}])

      assert {:refused, refusals} = Prose.compile(opts)

      assert Enum.any?(
               refusals,
               &(&1.code == :foreign_subject and &1.subject == @ns <> "WO-SMUGGLED")
             )
    end
  end

  describe "compile/1 SHACL and domain admission (steps b, c)" do
    test "a kind outside the ARD 5.2 list is refused by the proposition shape", %{tmp: tmp} do
      {start, stop} = {465, 506}
      wish = Prose.proposition_iri(@ns, @source_sha, start, stop, "Wish")

      opts =
        fixture_copy(tmp,
          candidates: [
            {"fx:P-d5f6ba90710b016d a", "<#{wish}> a"},
            {~s(sj:propositionKind "Metric"), ~s(sj:propositionKind "Wish")}
          ]
        )

      assert {:refused, refusals} = Prose.compile(opts)
      assert provenance(refusals) == []

      assert Enum.any?(refusals, fn refusal ->
               refusal.code == :shacl_violation and refusal.subject == wish and
                 refusal.detail =~ "#{@sj}propositionKind pattern"
             end)
    end

    test "an uncovered gate is refused by name", %{tmp: tmp} do
      gate = """

      fx:GCP-3 a sj:GoalCheckpoint ;
          dcterms:identifier "GCP-3" ;
          rdfs:label "GCP-3 unprosed gate" ;
          dcterms:description "A gate no admitted proposition requires." ;
          sj:checkpointOf fx:GC-PROSE ;
          sj:boundaryClass sj:Core ;
          sj:courtCommand "sh courts/GCP-3.sh" .
      """

      opts = fixture_copy(tmp, goal: [{:append, gate}])

      assert {:refused, [refusal]} = Prose.compile(opts)
      assert refusal.code == :uncovered_gate
      assert refusal.subject == @ns <> "GCP-3"
    end

    test "an Exclusion that restates a required Postcondition of the same gate is a contradiction",
         %{tmp: tmp} do
      contradicting =
        exclusion_candidate("Two replays of the compiler produce byte-identical outputs.")

      statement_ok = exclusion_candidate("Replays never reach an LLM provider.")

      assert {:refused, [refusal]} =
               Prose.compile(
                 fixture_copy(Path.join(tmp, "a"), candidates: [{:append, contradicting}])
               )

      assert refusal.code == :contradiction
      assert refusal.subject == Prose.proposition_iri(@ns, @source_sha, 342, 401, "Exclusion")
      assert refusal.detail =~ @replay_post

      # Anti-vacuity: the same added Exclusion with a different statement admits.
      assert {:ok, result} =
               Prose.compile(
                 fixture_copy(Path.join(tmp, "b"), candidates: [{:append, statement_ok}])
               )

      assert result.summary.admitted == 10
    end

    test "a proposition required by a checkpoint outside the root's gates is refused", %{tmp: tmp} do
      opts =
        fixture_copy(tmp,
          candidates: [{"sj:requiredBy fx:GCP-2 ;", "sj:requiredBy fx:GC-PROSE-NEXT ;"}]
        )

      assert {:refused, refusals} = Prose.compile(opts)
      assert Enum.any?(refusals, &(&1.code == :foreign_requirement and &1.subject == @metric))
      assert Enum.any?(refusals, &(&1.code == :uncovered_gate and &1.subject == @ns <> "GCP-2"))
    end
  end

  describe "compile/1 finite delta against receipts (step d)" do
    test "an ALIVE receipt naming a proposition removes exactly its order; UNKNOWN witnesses nothing",
         %{tmp: tmp} do
      receipts = Path.join(tmp, "receipts")
      File.mkdir_p!(receipts)
      write_receipt!(receipts, "invariant.json", @invariant, "ALIVE")
      write_receipt!(receipts, "replay-unknown.json", @replay_post, "UNKNOWN")

      assert {:ok, result} = Prose.compile(fixture_opts(receipts_dir: receipts))

      assert result.summary.witnessed == 1
      assert result.summary.orders == 4
      assert order_iris(result) == MapSet.new(@delta -- [@invariant], &Prose.order_iri(@ns, &1))
    end

    test "an ALIVE gate receipt (subject <root>/<gate>) witnesses every proposition that gate requires",
         %{tmp: tmp} do
      receipts = Path.join(tmp, "receipts")
      File.mkdir_p!(receipts)
      write_receipt!(receipts, "GCP-1.json", "GC-PROSE/GCP-1", "ALIVE")

      assert {:ok, result} = Prose.compile(fixture_opts(receipts_dir: receipts))

      assert result.summary.orders == 3

      assert order_iris(result) ==
               MapSet.new([@format_post, @invariant, @root_post], &Prose.order_iri(@ns, &1))
    end

    test "a receipts dir that does not exist is refused, not treated as empty", %{tmp: tmp} do
      assert {:refused, [refusal]} =
               Prose.compile(fixture_opts(receipts_dir: Path.join(tmp, "missing")))

      assert refusal.code == :input_unreadable
    end
  end

  describe "emitted orders under the FRI-T1 WorkOrder shapes (GC23-3, falsifier F1)" do
    test "the emitted orders admit, merged with the pack ontology and the goal" do
      assert {:ok, result} = Prose.compile(fixture_opts())
      report = validate_orders(RDF.Turtle.read_string!(result.orders_ttl))

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert "friday_work_order_shape" in report.shapes_checked
      assert "work_order_shape" in report.shapes_checked
    end

    test "dropping any tuple field from an emitted order is refused, naming the field" do
      assert {:ok, result} = Prose.compile(fixture_opts())
      orders = RDF.Turtle.read_string!(result.orders_ttl)
      order = RDF.iri(Prose.order_iri(@ns, @format_post))

      for field <- @f1_fields do
        predicate = RDF.iri(@sj <> field)
        dropped = RDF.Description.take(RDF.Graph.get(orders, order), [predicate])
        assert RDF.Description.count(dropped) >= 1

        report = validate_orders(RDF.Graph.delete(orders, dropped))

        refute report.conforms, "dropping sj:#{field} was admitted"

        assert Enum.any?(
                 report.violations,
                 &(&1.focus_node == RDF.IRI.to_string(order) and &1.path == @sj <> field)
               ),
               "dropping sj:#{field} was refused without naming it: #{inspect(report.violations, pretty: true)}"
      end
    end
  end

  describe "mix semantic_jira.compile_prose (real subprocess, no LLM credentials)" do
    test "writes outputs, --check confirms them, drift and refusals exit 1", %{tmp: tmp} do
      out = Path.join(tmp, "out")
      base = cli_args(fixture_opts()) ++ ["--out-dir", out]

      {output, status} = run_cli(base)
      assert status == 0, output
      assert output =~ "ADMITTED: 9 propositions (7 required, 2 not required)"
      assert output =~ "5 work orders"

      assert {:ok, result} = Prose.compile(fixture_opts())
      assert File.read!(Path.join(out, "orders.ttl")) == result.orders_ttl
      assert File.read!(Path.join(out, "propositions.ttl")) == result.propositions_ttl

      {check_output, check_status} = run_cli(base ++ ["--check"])
      assert check_status == 0, check_output
      assert check_output =~ "outputs recompute byte-identically"

      File.write!(Path.join(out, "propositions.ttl"), "# drift\n")
      {drift_output, drift_status} = run_cli(base ++ ["--check"])
      assert drift_status == 1
      assert drift_output =~ "REFUSED(output_drift)"

      refused_opts =
        fixture_copy(Path.join(tmp, "refused"),
          candidates: [{"sj:sourceStart 258 ;", "sj:sourceStart 259 ;"}]
        )

      {refused_output, refused_status} =
        run_cli(cli_args(refused_opts) ++ ["--out-dir", Path.join(tmp, "never")])

      assert refused_status == 1
      assert refused_output =~ "REFUSED(provenance_mismatch) #{@invariant}"
      refute File.exists?(Path.join(tmp, "never"))
    end
  end

  ## Helpers

  defp fixture_opts(extra \\ []) do
    [
      source: Path.join(@fixture_dir, "prose.md"),
      candidates: Path.join(@fixture_dir, "candidates.ttl"),
      goal: Path.join(@fixture_dir, "goal.ttl")
    ] ++ extra
  end

  # Copies the fixture into <tmp>/test/fixtures/semantic-jira-prose/ (so the
  # candidates' repo-relative sj:sourceDocument still names the prose file)
  # and applies each {from, to} replacement exactly once, or {:append, text}.
  defp fixture_copy(tmp, mutations) do
    dir = Path.join(tmp, @fixture_dir)
    File.mkdir_p!(dir)

    for {name, key} <- [
          {"prose.md", :source},
          {"candidates.ttl", :candidates},
          {"goal.ttl", :goal}
        ] do
      content =
        Enum.reduce(
          Keyword.get(mutations, key, []),
          File.read!(Path.join(@fixture_dir, name)),
          &mutate!/2
        )

      File.write!(Path.join(dir, name), content)
    end

    [
      source: Path.join(dir, "prose.md"),
      candidates: Path.join(dir, "candidates.ttl"),
      goal: Path.join(dir, "goal.ttl")
    ]
  end

  defp mutate!({:append, text}, content), do: content <> text

  defp mutate!({from, to}, content) do
    assert String.contains?(content, from), "fixture mutation target #{inspect(from)} not found"
    String.replace(content, from, to, global: false)
  end

  defp exclusion_candidate(statement) do
    iri = Prose.proposition_iri(@ns, @source_sha, 342, 401, "Exclusion")

    """

    <#{iri}> a sj:Proposition ;
        sj:propositionKind "Exclusion" ;
        sj:statement "#{statement}" ;
        sj:sourceDocument "test/fixtures/semantic-jira-prose/prose.md" ;
        sj:sourceSha256 "#{@source_sha}" ;
        sj:sourceStart 342 ;
        sj:sourceEnd 401 ;
        sj:sourceText "Two replays of the compiler produce byte-identical outputs." ;
        sj:boundaryClass sj:FirstMile ;
        sj:requiredBy fx:GCP-1 ;
        sj:candidateStanding "UNKNOWN" ;
        sj:extractedBy "fixture:hand-authored@V23-C" .
    """
  end

  defp write_receipt!(dir, name, subject, standing) do
    receipt = %{
      "identity" => %{
        "subject" => subject,
        "repo" => "seanchatmangpt/ggen_igniter",
        "subject_sha" => String.duplicate("a", 40),
        "base_sha" => String.duplicate("b", 40)
      },
      "authority" => %{"ceiling" => "CONSTRUCT", "grant" => "NONE", "actor" => "test"},
      "consequence" => %{"commits" => [], "files_changed" => [], "remote_effects" => []},
      "replay" => %{"commands" => [%{"cmd" => "true", "cwd" => ".", "exit" => 0}]},
      "standing" => %{"value" => standing, "derived_from" => "fixture court"}
    }

    File.write!(Path.join(dir, name), Jason.encode!(receipt))
  end

  defp validate_orders(orders) do
    @ontology_path
    |> RDF.Turtle.read_file!()
    |> RDF.Graph.add(RDF.Turtle.read_file!(Path.join(@fixture_dir, "goal.ttl")))
    |> RDF.Graph.add(orders)
    |> Shacl.validate(RDF.Turtle.read_file!(@work_order_shapes))
  end

  defp provenance(refusals), do: Enum.filter(refusals, &(&1.code == :provenance_mismatch))

  defp order_iris(result) do
    result.orders_ttl
    |> RDF.Turtle.read_string!()
    |> instances("WorkOrder")
    |> MapSet.new()
  end

  defp instances(graph, class) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.filter(&(RDF.iri(@sj <> class) in RDF.Description.get(&1, RDF.type(), [])))
    |> Enum.map(&RDF.IRI.to_string(&1.subject))
  end

  defp objects(graph, local) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.flat_map(&RDF.Description.get(&1, RDF.iri(@sj <> local), []))
    |> Enum.map(&to_string/1)
  end

  defp values(description, local) do
    description
    |> RDF.Description.get(RDF.iri(@sj <> local), [])
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp value(description, local) do
    case values(description, local) do
      [one] -> one
      other -> flunk("expected one sj:#{local}, got #{inspect(other)}")
    end
  end

  defp cli_args(opts) do
    [
      "semantic_jira.compile_prose",
      "--source",
      opts[:source],
      "--candidates",
      opts[:candidates],
      "--goal",
      opts[:goal]
    ]
  end

  defp run_cli(args) do
    env = [{"MIX_ENV", "test"} | Enum.map(@llm_env, &{&1, nil})]
    System.cmd("mix", args, env: env, stderr_to_stdout: true)
  end
end
