defmodule GgenIgniter.SemanticJiraAdmissionGuardTest do
  @moduledoc """
  Permanent guards for the repaired failure classes of the full-shape SHACL
  admission (`GgenIgniter.SemanticJira.Admission`, `SemanticJira.Shacl`).

  Each describe block pins one root cause, not one witness:

    * `sh:pattern` anchoring -- PCRE `$` matched before a trailing newline, so a
      pattern-violating literal was admitted. Guarded at the validator
      (`Shacl`) and at the admission court for every pattern-constrained key.
    * fail-closed scope -- `:unsupported_constraint` reports carry
      `focus_node: nil`; the candidate-node scoping in `Admission.admit/2` must
      never discard them.
    * totality -- `Admission.to_graph/1` / `admit/2` never raise on any field
      value or any sibling; a malformed value is a typed refusal (or no triple).
    * `sh:closed` -- vacuous on the map projection (documented), still real over
      the graph; both halves are pinned so the moduledoc cannot drift into an
      over-claim again.

  Chicago, no doubles: the real shipped shape file, the real `Shacl` validator,
  real temp Turtle/shape files. The junk values are real terms, not stubs.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira.{Admission, Shacl}

  @sha String.duplicate("b", 40)

  defp wo(id) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "d-#{id}",
      "subject" => "subj-#{id}",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "authority_ceiling" => "CONSTRUCT",
      "authority_requirement" => "NONE",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "path_scope" => ["lib/ggen_igniter/semantic_jira"],
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "required_receipt_classes" => ["verification"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "next_action" => "run-court",
      "next_checkpoint" => "checkpoint-#{id}",
      "dependencies" => []
    }
  end

  defp tmp!(prefix, content) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}.ttl")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp tampered_shape!(from, to) do
    shipped = File.read!(Admission.shapes_path())
    tampered = String.replace(shipped, from, to, global: false)
    refute tampered == shipped, "tamper anchor not found in the shipped shape: #{from}"
    tmp!("sj_guard_shape", tampered)
  end

  describe "Shacl sh:pattern uses end-of-string `$` (XPath), never PCRE's before-trailing-newline" do
    @prefixes ~S"""
    @prefix ex: <http://example.org/> .
    @prefix sh: <http://www.w3.org/ns/shacl#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    """

    defp pattern_report(pattern, flags, values) do
      flags_triple = if flags == "", do: "", else: ~s|sh:flags "#{flags}" ;|

      shapes = """
      #{@prefixes}
      ex:ThingShape a sh:NodeShape ; sh:targetClass ex:Thing ;
        sh:property [ sh:path ex:code ; #{flags_triple} sh:pattern "#{pattern}" ] .
      """

      data =
        values
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {literal, i} ->
          "ex:n#{i} a ex:Thing ; ex:code #{literal} ."
        end)

      Shacl.validate_file(tmp!("sj_guard_data", @prefixes <> data), tmp!("sj_guard_sh", shapes))
    end

    defp pattern_focus(report),
      do: for(%{constraint: :pattern, focus_node: f} <- report.violations, do: f)

    test "exact value conforms; trailing newline(s) violate; a case-insensitive flag keeps the rule" do
      report =
        pattern_report(
          "^[A-Z]+$",
          "",
          [~S|"ABC"|, ~S|"ABC\n"|, ~S|"ABC\n\n"|, ~S|"AB\nC"|]
        )

      assert Enum.sort(pattern_focus(report)) ==
               Enum.sort([
                 "http://example.org/n1",
                 "http://example.org/n2",
                 "http://example.org/n3"
               ])

      report_i = pattern_report("^[a-z]+$", "i", [~S|"ABC"|, ~S|"ABC\n"|])
      assert pattern_focus(report_i) == ["http://example.org/n1"]
    end

    test "an explicit `\\z` anchor and an unanchored pattern behave as before" do
      report = pattern_report("^[A-Z]+\\\\z", "", [~S|"ABC"|, ~S|"ABC\n"|])
      assert pattern_focus(report) == ["http://example.org/n1"]

      unanchored = pattern_report("BC", "", [~S|"ABC\n"|, ~S|"xyz"|])
      assert pattern_focus(unanchored) == ["http://example.org/n1"]
    end
  end

  describe "every pattern-constrained WorkOrder key refuses a trailing-newline value" do
    for {key, value} <- [
          {"identity", "ROOT\n"},
          {"repository", "o/r\n"},
          {"base_sha", String.duplicate("b", 40) <> "\n"},
          {"candidate_sha", String.duplicate("b", 40) <> "\n"},
          {"subject_sha", String.duplicate("b", 40) <> "\n"},
          {"standing", "UNKNOWN\n"},
          {"authority_ceiling", "CONSTRUCT\n"},
          {"required_receipt_classes", ["verification\n"]}
        ] do
      test "#{key} = #{inspect(value)}" do
        candidate = Map.put(wo("ROOT"), unquote(key), unquote(Macro.escape(value)))

        assert {:error, {:refused_work_order, {:shacl_violations, violations}}} =
                 Admission.admit(candidate)

        assert Enum.any?(violations, &(&1.constraint == :pattern)),
               "expected a :pattern violation, got: #{inspect(violations)}"
      end
    end

    test "the lawful control (no newline) is admitted by the same court" do
      assert {:ok, %Shacl{conforms: true}} = Admission.admit(wo("ROOT"))
    end
  end

  describe "fail-closed: a shape term the validator cannot evaluate refuses, at any scope" do
    for {label, from, to} <- [
          {"property-level sh:in", ~s|sh:path sj:authorityCeiling ; sh:minCount 1 ;|,
           ~s|sh:path sj:authorityCeiling ; sh:in ( "OBSERVE" ) ; sh:minCount 1 ;|},
          {"property-level sh:uniqueLang", ~s|sh:path sj:promotionRule ; sh:minCount 1 ;|,
           ~s|sh:path sj:promotionRule ; sh:uniqueLang true ; sh:minCount 1 ;|},
          {"node-level sh:node", "sh:closed true ;",
           "sh:closed true ; sh:node sj:WorkOrderShape ;"}
        ] do
      test "#{label}: the unsupported-constraint report (focus_node nil) is kept, alone and with siblings" do
        path = tampered_shape!(unquote(from), unquote(to))

        for opts <- [[], [work_orders: [wo("OTHER")]]] do
          assert {:error, {:refused_work_order, {:shacl_violations, violations}}} =
                   Admission.admit(wo("ROOT"), [shapes_path: path] ++ opts)

          assert Enum.any?(
                   violations,
                   &(&1.constraint == :unsupported_constraint and is_nil(&1.focus_node))
                 ),
                 "no nil-focus :unsupported_constraint kept: #{inspect(violations)}"
        end
      end
    end
  end

  describe "totality: no field value and no sibling can make admission raise" do
    @junk [
      %{"a" => 1},
      [%{"a" => 1}],
      {:tuple, 1},
      [[1, 2], %{"k" => {:v}}],
      <<255, 254>>,
      1.5,
      nil,
      true,
      :an_atom
    ]

    test "to_graph/1 returns a graph for a junk value in every key, including dependency fields" do
      for key <- Map.keys(wo("ROOT")), junk <- @junk do
        assert %RDF.Graph{} = Admission.to_graph([Map.put(wo("ROOT"), key, junk)]),
               "to_graph raised/failed for #{key} = #{inspect(junk)}"
      end

      for junk <- @junk do
        dep = %{"upstream" => junk, "type" => junk, "required_standing" => junk}
        assert %RDF.Graph{} = Admission.to_graph([Map.put(wo("ROOT"), "dependencies", [dep])])
        assert %RDF.Graph{} = Admission.to_graph([Map.put(wo("ROOT"), "dependencies", junk)])
      end
    end

    test "admit/2 returns a typed result (never raises) for a junk value in every key" do
      for key <- Map.keys(wo("ROOT")), junk <- @junk do
        result =
          try do
            Admission.admit(Map.put(wo("ROOT"), key, junk))
          rescue
            e -> {:raised, e}
          end

        assert match?({:ok, %Shacl{}}, result) or
                 match?({:error, {:refused_work_order, {:shacl_violations, [_ | _]}}}, result),
               "admit/2 for #{key} = #{inspect(junk)} returned #{inspect(result)}"
      end
    end

    test "a non-scalar identity is refused (no identifier triple -> sh:minCount), not admitted" do
      for junk <- [%{"a" => 1}, [%{"a" => 1}], {:t, 1}] do
        assert {:error, {:refused_work_order, {:shacl_violations, violations}}} =
                 Admission.admit(Map.put(wo("ROOT"), "identity", junk))

        assert Enum.any?(violations, &(&1.constraint == :min_count))
      end
    end

    test "a sibling poisoned in any single key never blocks or crashes a lawful candidate" do
      lawful = wo("FINE")

      for key <- Map.keys(wo("OTHER")), junk <- @junk do
        poisoned = Map.put(wo("OTHER"), key, junk)

        result =
          try do
            Admission.admit(lawful, work_orders: [poisoned])
          rescue
            e -> {:raised, e}
          end

        assert {:ok, %Shacl{conforms: true}} = result,
               "sibling #{key} = #{inspect(junk)} broke a lawful candidate: #{inspect(result)}"
      end
    end

    test "non-map context entries are skipped, not projected" do
      assert {:ok, _} = Admission.admit(wo("FINE"), work_orders: [nil, 1, "x", [1], :a, {1}])
      assert {:ok, _} = Admission.admit(wo("FINE"), work_orders: :not_a_list)
    end

    test "map keys of any type are projected without raising" do
      candidate = Map.merge(wo("FINE"), %{{:tuple, :key} => 1, %{"m" => 1} => 2, 3 => 4})
      assert {:ok, _} = Admission.admit(candidate)
    end
  end

  describe "sh:closed: vacuous on the map projection, real over the graph (moduledoc == behavior)" do
    test "an unknown map key adds no triple, so the projected graph is unchanged" do
      plain = Admission.to_graph([wo("ROOT")])
      rogue = Admission.to_graph([Map.put(wo("ROOT"), "rogue_field", "x")])

      assert Enum.sort(RDF.Graph.triples(plain)) == Enum.sort(RDF.Graph.triples(rogue))
      assert {:ok, _} = Admission.admit(Map.put(wo("ROOT"), "rogue_field", "x"))
    end

    test "the shipped shape is still closed: an undeclared predicate on the node is refused" do
      iri = RDF.iri("urn:ggen-igniter:semantic-jira:work-order:ROOT")

      graph =
        Admission.to_graph([wo("ROOT")])
        |> RDF.Graph.add({iri, RDF.iri("urn:example:rogue"), RDF.literal("x")})

      report = Shacl.validate(graph, Ontology.load!(Admission.shapes_path()))

      assert Enum.any?(
               report.violations,
               &(&1.constraint == :closed and &1.focus_node == to_string(iri))
             )
    end
  end
end
