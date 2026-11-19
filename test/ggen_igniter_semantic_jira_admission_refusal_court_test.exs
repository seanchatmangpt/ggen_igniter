defmodule GgenIgniter.SemanticJiraAdmissionRefusalCourtTest do
  @moduledoc """
  Court-kit / semantic-gate-witness twin court over
  `GgenIgniter.SemanticJira.admit_work_order/1` refusal tags.

  Donor method: `~/ggen-marketplace/packs/court-kit-pack` (every registered
  refusal needs `ck:observedTrigger`) +
  `~/ggen-marketplace/packs/semantic-gate-witness-court-pack` (pass/fail
  witnesses for the totality gate).

  Chicago: real `admit_work_order/1` only — no mocks, no sleeps. For every
  register token: (1) a malformed WorkOrder fires the tagged refusal
  (refusal-live KAT), (2) the canonical shadow twin admits and therefore
  cannot fire that tag (anti-vacuity). The SPARQL gate returns zero rows on
  the pass witness and ≥1 row on the fail witness (missing observedTrigger).
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query, SemanticJira}

  @court_root Path.expand("fixtures/semantic-jira-admission-court", __DIR__)
  @register Path.join(@court_root, "ontology.ttl")
  @gate Path.join(@court_root, "gates/01_all_codes_live.rq")
  @pass_witness Path.join(@court_root, "witnesses/pass/01_all_codes_live.ttl")
  @fail_witness Path.join(@court_root, "witnesses/fail/01_all_codes_live.ttl")
  @gate_court_toml Path.join(@court_root, "gate-court.toml")

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"

  # Closed table: token → malformed override-or-input.
  # Matchers live in match_reason?/2 — Elixir 1.20 refuses anonymous
  # functions in module attributes injected into generated tests.
  @kat_table [
    {"WO-EXPECTED-MAP", :non_map},
    {"WO-MISSING-REQUIRED-FIELD", %{"identity" => ""}},
    {"WO-INVALID-REPOSITORY", %{"repository" => "not-a-repo"}},
    {"WO-INVALID-SHA-BASE", %{"base_sha" => "main"}},
    {"WO-INVALID-SHA-CANDIDATE", %{"candidate_sha" => "main"}},
    {"WO-INVALID-STANDING", %{"standing" => "NOT_A_STANDING"}},
    # nonempty_lists/2 fires {:invalid_list, key} on a non-list (empty list
    # is {:missing_required_field, key} via required/2 for @required keys).
    {"WO-INVALID-LIST", %{"required_courts" => "not-a-list"}},
    {"WO-INVALID-DEPENDENCY",
     %{
       "dependencies" => [
         %{"upstream" => "UP", "type" => "not-a-dependency-type"}
       ]
     }},
    {"WO-INVALID-DEPENDENCIES", %{"dependencies" => "not-a-list"}},
    {"WO-UNSUPPORTED-PROJECTION-TYPE", %{"projections" => ["bogus-projection"]}},
    # Live kernel: nonempty_lists/2 runs before projection_types/1, so a
    # non-list projections value refuses as {:invalid_list, "projections"}
    # (the {:invalid_projection_types, _} clause is currently shadowed).
    {"WO-INVALID-PROJECTION-TYPES", %{"projections" => "not-a-list"}},
    {"WO-UNSUPPORTED-RECEIPT-CLASS", %{"required_receipt_classes" => ["bogus"]}},
    {"WO-INVALID-RECEIPT-CLASSES", %{"required_receipt_classes" => "not-a-list"}},
    {"WO-INVALID-PATH-SCOPE", %{"path_scope" => ["/abs"]}},
    {"WO-INVALID-ORIGIN-AUTHORITY", %{"origin_authority" => "not-an-iri"}},
    {"WO-INVALID-ORIGIN-OBSERVATION", %{"origin_observation" => "not-an-iri"}},
    {"WO-INVALID-TARGET-PACK", %{"target_pack" => "Demo Pack"}}
  ]

  defp match_reason?("WO-EXPECTED-MAP", reason), do: reason == :expected_map

  defp match_reason?("WO-MISSING-REQUIRED-FIELD", reason),
    do: match?({:missing_required_field, "identity"}, reason)

  defp match_reason?("WO-INVALID-REPOSITORY", reason),
    do: match?({:invalid_repository, _}, reason)

  defp match_reason?("WO-INVALID-SHA-BASE", reason),
    do: match?({:invalid_sha, :base_sha, _}, reason)

  defp match_reason?("WO-INVALID-SHA-CANDIDATE", reason),
    do: match?({:invalid_sha, :candidate_sha, _}, reason)

  defp match_reason?("WO-INVALID-STANDING", reason),
    do: match?({:invalid_standing, _}, reason)

  defp match_reason?("WO-INVALID-LIST", reason),
    do: match?({:invalid_list, "required_courts"}, reason)

  defp match_reason?("WO-INVALID-DEPENDENCY", reason),
    do: match?({:invalid_dependency, _}, reason)

  defp match_reason?("WO-INVALID-DEPENDENCIES", reason),
    do: match?({:invalid_dependencies, _}, reason)

  defp match_reason?("WO-UNSUPPORTED-PROJECTION-TYPE", reason),
    do: match?({:unsupported_projection_type, "bogus-projection"}, reason)

  defp match_reason?("WO-INVALID-PROJECTION-TYPES", reason),
    do:
      match?({:invalid_list, "projections"}, reason) or
        match?({:invalid_projection_types, _}, reason)

  defp match_reason?("WO-UNSUPPORTED-RECEIPT-CLASS", reason),
    do: match?({:unsupported_receipt_class, "bogus"}, reason)

  defp match_reason?("WO-INVALID-RECEIPT-CLASSES", reason),
    do: match?({:invalid_receipt_classes, _}, reason)

  defp match_reason?("WO-INVALID-PATH-SCOPE", reason),
    do: match?({:invalid_path_scope, _}, reason)

  defp match_reason?("WO-INVALID-ORIGIN-AUTHORITY", reason),
    do: match?({:invalid_origin_authority, _}, reason)

  defp match_reason?("WO-INVALID-ORIGIN-OBSERVATION", reason),
    do: match?({:invalid_origin_observation, _}, reason)

  defp match_reason?("WO-INVALID-TARGET-PACK", reason),
    do: match?({:invalid_target_pack, "Demo Pack"}, reason)

  defp canonical(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "SJ-ADM-COURT-001",
        "title" => "Admission refusal court",
        "description" => "Canonical shadow twin for court-kit KATs.",
        "subject" => "urn:subject:admission-refusal-court",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:admission-refusal-court:1",
        "dependencies" => [],
        "required_courts" => ["court:admission-refusal"],
        "required_evidence" => ["source"],
        "acceptance" => ["acceptance:admission-refusal"],
        "falsifiers" => ["falsifier:admission-refusal"],
        "projections" => SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib/ggen_igniter"],
        "authority_requirement" => "NONE",
        "origin_authority" => @origin_authority,
        "replay_required" => false
      },
      overrides
    )
  end

  defp probe(:non_map), do: SemanticJira.admit_work_order([:not, :a, :map])
  defp probe(overrides) when is_map(overrides), do: SemanticJira.admit_work_order(canonical(overrides))

  defp reason_of({:error, {:refused_work_order, reason}}), do: reason
  defp reason_of(other), do: flunk("expected refused_work_order, got: #{inspect(other)}")

  describe "shadow twin admits (positive control baseline)" do
    test "canonical WorkOrder admits through the real kernel" do
      assert {:ok, admitted} = SemanticJira.admit_work_order(canonical())
      assert admitted["admitted"] == true
      assert admitted["authority"] == "NONE"
      assert is_binary(admitted["work_order_digest"])
    end
  end

  describe "refusal-live KAT + shadow twin (court-kit anti-vacuity)" do
    for {token, input} <- @kat_table do
      @token token
      @input input

      test "kat_#{token}_refusal_live fires on malformed WorkOrder" do
        reason = probe(@input) |> reason_of()
        assert match_reason?(@token, reason),
               "#{@token} must fire on its documented trigger; got #{inspect(reason)}"
      end

      test "kat_#{token}_shadow_twin_silent on canonical WorkOrder" do
        assert {:ok, _} = SemanticJira.admit_work_order(canonical())

        # Discrimination: the malformed input still refuses (court can flip).
        assert {:error, {:refused_work_order, reason}} = probe(@input)
        assert match_reason?(@token, reason)
      end
    end
  end

  describe "court-kit observedTrigger totality gate" do
    test "pass witness returns zero unobserved rows" do
      graph = Ontology.load!(@pass_witness)
      rows = Query.run(graph, File.read!(@gate))
      assert rows == [], "unobserved codes: #{inspect(rows)}"
    end

    test "fail witness (missing observedTrigger) returns ≥1 row — gate flips" do
      graph = Ontology.load!(@fail_witness)
      rows = Query.run(graph, File.read!(@gate))
      assert rows != [], "VACUOUS GATE: fail witness did not trip 01_all_codes_live"

      tokens =
        Enum.map(rows, fn
          %{"token" => token} -> token
          row when is_map(row) -> Map.get(row, "token") || Map.get(row, :token)
          other -> other
        end)

      assert "WO-INVALID-TARGET-PACK" in Enum.map(tokens, &to_string/1)
    end

    test "register ontology lists exactly the KAT table tokens with observedTrigger" do
      graph = Ontology.load!(@register)
      query = """
      PREFIX ck: <urn:court-kit:>
      SELECT ?token ?obs WHERE {
        ?code a ck:RefusalCode ; ck:token ?token ; ck:observedTrigger ?obs .
      } ORDER BY ?token
      """

      rows = Query.run(graph, query)
      tokens = Enum.map(rows, &to_string(&1["token"] || &1[:token]))
      expected = Enum.map(@kat_table, &elem(&1, 0)) |> Enum.sort()

      assert Enum.sort(tokens) == expected,
             "register/KAT drift: register=#{inspect(Enum.sort(tokens))} kat=#{inspect(expected)}"

      assert length(rows) == length(@kat_table)
      assert Enum.all?(rows, fn row -> (row["obs"] || row[:obs]) not in [nil, ""] end)
    end
  end

  @marketplace_checker "/Users/sac/ggen-marketplace/scripts/check_gate_witness_courts.py"
  @marketplace_checker_present? File.exists?(@marketplace_checker)

  # check_gate_witness_courts.py imports tomllib (stdlib since 3.11). Prefer
  # a 3.11+ binary when `python3` on PATH is older (common on macOS).
  @python_for_qualify (
    Enum.find_value(["python3.12", "python3.11", "python3"], fn bin ->
      case System.find_executable(bin) do
        nil ->
          nil

        path ->
          case System.cmd(path, ["-c", "import tomllib"], stderr_to_stdout: true) do
            {_, 0} -> path
            _ -> nil
          end
      end
    end)
  )

  @marketplace_skip_reason (
    cond do
      not @marketplace_checker_present? ->
        "BLOCKED:marketplace-checker-absent (no #{@marketplace_checker})"

      is_nil(@python_for_qualify) ->
        "BLOCKED:tomllib-absent (need python3.11+ with tomllib for marketplace qualify)"

      true ->
        false
    end
  )

  describe "semantic-gate-witness court contract" do
    test "gate-court.toml declares exact-stem pass+fail coverage for the KAT gate" do
      assert File.exists?(@gate_court_toml)
      assert File.exists?(@gate)
      assert File.exists?(@pass_witness)
      assert File.exists?(@fail_witness)

      toml = File.read!(@gate_court_toml)
      assert toml =~ ~s|schema = "ggen.semantic-gate-witness-court/1"|
      assert toml =~ ~s|case_key = "exact-stem"|
      assert toml =~ "require_pass = true"
      assert toml =~ "require_fail = true"

      # Stem correspondence (semantic-gate-witness law): gate stem == witness stems.
      assert Path.basename(@gate, ".rq") == "01_all_codes_live"
      assert Path.basename(@pass_witness, ".ttl") == "01_all_codes_live"
      assert Path.basename(@fail_witness, ".ttl") == "01_all_codes_live"
    end

    @tag skip: @marketplace_skip_reason
    test "marketplace check_gate_witness_courts.qualify/1 admits this court root" do
      # Real collaborator: import the marketplace structural qualify() and run
      # it against this fixture pack root (not the packs/* glob scanner).
      py = """
      import importlib.util, json, sys
      from pathlib import Path
      spec = importlib.util.spec_from_file_location(
          "check_gate_witness_courts",
          #{inspect(@marketplace_checker)}
      )
      mod = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(mod)
      result = mod.qualify(Path(#{inspect(@court_root)}))
      print(json.dumps(result, sort_keys=True))
      """

      {out, status} = System.cmd(@python_for_qualify, ["-c", py], stderr_to_stdout: true)
      assert status == 0, "qualify failed:\n#{out}"

      assert %{"standing" => "ALIVE", "case_count" => 1, "require_fail" => true,
              "require_pass" => true} = Jason.decode!(out)
    end
  end
end
