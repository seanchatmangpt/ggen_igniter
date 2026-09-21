defmodule GgenIgniter.SemanticJiraAdmissionTest do
  @moduledoc """
  Chicago-style: real `SemanticJira.Admission` over the real shipped shape file
  (`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`) through the real
  `Shacl` validator and real RDF/Turtle loading, plus a real temp shape file for
  the shape-override witness. No test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Admission
  alias RDF.Graph

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @sha String.duplicate("a", 40)

  defp wo(id, deps \\ []) do
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
      "path_scope" => ["lib/ggen_igniter"],
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "required_receipt_classes" => ["verification"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "next_action" => "run-court",
      "next_checkpoint" => "cp-#{id}",
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp work_order_nodes(graph) do
    graph
    |> Graph.triples()
    |> Enum.filter(fn {_, p, o} -> p == RDF.type() and o == RDF.iri(@sj <> "WorkOrder") end)
    |> Enum.map(&elem(&1, 0))
  end

  describe "shapes_path/0" do
    test "resolves to the shipped shape file on disk" do
      assert File.regular?(Admission.shapes_path())
      assert Admission.shapes_path() =~ "semantic-jira-pack/shapes/work-order.shacl.ttl"
    end
  end

  describe "to_graph/1" do
    test "is deterministic and atom-key/string-key insensitive" do
      atom_keyed = for {k, v} <- wo("WO-A"), into: %{}, do: {String.to_atom(k), v}
      assert Admission.to_graph([wo("WO-A")]) == Admission.to_graph([atom_keyed])
      assert Admission.to_graph([wo("WO-A")]) == Admission.to_graph([wo("WO-A")])
    end

    test "a repeated identity yields distinct WorkOrder nodes (never silently merged)" do
      graph = Admission.to_graph([wo("WO-A"), Map.put(wo("WO-A"), "subject", "elsewhere")])
      assert length(work_order_nodes(graph)) == 2
    end

    test "never raises on malformed values" do
      assert %Graph{} = Admission.to_graph([%{}, %{"identity" => 42, "required_courts" => "ci"}])
    end
  end

  describe "admit/2" do
    test "admits a complete WorkOrder and its dependency chain through the full shape" do
      chain = [wo("WO-A"), wo("WO-B", ["WO-A"]), wo("WO-C", ["WO-B"])]

      for w <- chain,
          do:
            assert(
              {:ok, %{conforms: true, violations: []}} = Admission.admit(w, work_orders: chain)
            )
    end

    test "refuses malformed candidates with typed violations instead of raising" do
      assert {:error, {:refused_work_order, {:shacl_violations, v}}} = Admission.admit(%{})
      assert Enum.any?(v, &(&1.constraint == :min_count))

      # a non-string identifier is a wrongly-typed literal: datatype violation
      assert {:error, {:refused_work_order, {:shacl_violations, v}}} =
               Admission.admit(Map.put(wo("WO-A"), "identity", 42))

      assert Enum.any?(v, &(&1.constraint == :datatype))

      # a scalar in a list field is one element to this court; the kernel court
      # (admit_work_order/1) is what refuses the wrong shape
      scalar_court = Map.put(wo("WO-A"), "required_courts", "ci")
      assert {:ok, _} = Admission.admit(scalar_court)

      assert {:error, {:refused_work_order, _}} =
               GgenIgniter.SemanticJira.admit_work_order(scalar_court)
    end

    test "a malformed sibling does not block an unrelated lawful candidate" do
      broken = wo("BROKEN") |> Map.delete("path_scope")
      assert {:ok, _} = Admission.admit(wo("FINE"), work_orders: [broken])
      assert {:error, _} = Admission.admit(broken, work_orders: [wo("FINE")])
    end

    test "the verdict comes from the shape file: an inline-subset shape file admits what the shipped shape refuses" do
      subset = Path.join(System.tmp_dir!(), "sj_subset_#{System.unique_integer([:positive])}.ttl")
      on_exit(fn -> File.rm_rf!(subset) end)

      File.write!(subset, """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      @prefix sj: <#{@sj}> .
      sj:SubsetShape a sh:NodeShape ;
          sh:targetClass sj:WorkOrder ;
          sh:property [ sh:path sj:baseSha ; sh:minCount 1 ; sh:datatype xsd:string ] .
      """)

      candidate = Map.delete(wo("WO-A"), "path_scope")
      assert {:ok, _} = Admission.admit(candidate, shapes_path: subset)
      assert {:error, {:refused_work_order, {:shacl_violations, _}}} = Admission.admit(candidate)
    end
  end
end
