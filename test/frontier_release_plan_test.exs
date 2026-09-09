defmodule GgenIgniter.FrontierReleasePlanTest do
  @moduledoc "Chicago-style: exercises the real RuntimeShape collaborator and pure structured plan state with no mocks or shell execution."

  use ExUnit.Case, async: true

  alias GgenIgniter.{FrontierReleasePlan, RuntimeShape}

  defp source_shape do
    RuntimeShape.new!(%{
      subject_id: "opportunity:frontier-release-example",
      source_digest: "sha256:source",
      graph_digest: "sha256:graph",
      ontology_versions: %{"frontier-release-factory" => "0.1.0"},
      admission: %{"standing" => "CANDIDATE", "authority" => "NONE"}
    })
  end

  defp create_attrs do
    %{
      opportunity_id: "frontier-release-example",
      project_name: "frontier_response",
      project_dir: "/tmp/frontier_response",
      target_repository: "seanchatmangpt/frontier-response",
      pack_dir: "/packs/frontier-release-factory-pack",
      response_mode: "compose",
      repository_mode: "create",
      visibility: "public"
    }
  end

  describe "new/2 (content-addressed response plan)" do
    test "creates a portable RuntimeShape projection without execution standing" do
      assert {:ok, plan} = FrontierReleasePlan.new(source_shape(), create_attrs())
      assert :ok = RuntimeShape.validate(plan)
      assert String.starts_with?(plan.shape_digest, "sha256:")
      assert plan.admission["authority_ceiling"] == "CONSTRUCT"
      assert plan.admission["do_intents_require_external_broker"] == true
    end

    test "is deterministic across equivalent input map insertion order" do
      attrs = create_attrs()
      reversed = attrs |> Enum.reverse() |> Map.new()

      assert {:ok, left} = FrontierReleasePlan.new(source_shape(), attrs)
      assert {:ok, right} = FrontierReleasePlan.new(source_shape(), reversed)
      assert left.shape_digest == right.shape_digest
    end

    test "refuses unknown plan fields instead of silently carrying semantics" do
      attrs = Map.put(create_attrs(), :ambient_authority, "DO")

      assert {:error, errors} = FrontierReleasePlan.new(source_shape(), attrs)
      assert {:unknown_fields, ["ambient_authority"]} in errors
    end

    test "new repository project name must match the generated directory identity" do
      attrs = Map.put(create_attrs(), :project_name, "different_name")

      assert {:error, errors} = FrontierReleasePlan.new(source_shape(), attrs)

      assert Enum.any?(errors, fn
               {:project_name_directory_mismatch, "different_name", "/tmp/frontier_response"} ->
                 true

               _ ->
                 false
             end)
    end
  end

  describe "steps/1 (reuse versus create topology)" do
    test "create mode separates reversible manufacture from brokered gh repo create DO" do
      assert {:ok, plan} = FrontierReleasePlan.new(source_shape(), create_attrs())
      assert {:ok, steps} = FrontierReleasePlan.steps(plan)

      assert Enum.map(steps, & &1["id"]) == [
               "scaffold-local-project",
               "manufacture-from-pack",
               "verify-local-project",
               "create-github-repository"
             ]

      assert {:ok, [repository_intent]} = FrontierReleasePlan.do_intents(plan)
      assert repository_intent["executable"] == "gh"
      assert repository_intent["broker_required"] == true
      assert repository_intent["receipt_required"] == true
      assert repository_intent["required_authority"] == "create_repository"
      assert hd(repository_intent["argv"]) == "repo"
    end

    test "reuse mode never scaffolds a replacement project or creates a repository" do
      attrs =
        create_attrs()
        |> Map.put(:repository_mode, "reuse")
        |> Map.put(:response_mode, "extend")

      assert {:ok, plan} = FrontierReleasePlan.new(source_shape(), attrs)
      assert {:ok, steps} = FrontierReleasePlan.steps(plan)
      assert Enum.map(steps, & &1["id"]) == ["manufacture-from-pack", "verify-local-project"]
      assert {:ok, []} = FrontierReleasePlan.do_intents(plan)
    end

    test "construct_intents excludes verification and consequential DO" do
      assert {:ok, plan} = FrontierReleasePlan.new(source_shape(), create_attrs())
      assert {:ok, construct} = FrontierReleasePlan.construct_intents(plan)

      assert Enum.map(construct, & &1["id"]) == [
               "scaffold-local-project",
               "manufacture-from-pack"
             ]

      assert Enum.all?(construct, &(&1["class"] == "CONSTRUCT"))
    end
  end

  describe "authority fence" do
    test "describing gh repo create does not raise the RuntimeShape authority ceiling" do
      assert {:ok, plan} = FrontierReleasePlan.new(source_shape(), create_attrs())
      assert {:ok, [intent]} = FrontierReleasePlan.do_intents(plan)

      assert plan.admission["authority_ceiling"] == "CONSTRUCT"
      assert intent["class"] == "DO"
      assert intent["broker_required"] == true
      assert intent["receipt_required"] == true
    end
  end
end
