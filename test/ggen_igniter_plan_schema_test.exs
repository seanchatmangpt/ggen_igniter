defmodule GgenIgniter.PlanSchemaTest.Validator do
  @moduledoc """
  A real, minimal, recursive JSON Schema (draft-07 subset) validator, local
  to this test file since this project has no `ex_json_schema`-equivalent
  dependency (see `mix.exs`). Supports exactly the keywords
  `priv/schema/plan.schema.json` uses: `type` (including an array of
  alternative types, e.g. `["string", "null"]`), `required`, `properties`,
  `additionalProperties: false`, `enum`, `items` (array validation),
  `pattern` (regex), and `minimum`. Returns `:ok` or `{:error, [String.t()]}`
  with one located, human-readable message per real violation found (not
  just the first) -- `path` threading (`"outputs[0].operation"`,
  `"mutations_intended.writes"`) is real, not decorative, so each test can
  assert on the SPECIFIC violation it constructed the fixture to trigger.
  """

  @spec validate(map(), term()) :: :ok | {:error, [String.t()]}
  def validate(schema, data) do
    case check(schema, data, "$") do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check(schema, data, path) do
    []
    |> check_type(schema, data, path)
    |> check_enum(schema, data, path)
    |> check_pattern(schema, data, path)
    |> check_minimum(schema, data, path)
    |> check_object(schema, data, path)
    |> check_array(schema, data, path)
  end

  defp check_type(errors, %{"type" => types}, data, path) do
    types = List.wrap(types)

    if Enum.any?(types, &type_matches?(&1, data)) do
      errors
    else
      [
        "#{display(path)}: expected type #{inspect(types)}, got #{inspect(data)}"
        | errors
      ]
    end
  end

  defp check_type(errors, _schema, _data, _path), do: errors

  defp type_matches?("object", data), do: is_map(data)
  defp type_matches?("array", data), do: is_list(data)
  defp type_matches?("string", data), do: is_binary(data)
  defp type_matches?("integer", data), do: is_integer(data)
  defp type_matches?("number", data), do: is_number(data)
  defp type_matches?("boolean", data), do: is_boolean(data)
  defp type_matches?("null", data), do: is_nil(data)
  defp type_matches?(_other, _data), do: false

  defp check_enum(errors, %{"enum" => allowed}, data, path) do
    if data in allowed do
      errors
    else
      ["#{display(path)}: value #{inspect(data)} not in enum #{inspect(allowed)}" | errors]
    end
  end

  defp check_enum(errors, _schema, _data, _path), do: errors

  defp check_pattern(errors, %{"pattern" => pattern}, data, path) when is_binary(data) do
    if Regex.match?(Regex.compile!(pattern), data) do
      errors
    else
      [
        "#{display(path)}: value #{inspect(data)} does not match pattern #{inspect(pattern)}"
        | errors
      ]
    end
  end

  defp check_pattern(errors, _schema, _data, _path), do: errors

  defp check_minimum(errors, %{"minimum" => min}, data, path) when is_number(data) do
    if data >= min do
      errors
    else
      ["#{display(path)}: value #{inspect(data)} is below minimum #{inspect(min)}" | errors]
    end
  end

  defp check_minimum(errors, _schema, _data, _path), do: errors

  defp check_object(errors, %{"type" => "object"} = schema, data, path) when is_map(data) do
    properties = Map.get(schema, "properties", %{})
    required = Map.get(schema, "required", [])
    additional_allowed? = Map.get(schema, "additionalProperties", true) != false

    required_errors =
      Enum.reduce(required, [], fn key, acc ->
        if Map.has_key?(data, key) do
          acc
        else
          ["#{display(path)}: missing required property #{inspect(key)}" | acc]
        end
      end)

    additional_errors =
      if additional_allowed? do
        []
      else
        data
        |> Map.keys()
        |> Enum.reject(&Map.has_key?(properties, &1))
        |> Enum.map(&"#{display(path)}: unexpected additional property #{inspect(&1)}")
      end

    property_errors =
      Enum.reduce(properties, [], fn {key, subschema}, acc ->
        case Map.fetch(data, key) do
          {:ok, value} -> check(subschema, value, join(path, key)) ++ acc
          :error -> acc
        end
      end)

    required_errors ++ additional_errors ++ property_errors ++ errors
  end

  defp check_object(errors, _schema, _data, _path), do: errors

  defp check_array(errors, %{"type" => "array", "items" => item_schema}, data, path)
       when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {item, index}, acc ->
      check(item_schema, item, "#{path}[#{index}]") ++ acc
    end)
    |> Kernel.++(errors)
  end

  defp check_array(errors, _schema, _data, _path), do: errors

  # "$" is the root; everything else is displayed relative (no leading "$.")
  # so error messages read "outputs[0].operation", not "$.outputs[0].operation".
  defp display("$"), do: "root"
  defp display("$." <> rest), do: rest
  defp display(other), do: other

  defp join("$", key), do: "$." <> key
  defp join(path, key), do: path <> "." <> key
end

defmodule GgenIgniter.PlanSchemaTest do
  @moduledoc """
  Fixture-based structural validation of `priv/schema/plan.schema.json` -- the
  real JSON Schema (draft-07) describing the pre-actuation PLAN document a
  `mix ggen_igniter.sync` run (or the Reactor pipeline's :admit-bound plan)
  produces: real inputs+hashes, query names+sources+discovered bindings, the
  selected engine, one row per intended output (existing-file decision,
  previous/desired hashes, operation), any requested-but-unsupported
  features, and a summed mutation-intent count.

  No JSON Schema validation library (e.g. `ex_json_schema`) is a dependency
  of this project (see `mix.exs`), so this test implements a real, minimal,
  RECURSIVE structural validator for the exact subset of JSON Schema
  keywords `plan.schema.json` actually uses (`type` incl. arrays of types,
  `required`, `properties`, `additionalProperties: false`, `enum`, `items`,
  `pattern`, `minimum`). This is a real validator against the real schema
  document read from disk -- not a hand-rolled check of the fixture JSON
  against expectations independent of the schema file. A schema edit that
  drops a `required` field or loosens an `enum` is caught by these same
  fixtures without touching this test file, because the schema is loaded
  from disk on every run, never hard-coded here.

  Chicago-school: real files on disk (`priv/schema/plan.schema.json`, the
  `test/fixtures/plan_schema/*.json` fixtures), real `Jason.decode!/1`,
  state-based assertions on the real `{:ok, ...}` / `{:error, errors}`
  return value -- no mocking of any kind.
  """
  use ExUnit.Case, async: true

  @schema_path Path.join([__DIR__, "..", "priv", "schema", "plan.schema.json"])
  @fixtures_dir Path.join([__DIR__, "fixtures", "plan_schema"])

  setup_all do
    schema =
      @schema_path
      |> File.read!()
      |> Jason.decode!()

    {:ok, schema: schema}
  end

  defp load_fixture!(filename) do
    @fixtures_dir
    |> Path.join(filename)
    |> File.read!()
    |> Jason.decode!()
  end

  describe "the schema file itself" do
    test "is real, valid JSON, and declares draft-07" do
      assert File.exists?(@schema_path)
      raw = File.read!(@schema_path)
      assert {:ok, decoded} = Jason.decode(raw)
      assert decoded["$schema"] == "http://json-schema.org/draft-07/schema#"
      assert decoded["type"] == "object"
    end

    test "requires the seven real top-level plan fields", %{schema: schema} do
      assert schema["required"] == [
               "schema_version",
               "generated_at",
               "inputs",
               "engine",
               "queries",
               "outputs",
               "mutations_intended"
             ]
    end
  end

  describe "valid fixture" do
    test "validates cleanly against the real schema", %{schema: schema} do
      plan = load_fixture!("valid_plan.json")
      assert :ok = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
    end
  end

  describe "invalid fixtures -- each fails for the expected, located reason" do
    test "missing required top-level fields (outputs, mutations_intended) is rejected", %{
      schema: schema
    } do
      plan = load_fixture!("invalid_missing_required_top_level.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
      assert Enum.any?(errors, &String.contains?(&1, "missing required property \"outputs\""))

      assert Enum.any?(
               errors,
               &String.contains?(&1, "missing required property \"mutations_intended\"")
             )
    end

    test "an engine.name outside the closed enum is rejected", %{schema: schema} do
      plan = load_fixture!("invalid_bad_engine_enum.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
      assert Enum.any?(errors, &String.contains?(&1, "engine.name"))
      assert Enum.any?(errors, &String.contains?(&1, "not in enum"))
    end

    test "an ontology_hash that doesn't match the sha256: pattern is rejected", %{schema: schema} do
      plan = load_fixture!("invalid_bad_hash_pattern.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
      assert Enum.any?(errors, &String.contains?(&1, "ontology_hash"))
      assert Enum.any?(errors, &String.contains?(&1, "does not match pattern"))
    end

    test "a string where mutations_intended.writes must be an integer is rejected", %{
      schema: schema
    } do
      plan = load_fixture!("invalid_wrong_type.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
      assert Enum.any?(errors, &String.contains?(&1, "mutations_intended.writes"))
      assert Enum.any?(errors, &String.contains?(&1, "expected type"))
    end

    test "an undeclared top-level property is rejected (additionalProperties: false)", %{
      schema: schema
    } do
      plan = load_fixture!("invalid_additional_property.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)

      assert Enum.any?(
               errors,
               &String.contains?(&1, "unexpected additional property \"totally_made_up_field\"")
             )
    end

    test "an outputs[] entry missing required fields (existing_file_decision, previous_hash, desired_hash) is rejected",
         %{schema: schema} do
      plan = load_fixture!("invalid_nested_output_missing_required.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)

      assert Enum.any?(
               errors,
               &String.contains?(
                 &1,
                 "outputs[0]: missing required property \"existing_file_decision\""
               )
             )

      assert Enum.any?(
               errors,
               &String.contains?(&1, "outputs[0]: missing required property \"previous_hash\"")
             )
    end

    test "an outputs[].operation outside the closed enum is rejected", %{schema: schema} do
      plan = load_fixture!("invalid_operation_enum.json")
      assert {:error, errors} = GgenIgniter.PlanSchemaTest.Validator.validate(schema, plan)
      assert Enum.any?(errors, &String.contains?(&1, "outputs[0].operation"))
      assert Enum.any?(errors, &String.contains?(&1, "not in enum"))
    end
  end
end
