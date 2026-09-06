defmodule GgenIgniter.RuntimeShapeTest do
  @moduledoc "Chicago-style: exercises the real RuntimeShape constructor, canonicalizer, Jason encoder, and crypto digest implementation with no test doubles."

  use ExUnit.Case, async: true

  alias GgenIgniter.RuntimeShape

  defp base_attrs do
    %{
      subject_id: "urn:example:ticket",
      source_digest: "sha256:source",
      graph_digest: "sha256:graph",
      ontology_versions: %{"prov" => "2013", "ash" => "3"},
      attributes: [
        %{"name" => "id", "type" => "uuid", "constraints" => %{"allow_nil" => false}}
      ],
      relationships: [],
      actions: [%{"name" => "read", "kind" => "read"}],
      public_facets: [%{"term" => "prov:Entity"}],
      native_facets: %{"ash" => [%{"capability" => "read"}]},
      admission: %{"status" => "admitted", "profile" => "runtime-shape-v1"}
    }
  end

  describe "new!/1 (portable admitted shape)" do
    test "computes a content digest and preserves the admitted semantic fields" do
      shape = RuntimeShape.new!(base_attrs())

      assert shape.schema_version == RuntimeShape.schema_version()
      assert shape.subject_id == "urn:example:ticket"
      assert String.starts_with?(shape.shape_digest, "sha256:")
      assert shape.shape_digest == RuntimeShape.digest(shape)
    end

    test "map insertion order, including nested maps, does not change identity" do
      first = RuntimeShape.new!(base_attrs())

      reordered =
        RuntimeShape.new!(%{
          admission: %{"profile" => "runtime-shape-v1", "status" => "admitted"},
          native_facets: %{"ash" => [%{"capability" => "read"}]},
          public_facets: [%{"term" => "prov:Entity"}],
          actions: [%{"kind" => "read", "name" => "read"}],
          relationships: [],
          attributes: [
            %{"constraints" => %{"allow_nil" => false}, "type" => "uuid", "name" => "id"}
          ],
          ontology_versions: %{"ash" => "3", "prov" => "2013"},
          graph_digest: "sha256:graph",
          source_digest: "sha256:source",
          subject_id: "urn:example:ticket"
        })

      assert first.shape_digest == reordered.shape_digest
    end

    test "list order remains semantic and changes identity" do
      first = RuntimeShape.new!(base_attrs())

      reversed_actions =
        base_attrs()
        |> Map.put(:actions, [
          %{"name" => "update", "kind" => "update"},
          %{"name" => "read", "kind" => "read"}
        ])
        |> RuntimeShape.new!()

      same_actions_different_order =
        base_attrs()
        |> Map.put(:actions, [
          %{"name" => "read", "kind" => "read"},
          %{"name" => "update", "kind" => "update"}
        ])
        |> RuntimeShape.new!()

      refute reversed_actions.shape_digest == same_actions_different_order.shape_digest
      refute first.shape_digest == reversed_actions.shape_digest
    end
  end

  describe "new/1 (fail-closed input boundary)" do
    test "refuses unknown top-level string keys without creating arbitrary atoms" do
      attrs = Map.put(base_attrs(), "totally_external_field", "value")

      assert {:error, [{:unknown_field, "totally_external_field"}]} = RuntimeShape.new(attrs)
    end

    test "refuses executable and runtime-only values recursively" do
      attrs =
        base_attrs()
        |> Map.put(:native_facets, %{"ash" => [%{"callback" => fn -> :ok end}]})
        |> Map.put(:provenance, %{"observer" => self()})

      assert {:error, errors} = RuntimeShape.new(attrs)
      assert Enum.any?(errors, &match?({:nonportable_value, _, :function}, &1))
      assert Enum.any?(errors, &match?({:nonportable_value, _, :pid}, &1))
    end

    test "refuses missing or invalid required identity fields" do
      attrs = base_attrs() |> Map.delete(:subject_id) |> Map.put(:graph_digest, nil)

      assert {:error, errors} = RuntimeShape.new(attrs)
      assert {:invalid_field, :subject_id, nil} in errors
      assert {:invalid_field, :graph_digest, nil} in errors
    end
  end

  describe "to_map/1 and from_map/1 (portable interchange)" do
    test "round-trips through real Jason JSON with stable semantic identity" do
      original = RuntimeShape.new!(base_attrs())

      decoded =
        original
        |> RuntimeShape.to_map()
        |> Jason.encode!()
        |> Jason.decode!()

      assert {:ok, restored} = RuntimeShape.from_map(decoded)
      assert restored.shape_digest == original.shape_digest
      assert RuntimeShape.semantic_map(restored) == RuntimeShape.semantic_map(original)
    end
  end
end
