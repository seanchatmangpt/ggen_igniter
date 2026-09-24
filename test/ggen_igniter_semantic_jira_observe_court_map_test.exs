defmodule GgenIgniter.SemanticJiraObserveCourtMapTest do
  @moduledoc """
  Chicago, no doubles (V23-T6R; PRD PR-006/PR-012, ARD §4 ggen_igniter).

  Observation edge: a finding DERIVED from a real temporary git repository
  (normative model = the committed blob at the real base commit read back
  with `git show`, observed model = the drifted working-tree bytes,
  observation receipt = the real `git diff` bytes) becomes a candidate
  WorkOrder admitted by the real kernel and the real SHACL court over the
  real pack ontology — in-process (`Observation.candidate/3`) and through the
  real `mix semantic_jira.observe` subprocess `Xaas.Ultracode.SemanticCrown`
  invokes.

  Court-map mint: `CourtMap.from_ontology/2` and `mix semantic_jira.court_map`
  over the real Turtle fixture `test/fixtures/semantic_jira/court_map_fri_fmt.ttl`
  (proven parseable by the real RDF Turtle reader), chained into the real
  `mix semantic_jira.descriptor --court-map` so the minted map lands in the
  XaaS descriptor; plus the descriptor's court-map admission refusals.

  Every assertion is on returned/printed JSON or on disk.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira.{CourtMap, Descriptor, Observation}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @origin_authority @sj <> "objective-code-work-authority"
  @work_orders Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)
  @court_map_ttl Path.expand("fixtures/semantic_jira/court_map_fri_fmt.ttl", __DIR__)
  @alias "seanchatmangpt/ggen_igniter=ggen_igniter"
  @suite "ggen-igniter-format"
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @format_clean "urn:semantic-jira:acceptance:FRI-FMT-A:format-clean"
  @revert_reddens "urn:semantic-jira:falsifier:FRI-FMT-A:revert-reddens"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_observe_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # ── real git repository ──────────────────────────────────────────────────

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    out
  end

  defp sha256(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  # A real repository with one formatted source file committed at `base`,
  # then drifted in the working tree (deterministic format drift: the KNOWN
  # reference class recipe:mix-format).
  defp drifted_repo!(dir) do
    repo = Path.join(dir, "subject")
    File.mkdir_p!(Path.join(repo, "lib"))
    git!(repo, ["init", "-q"])
    git!(repo, ["config", "user.email", "v23-t6r@example.invalid"])
    git!(repo, ["config", "user.name", "V23-T6R"])
    git!(repo, ["config", "commit.gpgsign", "false"])

    clean = "defmodule Sample do\n  def value, do: 1\nend\n"
    File.write!(Path.join(repo, "lib/sample.ex"), clean)
    git!(repo, ["add", "lib/sample.ex"])
    git!(repo, ["commit", "-q", "-m", "base"])
    base = repo |> git!(["rev-parse", "HEAD"]) |> String.trim()

    File.write!(Path.join(repo, "lib/sample.ex"), "defmodule Sample do\ndef value,do: 1\nend\n")
    %{repo: repo, base: base}
  end

  defp finding!(%{repo: repo, base: base}) do
    normative = git!(repo, ["show", "#{base}:lib/sample.ex"])
    observed = File.read!(Path.join(repo, "lib/sample.ex"))
    diff = git!(repo, ["diff", "--no-color", base, "--", "lib/sample.ex"])

    %{
      "normative_model_digest" => sha256(normative),
      "observed_model_digest" => sha256(observed),
      "observation_receipt_digest" => sha256(diff),
      "delta" => "format drift in lib/sample.ex against #{base}"
    }
  end

  defp base_work_order(base_sha, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "OBS-BASE",
        "title" => "Observed format drift base",
        "description" => "Base work order whose typed courts the observed candidate reuses.",
        "subject" => "ggen_igniter:observe:base",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => base_sha,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "Standing advances only from an exact-head fabric court receipt.",
        "replay_identity" => "semantic-jira:observe:base",
        "dependencies" => [],
        "required_courts" => [@sj <> "exact-head-projection-court"],
        "required_evidence" => [@sj <> "graph-receipt-evidence"],
        "acceptance" => [@sj <> "canonical-source"],
        "falsifiers" => [@sj <> "projection-gains-authority"],
        "projections" => ["jira"],
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib"],
        "origin_authority" => @origin_authority
      },
      overrides
    )
  end

  defp write_json!(path, value) do
    File.write!(path, Jason.encode!(value))
    path
  end

  # The mix subprocess may print Mix/compiler notices first; the task's result
  # is the last line that decodes as a JSON object.
  defp mix_json(args) do
    {out, code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    json =
      out
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = map} -> map
          _ -> nil
        end
      end)

    {code, json, out}
  end

  # ── observation edge ─────────────────────────────────────────────────────

  describe "Observation.candidate/3 over a finding derived from a real git repository" do
    test "admits a SHACL-conformant candidate bound to the real base commit", %{dir: dir} do
      subject = drifted_repo!(dir)
      finding = finding!(subject)

      assert {:ok, result} =
               Observation.candidate(finding, base_work_order(subject.base),
                 origin_authority: @origin_authority
               )

      candidate = result["work_order"]
      short = String.slice(result["finding"]["finding_digest"], 7, 12)

      assert candidate["identity"] == "OBS-" <> String.upcase(short)
      assert candidate["base_sha"] == subject.base
      assert candidate["standing"] == "UNKNOWN"
      assert candidate["authority"] == "NONE"
      assert candidate["admitted"] == true
      assert candidate["required_courts"] == [@sj <> "exact-head-projection-court"]
      assert candidate["path_scope"] == ["lib"]
      assert Regex.match?(@digest, candidate["work_order_digest"])
      assert Regex.match?(@digest, candidate["definition_digest"])

      assert result["finding"]["normative_model_digest"] == finding["normative_model_digest"]
      assert result["finding"]["admission_state"] == "CANDIDATE"
      assert result["repair"] == nil

      assert result["shacl"]["conforms"] == true
      assert result["shacl"]["shapes_checked"] > 0
      assert result["shacl"]["focus_node_count"] > 0

      # The emitted Turtle is real Turtle carrying the candidate's exact base.
      graph = RDF.Turtle.read_string!(result["turtle"])
      assert RDF.Graph.triple_count(graph) > 0
      assert result["turtle"] =~ ~s(sj:baseSha "#{subject.base}")

      # INVARIANT A: the candidate is bound to its declared origin authority.
      assert candidate["origin_authority"] == @origin_authority

      assert candidate["origin_observation"] ==
               @sj <> "obs-" <> short <> "-finding"

      assert result["turtle"] =~ ~s(sj:originAuthority <#{@origin_authority}>)
      assert result["turtle"] =~ ~s(sj:originObservation <#{@sj}obs-#{short}-finding>)

      # Deterministic: the same observation re-derives the same candidate.
      assert {:ok, again} =
               Observation.candidate(finding, base_work_order(subject.base),
                 origin_authority: @origin_authority
               )

      assert again["work_order"]["work_order_digest"] == candidate["work_order_digest"]
      assert again["turtle"] == result["turtle"]

      # A different observation (further drift) is a different candidate.
      File.write!(Path.join(subject.repo, "lib/sample.ex"), "defmodule Sample do\nend\n")

      assert {:ok, other} =
               Observation.candidate(finding!(subject), base_work_order(subject.base),
                 origin_authority: @origin_authority
               )

      refute other["work_order"]["identity"] == candidate["identity"]
    end

    test "a repair hypothesis adds the guard acceptance and the repair lineage", %{dir: dir} do
      subject = drifted_repo!(dir)

      repair = %{
        "failed_receipt_digest" => sha256("failed-format-court"),
        "hypothesis" => "the worker skipped mix format",
        "smallest_repair" => "run mix format on lib/sample.ex",
        "permanent_guard" => "format court on every candidate head",
        "changed_identities" => ["lib/sample.ex"],
        "verifier" => "ggen-igniter-format"
      }

      assert {:ok, result} =
               Observation.candidate(finding!(subject), base_work_order(subject.base),
                 repair: repair,
                 origin_authority: @origin_authority
               )

      assert result["repair"]["kind"] == "repair_work_order_candidate"
      assert result["repair"]["repair_of"] == "OBS-BASE"
      assert Enum.any?(result["work_order"]["acceptance"], &String.ends_with?(&1, "-guard"))
      assert result["work_order"]["description"] =~ "Hypothesis: the worker skipped mix format"
      assert result["shacl"]["conforms"] == true
    end

    test "refuses typed: malformed finding, unadmittable base, SHACL violation", %{dir: dir} do
      subject = drifted_repo!(dir)
      finding = finding!(subject)
      base = base_work_order(subject.base)

      assert {:error, {:observation_refused, {:finding, _}}} =
               Observation.candidate(Map.delete(finding, "delta"), base,
                 origin_authority: @origin_authority
               )

      assert {:error, {:observation_refused, {:base_work_order, _}}} =
               Observation.candidate(finding, Map.delete(base, "title"),
                 origin_authority: @origin_authority
               )

      # A reused court that is not a typed sj:Court node in the canonical
      # graph violates the WorkOrder shape's sh:class constraint.
      untyped = base_work_order(subject.base, %{"required_courts" => ["urn:untyped:court"]})

      assert {:error, {:observation_refused, {:shacl_violations, violations}}} =
               Observation.candidate(finding, untyped, origin_authority: @origin_authority)

      assert Enum.any?(
               violations,
               &(&1[:path] |> to_string() |> String.ends_with?("requiresCourt"))
             )
    end

    test "refuses typed: no origin_authority opt, before any kernel work (INVARIANT A)", %{
      dir: dir
    } do
      subject = drifted_repo!(dir)

      assert {:error, {:observation_refused, {:missing_origin_authority, message}}} =
               Observation.candidate(finding!(subject), base_work_order(subject.base))

      assert message =~ "origin_authority"
    end

    test "refuses typed: a fresh self-declared origin the canonical ontology never admitted", %{
      dir: dir
    } do
      subject = drifted_repo!(dir)

      assert {:error, {:observation_refused, {:origin_not_admitted, _reason}}} =
               Observation.candidate(finding!(subject), base_work_order(subject.base),
                 origin_authority: @sj <> "self-declared-rogue-authority"
               )
    end

    test "refuses typed: a real canonical node that is not an authority", %{dir: dir} do
      subject = drifted_repo!(dir)

      # sj:projection-gains-authority exists in the canonical graph as a
      # Falsifier node; existence is not authority.
      assert {:error, {:observation_refused, {:origin_not_admitted, _reason}}} =
               Observation.candidate(finding!(subject), base_work_order(subject.base),
                 origin_authority: @sj <> "projection-gains-authority"
               )
    end
  end

  describe "mix semantic_jira.observe (the SemanticCrown subprocess surface)" do
    @tag timeout: :timer.minutes(5)
    test "exit 0 writes the admitted candidate; exit 1 typed refusal; exit 2 invalid invocation",
         %{dir: dir} do
      subject = drifted_repo!(dir)
      finding_path = write_json!(Path.join(dir, "finding.json"), finding!(subject))
      base_path = write_json!(Path.join(dir, "base.json"), base_work_order(subject.base))
      out = Path.join(dir, "candidate.json")

      {code, json, output} =
        mix_json([
          "semantic_jira.observe",
          "--finding",
          finding_path,
          "--base-work-order",
          base_path,
          "--origin-authority",
          @origin_authority,
          "--identity",
          "OBS-CLI-A",
          "--out",
          out
        ])

      assert code == 0, output
      assert json["work_order"]["identity"] == "OBS-CLI-A"
      assert json["work_order"]["base_sha"] == subject.base
      assert json["work_order"]["origin_authority"] == @origin_authority
      assert json["shacl"]["conforms"] == true
      assert Jason.decode!(File.read!(out)) == json

      untyped_path =
        write_json!(
          Path.join(dir, "untyped.json"),
          base_work_order(subject.base, %{"required_courts" => ["urn:untyped:court"]})
        )

      {code, json, output} =
        mix_json([
          "semantic_jira.observe",
          "--finding",
          finding_path,
          "--base-work-order",
          untyped_path,
          "--origin-authority",
          @origin_authority
        ])

      assert code == 1, output
      assert json["status"] == "refused"
      assert ["observation_refused", ["shacl_violations" | _]] = json["reason"]

      {code, json, output} =
        mix_json([
          "semantic_jira.observe",
          "--finding",
          finding_path,
          "--base-work-order",
          base_path
        ])

      assert code == 1, output
      assert json["status"] == "refused"
      assert ["observation_refused", ["missing_origin_authority", _]] = json["reason"]

      {code, json, output} = mix_json(["semantic_jira.observe", "--finding", finding_path])
      assert code == 2, output
      assert json == %{"status" => "invalid_invocation", "reason" => "missing --base-work-order"}
    end
  end

  # ── court-map mint ───────────────────────────────────────────────────────

  describe "CourtMap.from_ontology/2 over a real Turtle fixture" do
    test "the fixture is real Turtle and mints the witnessed map per work order" do
      ttl = File.read!(@court_map_ttl)
      assert RDF.Graph.triple_count(RDF.Turtle.read_string!(ttl)) > 0

      assert {:ok, a} = CourtMap.from_ontology(ttl, "FRI-FMT-A")

      assert a == %{
               "acceptance" => %{
                 @format_clean => %{
                   "test" => "test/ggen_igniter_format_test.exs::format clean at candidate head"
                 }
               },
               "falsifiers" => %{
                 @revert_reddens => %{
                   "test" => "test/ggen_igniter_format_test.exs::revert reddens format court"
                 }
               },
               "courts" => []
             }

      assert {:ok, b} = CourtMap.from_ontology(ttl, "FRI-FMT-B")
      assert b["courts"] == [@sj <> "exact-head-projection-court"]
      assert map_size(b["acceptance"]) == 1
    end

    test "fails closed: unwitnessed IRI, missing predicate, unknown identity, non-string" do
      ttl = File.read!(@court_map_ttl)

      unwitnessed =
        String.replace(
          ttl,
          ~s(    sj:witnessedBy "test/ggen_igniter_format_test.exs::revert reddens format court" .),
          ~s(    rdfs:comment "no witness" .)
        )

      assert {:error, {:court_map_refused, {:unwitnessed, @revert_reddens}}} =
               CourtMap.from_ontology(unwitnessed, "FRI-FMT-A")

      no_acceptance =
        String.replace(
          ttl,
          "    sj:acceptance <urn:semantic-jira:acceptance:FRI-FMT-A:format-clean> ;\n",
          ""
        )

      assert {:error, {:court_map_refused, {:missing_predicate, "acceptance"}}} =
               CourtMap.from_ontology(no_acceptance, "FRI-FMT-A")

      assert {:error, {:court_map_refused, {:work_order_not_found, "FRI-NOPE"}}} =
               CourtMap.from_ontology(ttl, "FRI-NOPE")

      assert {:error, {:court_map_refused, :not_a_string}} = CourtMap.from_ontology(nil, "X")
    end

    test "an observed candidate's Turtle carries no witnesses, so the mint refuses it",
         %{dir: dir} do
      subject = drifted_repo!(dir)

      {:ok, result} =
        Observation.candidate(finding!(subject), base_work_order(subject.base),
          identity: "OBS-UNWITNESSED",
          origin_authority: @origin_authority
        )

      assert {:error, {:court_map_refused, {:unwitnessed, iri}}} =
               CourtMap.from_ontology(result["turtle"], "OBS-UNWITNESSED")

      assert iri in result["work_order"]["acceptance"]
    end
  end

  describe "court map -> descriptor (build_xaas_contract/4 court-map admission)" do
    defp fixture_rows do
      @work_orders |> File.read!() |> Jason.decode!() |> Map.fetch!("work_orders")
    end

    defp contract(court_map) do
      Descriptor.build_xaas_contract(fixture_rows(), [], "FRI-FMT-A",
        verifier_suite: @suite,
        aliases: %{"seanchatmangpt/ggen_igniter" => "ggen_igniter"},
        provider: "recipe",
        court_map: court_map
      )
    end

    test "a minted map binds into the descriptor; foreign or malformed maps refuse" do
      {:ok, minted} = CourtMap.from_ontology(File.read!(@court_map_ttl), "FRI-FMT-A")

      assert {:ok, descriptor} = contract(minted)
      assert descriptor["court_map"] == minted
      assert descriptor["provider"] == "recipe"

      {:ok, b_map} = CourtMap.from_ontology(File.read!(@court_map_ttl), "FRI-FMT-B")

      assert {:error,
              {:descriptor_refused, {:court_map_refused, {:foreign_iri, "acceptance", _}}}} =
               contract(b_map)

      assert {:error, {:descriptor_refused, {:court_map_refused, {:unknown_keys, ["extra"]}}}} =
               contract(Map.put(minted, "extra", true))

      assert {:error, {:descriptor_refused, {:court_map_refused, :empty}}} =
               contract(%{"acceptance" => %{}, "falsifiers" => %{}, "courts" => []})

      assert {:error,
              {:descriptor_refused,
               {:court_map_refused, {:invalid_predicate, "acceptance", @format_clean, %{}}}}} =
               contract(%{"acceptance" => %{@format_clean => %{}}})

      assert {:error, {:descriptor_refused, {:court_map_refused, {:foreign_iri, "courts", _}}}} =
               contract(%{"courts" => ["urn:foreign:court"]})

      assert {:error, {:descriptor_refused, {:court_map_refused, :not_a_map}}} =
               contract(["not", "a", "map"])

      assert {:ok, no_map} = contract(nil)
      refute Map.has_key?(no_map, "court_map")
    end

    @tag timeout: :timer.minutes(5)
    test "mix semantic_jira.court_map mints the map that mix semantic_jira.descriptor binds",
         %{dir: dir} do
      court_map_path = Path.join(dir, "court-map.json")

      {code, minted, output} =
        mix_json([
          "semantic_jira.court_map",
          "--ontology",
          @court_map_ttl,
          "--identity",
          "FRI-FMT-A",
          "--out",
          court_map_path
        ])

      assert code == 0, output
      assert minted["acceptance"][@format_clean]["test"] =~ "format clean"
      assert Jason.decode!(File.read!(court_map_path)) == minted

      {code, descriptor, output} =
        mix_json([
          "semantic_jira.descriptor",
          "--work-orders",
          @work_orders,
          "--ledger",
          Path.join(dir, "ledger"),
          "--identity",
          "FRI-FMT-A",
          "--verifier-suite",
          @suite,
          "--alias",
          @alias,
          "--provider",
          "recipe",
          "--court-map",
          court_map_path
        ])

      assert code == 0, output
      assert descriptor["court_map"] == minted
      assert descriptor["provider"] == "recipe"

      {code, json, output} =
        mix_json([
          "semantic_jira.court_map",
          "--ontology",
          @court_map_ttl,
          "--identity",
          "FRI-NOPE"
        ])

      assert code == 1, output

      assert json == %{
               "status" => "refused",
               "reason" => ["court_map_refused", ["work_order_not_found", "FRI-NOPE"]]
             }

      {code, json, output} = mix_json(["semantic_jira.court_map", "--ontology", @court_map_ttl])
      assert code == 2, output
      assert json == %{"status" => "invalid_invocation", "reason" => "missing --identity"}
    end
  end
end
