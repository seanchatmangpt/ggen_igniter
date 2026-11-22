defmodule GgenIgniter.SemanticJiraKernelAlignmentTest do
  @moduledoc """
  Chicago-style: real `SemanticJira.admit_work_order/1` and the real shape file
  `priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`; no doubles.

  Pins the shape-vs-kernel alignment audit. A canonical order admits. B1
  (identifier pattern), B3 (non-empty pathScope) and B4 (receipt-class default)
  are shape-stricter-than-kernel divergences that are DELIBERATELY not tightened
  because existing fixtures (one-character identities, omitted path_scope) rely
  on the lenient behavior. These tests pin that current behavior so tightening
  later is an explicit, reviewed flip rather than a silent change.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.WorkOrderShape

  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @shape Path.expand("../priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl", __DIR__)
  @identity_regex ~r/\A[A-Z][A-Z0-9-]{1,63}\z/
  # Frozen pre-Phase-1 kernel standings (digest-blind). Must stay byte-identical
  # to WorkOrderShape.standings/0; drift means STOP before reminting digests.
  @frozen_standings ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)

  defp canonical(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "SJ-ALIGN-001",
        "title" => "Alignment",
        "description" => "Kernel/shape alignment fixture.",
        "subject" => "urn:subject:align",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:align:1",
        "dependencies" => [],
        "required_courts" => ["court:test"],
        "required_evidence" => ["source"],
        "acceptance" => ["acceptance:test"],
        "falsifiers" => ["falsifier:test"],
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

  describe "admit_work_order/1 (canonical)" do
    test "a canonical order whose identity matches the shape pattern admits" do
      assert Regex.match?(@identity_regex, "SJ-ALIGN-001")
      assert {:ok, admitted} = SemanticJira.admit_work_order(canonical())
      assert admitted["identity"] == "SJ-ALIGN-001"
      assert admitted["authority"] == "NONE"
    end

    test "blank identity is still refused" do
      assert {:error, {:refused_work_order, _}} =
               SemanticJira.admit_work_order(canonical(%{"identity" => ""}))
    end
  end

  describe "B1 identifier pattern (pinned divergence)" do
    test "shape file carries the identifier pattern" do
      assert File.read!(@shape) =~ ~S|sh:pattern "^[A-Z][A-Z0-9-]{1,63}$"|
    end

    test "kernel currently admits a one-character identity the shape would refuse" do
      refute Regex.match?(@identity_regex, "A")
      assert {:ok, _} = SemanticJira.admit_work_order(canonical(%{"identity" => "A"}))
    end
  end

  describe "B3 path_scope (pinned divergence)" do
    test "kernel admits an omitted path_scope and normalizes it to []" do
      order = Map.delete(canonical(), "path_scope")
      assert {:ok, admitted} = SemanticJira.admit_work_order(order)
      assert admitted["path_scope"] == []
    end

    test "malformed path_scope entries are still refused" do
      assert {:error, {:refused_work_order, {:invalid_path_scope, _}}} =
               SemanticJira.admit_work_order(canonical(%{"path_scope" => ["/abs"]}))
    end
  end

  describe "B4 required_receipt_classes (deliberate default)" do
    test "omitted classes default to [] while the shape requires minCount 1" do
      order = Map.delete(canonical(), "required_receipt_classes")
      assert {:ok, admitted} = SemanticJira.admit_work_order(order)
      assert admitted["required_receipt_classes"] == []
      assert File.read!(@shape) =~ "default"
    end

    test "an unsupported receipt class is still refused" do
      assert {:error, {:refused_work_order, {:unsupported_receipt_class, "bogus"}}} =
               SemanticJira.admit_work_order(
                 canonical(%{"required_receipt_classes" => ["bogus"]})
               )
    end
  end

  describe "Phase 1 WorkOrderShape standings/patterns (digest-safe)" do
    test "generated standings equal the frozen kernel expectation" do
      assert WorkOrderShape.standings() == @frozen_standings
      assert WorkOrderShape.frozen_standings() == @frozen_standings
      assert SemanticJira.standings() == @frozen_standings
    end

    test "shape file still carries the REFUSED arm the kernel keeps separate" do
      assert WorkOrderShape.standing_shacl_pattern() =~ "REFUSED"
      assert File.read!(@shape) =~ ~S|sj:standing|
      assert File.read!(@shape) =~ "REFUSED"
    end

    test "sha/repo/pack/digest patterns still admit the canonical fixture" do
      assert Regex.match?(WorkOrderShape.sha_pattern(), String.duplicate("a", 40))
      assert Regex.match?(WorkOrderShape.repo_pattern(), "seanchatmangpt/ggen_igniter")
      assert Regex.match?(WorkOrderShape.pack_name_pattern(), "semantic-jira-pack")

      assert Regex.match?(
               WorkOrderShape.digest_pattern(),
               "sha256:" <> String.duplicate("b", 64)
             )

      assert {:ok, _} = SemanticJira.admit_work_order(canonical())
    end
  end
end
