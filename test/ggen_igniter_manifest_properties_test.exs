defmodule GgenIgniterManifestPropertiesTest do
  @moduledoc """
  Chicago-style: real property-based testing via StreamData/ExUnitProperties --
  StreamData generators drive real calls into `GgenIgniter.Manifest`'s pure
  functions (`recipe_key/2`, `hash_content/1`, `output_paths/1`,
  `stale_paths/2`, `same_outputs?/2`) against real generated inputs, and every
  assertion is on the real returned value. No test doubles are used anywhere
  in this file (nothing here is a collaborator to fake in the first place --
  every function under test is pure), fully compatible with this repo's
  Chicago-testing rule (`~/.claude/rules/testing-chicago-style.md`,
  `test/CLAUDE.md`).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Manifest

  describe "hash_content/1 (property)" do
    property "is deterministic: same binary content always hashes the same" do
      check all(content <- StreamData.binary()) do
        assert Manifest.hash_content(content) == Manifest.hash_content(content)
      end
    end

    property "output always matches the sha256:<64 lowercase hex> shape" do
      check all(content <- StreamData.binary()) do
        assert Manifest.hash_content(content) =~ ~r/^sha256:[0-9a-f]{64}$/
      end
    end
  end

  describe "recipe_key/2 (property)" do
    property "different (template_path, out_template) pairs produce different keys, for well-formed inputs with no embedded \"=>\"" do
      no_arrow_string =
        StreamData.string(:printable, min_length: 1)
        |> StreamData.filter(&(not String.contains?(&1, "=>")))

      check all(
              template_a <- no_arrow_string,
              out_a <- no_arrow_string,
              template_b <- no_arrow_string,
              out_b <- no_arrow_string,
              {template_a, out_a} != {template_b, out_b}
            ) do
        assert Manifest.recipe_key(template_a, out_a) != Manifest.recipe_key(template_b, out_b)
      end
    end
  end

  test "recipe_key/2's known adversarial collision: an embedded \"=>\" in template_path can collide two different (template, out_template) pairs" do
    # This is a real, disclosed limitation of the "=>"-separator key scheme
    # (see GgenIgniter.Manifest's moduledoc), not a universal-injectivity
    # property -- documented here as a named unit test rather than
    # (falsely) asserted as a property over arbitrary strings.
    template_a = "foo=>bar"
    out_a = "baz"

    template_b = "foo"
    out_b = "bar=>baz"

    assert Manifest.recipe_key(template_a, out_a) == Manifest.recipe_key(template_b, out_b)
  end

  describe "output_paths/1 (property)" do
    property "returns a MapSet of exactly the N generated output path keys in the entry" do
      check all(
              paths <-
                StreamData.list_of(StreamData.string(:printable, min_length: 1), max_length: 20),
              hash <- StreamData.string(:printable, min_length: 1)
            ) do
        outputs = Map.new(paths, fn p -> {p, hash} end)
        entry = %{"outputs" => outputs}

        assert Manifest.output_paths(entry) == MapSet.new(Map.keys(outputs))
      end
    end

    property "returns an empty MapSet for nil" do
      check all(_dummy <- StreamData.constant(:ignored)) do
        assert Manifest.output_paths(nil) == MapSet.new()
      end
    end
  end

  describe "stale_paths/2 (property)" do
    property "is real set difference: stale_paths(entry, new_paths) == MapSet.difference(old, new)" do
      check all(
              old_paths <-
                StreamData.list_of(StreamData.string(:printable, min_length: 1), max_length: 20),
              new_paths <-
                StreamData.list_of(StreamData.string(:printable, min_length: 1), max_length: 20)
            ) do
        entry = %{"outputs" => Map.new(old_paths, fn p -> {p, "sha256:ignored"} end)}

        expected = MapSet.difference(MapSet.new(old_paths), MapSet.new(new_paths))

        assert Manifest.stale_paths(entry, new_paths) == expected
      end
    end
  end

  describe "same_outputs?/2 (property)" do
    property "is reflexive: same_outputs?(entry, outputs_from_that_same_entry) is always true" do
      check all(
              paths <-
                StreamData.list_of(StreamData.string(:printable, min_length: 1), max_length: 20),
              hash <- StreamData.string(:printable, min_length: 1)
            ) do
        outputs = Map.new(paths, fn p -> {p, hash} end)
        entry = %{"outputs" => outputs}

        assert Manifest.same_outputs?(entry, outputs)
      end
    end

    property "detects any single-key value change as false" do
      check all(
              paths <-
                StreamData.list_of(StreamData.string(:printable, min_length: 1),
                  min_length: 1,
                  max_length: 20
                ),
              hash <- StreamData.string(:printable, min_length: 1),
              changed_hash <- StreamData.string(:printable, min_length: 1),
              changed_hash != hash
            ) do
        outputs = Map.new(paths, fn p -> {p, hash} end)
        entry = %{"outputs" => outputs}

        [changed_path | _] = paths
        mutated_outputs = Map.put(outputs, changed_path, changed_hash)

        refute Manifest.same_outputs?(entry, mutated_outputs)
      end
    end
  end
end
