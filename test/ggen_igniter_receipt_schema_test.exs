defmodule GgenIgniterReceiptSchemaTest do
  @moduledoc """
  Validates `priv/schema/receipt.schema.json` (JSON Schema draft 2020-12,
  describing the real shape emitted by `GgenIgniter.Receipt.to_json_map/1`)
  against real fixture receipt JSON files under `test/fixtures/receipts/`.

  ## Why a hand-rolled validator, not a dependency

  `mix.exs`/`mix.lock` at the time this test was written have no JSON-schema
  validation library (`ex_json_schema` or equivalent) in deps -- only
  `jason` (already a direct dependency, used for real elsewhere in this repo,
  e.g. `GgenIgniter.Receipt.append!/2`, `GgenIgniter.Manifest`). Per the task
  instruction ("if none exists, write a minimal structural validator in
  Elixir rather than adding a new heavy dependency"), this module implements
  a real, minimal, non-mocked structural validator against the concrete
  constraint shapes `priv/schema/receipt.schema.json` actually uses --
  `type` (incl. arrays of allowed types for nullable fields), `required`,
  `additionalProperties: false`, `enum`, `pattern`, `items.type`. It is NOT
  a general JSON Schema draft 2020-12 implementation ($ref, allOf/anyOf,
  numeric bounds, etc. are out of scope) -- only the subset this one schema
  file exercises. This is a real, state-based check (parses real fixture
  JSON, walks the real schema map, returns real :ok/{:error, reasons}) --
  not an interaction-based mock of a validator.
  """

  use ExUnit.Case, async: true

  @schema_path Path.join([__DIR__, "..", "priv", "schema", "receipt.schema.json"])
  @fixtures_dir Path.join([__DIR__, "fixtures", "receipts"])

  setup_all do
    schema = @schema_path |> File.read!() |> Jason.decode!()
    {:ok, schema: schema}
  end

  defp load_fixture!(name) do
    @fixtures_dir |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  # ---- minimal structural validator -----------------------------------

  defp validate(schema, data) when is_map(schema) and is_map(data) do
    errors =
      []
      |> check_type(schema, data)
      |> check_required(schema, data)
      |> check_additional_properties(schema, data)
      |> check_properties(schema, data)

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp check_type(errors, %{"type" => "object"}, data) when is_map(data), do: errors
  defp check_type(errors, %{"type" => "object"}, _data), do: ["not an object" | errors]
  defp check_type(errors, _schema, _data), do: errors

  defp check_required(errors, %{"required" => required}, data) do
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    case missing do
      [] -> errors
      _ -> ["missing required keys: #{inspect(missing)}" | errors]
    end
  end

  defp check_required(errors, _schema, _data), do: errors

  defp check_additional_properties(
         errors,
         %{"additionalProperties" => false, "properties" => props},
         data
       ) do
    allowed = Map.keys(props)
    extra = Enum.filter(Map.keys(data), &(&1 not in allowed))

    case extra do
      [] -> errors
      _ -> ["unexpected keys: #{inspect(extra)}" | errors]
    end
  end

  defp check_additional_properties(errors, _schema, _data), do: errors

  defp check_properties(errors, %{"properties" => props}, data) do
    Enum.reduce(props, errors, fn {key, prop_schema}, acc ->
      case Map.fetch(data, key) do
        {:ok, value} -> validate_property(acc, key, prop_schema, value)
        :error -> acc
      end
    end)
  end

  defp check_properties(errors, _schema, _data), do: errors

  defp validate_property(errors, key, prop_schema, value) do
    errors
    |> validate_field_type(key, prop_schema, value)
    |> validate_enum(key, prop_schema, value)
    |> validate_pattern(key, prop_schema, value)
    |> validate_items(key, prop_schema, value)
  end

  defp validate_field_type(errors, key, %{"type" => types}, value) when is_list(types) do
    if Enum.any?(types, &json_type_matches?(&1, value)) do
      errors
    else
      ["#{key}: expected one of #{inspect(types)}, got #{inspect(value)}" | errors]
    end
  end

  defp validate_field_type(errors, key, %{"type" => type}, value) when is_binary(type) do
    if json_type_matches?(type, value) do
      errors
    else
      ["#{key}: expected #{type}, got #{inspect(value)}" | errors]
    end
  end

  defp validate_field_type(errors, _key, _prop_schema, _value), do: errors

  defp json_type_matches?("string", v), do: is_binary(v)
  defp json_type_matches?("null", v), do: is_nil(v)
  defp json_type_matches?("object", v), do: is_map(v)
  defp json_type_matches?("array", v), do: is_list(v)
  defp json_type_matches?("number", v), do: is_number(v)
  defp json_type_matches?("integer", v), do: is_integer(v)
  defp json_type_matches?("boolean", v), do: is_boolean(v)
  defp json_type_matches?(_other, _v), do: false

  defp validate_enum(errors, key, %{"enum" => allowed}, value) when not is_nil(value) do
    if value in allowed do
      errors
    else
      ["#{key}: #{inspect(value)} not in enum #{inspect(allowed)}" | errors]
    end
  end

  defp validate_enum(errors, _key, _prop_schema, _value), do: errors

  defp validate_pattern(errors, key, %{"pattern" => pattern}, value)
       when is_binary(value) do
    {:ok, regex} = Regex.compile(pattern)

    if Regex.match?(regex, value) do
      errors
    else
      ["#{key}: #{inspect(value)} does not match pattern #{inspect(pattern)}" | errors]
    end
  end

  defp validate_pattern(errors, _key, _prop_schema, _value), do: errors

  defp validate_items(errors, key, %{"items" => %{"type" => item_type}}, value)
       when is_list(value) do
    bad = Enum.reject(value, &json_type_matches?(item_type, &1))

    case bad do
      [] -> errors
      _ -> ["#{key}: array items not all type #{item_type}: #{inspect(bad)}" | errors]
    end
  end

  defp validate_items(errors, _key, _prop_schema, _value), do: errors

  # ---- tests ------------------------------------------------------------

  test "schema file is real, well-formed JSON Schema draft 2020-12", %{schema: schema} do
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["type"] == "object"
    assert is_map(schema["properties"])
    assert schema["additionalProperties"] == false

    assert schema["required"] == [
             "id",
             "recipe_key",
             "standing",
             "started_at",
             "finished_at",
             "pre_run_hash",
             "post_run_hash",
             "files",
             "events",
             "reason",
             "metadata"
           ]
  end

  test "schema's required/property set matches the real fields GgenIgniter.Receipt.to_json_map/1 emits",
       %{schema: schema} do
    receipt =
      GgenIgniter.Receipt.new(
        id: "rcpt_0000000000000000",
        standing: :alive,
        recipe_key: "a=>b",
        started_at: "2026-08-27T00:00:00.000000Z",
        finished_at: "2026-08-27T00:00:00.000000Z"
      )

    emitted_keys = receipt |> GgenIgniter.Receipt.to_json_map() |> Map.keys() |> Enum.sort()
    # `pack_name`/`pack_digest` (v26.9.30) and the risk fields (v26.10.20) are
    # optional: emitted only when set, so receipt_hash of pre-existing receipts
    # stays stable.
    schema_keys =
      schema["properties"]
      |> Map.keys()
      |> Enum.reject(
        &(&1 in [
          "pack_name",
          "pack_digest",
          "risk_tier",
          "risk_score",
          "risk_approvals",
          "human_minutes"
        ])
      )
      |> Enum.sort()

    assert emitted_keys == schema_keys
  end

  test "schema's standing enum matches GgenIgniter.Receipt.standings/0 exactly", %{schema: schema} do
    # Read the real standings FIRST. `String.to_existing_atom/1` below needs
    # every standing atom to be in the VM's atom table, and the only thing
    # that puts them there is `GgenIgniter.Receipt` being loaded -- module
    # attributes live in the module's literal pool, not in the atom table of
    # a VM that has never loaded it. Calling `standings/0` after the map left
    # that load to chance: passing alone and under any seed, but raising
    # `ArgumentError: not an already existing atom` on "compensation_failed"
    # in a full-suite run once the suite grew past ~700 tests and this file
    # stopped happening to run after something that loaded Receipt.
    #
    # This is ordering, not strength: `to_existing_atom/1` still refuses an
    # enum value that is not a real standing, which is the property under
    # test.
    standings = GgenIgniter.Receipt.standings()

    schema_enum =
      schema["properties"]["standing"]["enum"]
      |> Enum.map(&String.to_existing_atom/1)
      |> Enum.sort()

    assert schema_enum == Enum.sort(standings)
  end

  test "valid fixture validates successfully", %{schema: schema} do
    data = load_fixture!("valid.json")
    assert validate(schema, data) == :ok
  end

  test "missing-required fixture fails validation with the missing key named", %{schema: schema} do
    data = load_fixture!("missing_required.json")

    assert {:error, errors} = validate(schema, data)
    assert Enum.any?(errors, &String.contains?(&1, "finished_at"))
  end

  test "bad-standing-enum fixture fails validation", %{schema: schema} do
    data = load_fixture!("bad_standing_enum.json")

    assert {:error, errors} = validate(schema, data)
    assert Enum.any?(errors, &String.contains?(&1, "invented_standing"))
  end

  test "bad-hash-format fixture fails validation on pre_run_hash pattern", %{schema: schema} do
    data = load_fixture!("bad_hash_format.json")

    assert {:error, errors} = validate(schema, data)
    assert Enum.any?(errors, &String.contains?(&1, "pre_run_hash"))
  end

  test "a real GgenIgniter.Receipt.append!/2 round trip produces a receipt line that validates",
       %{
         schema: schema
       } do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_schema_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    receipt =
      GgenIgniter.Receipt.new(
        standing: :alive,
        recipe_key: "templates/x.eex=>lib/x.ex",
        files: ["lib/x.ex"],
        pre_run_hash: GgenIgniter.Receipt.hash_entries([{"lib/x.ex", nil}]),
        post_run_hash: GgenIgniter.Receipt.hash_entries([{"lib/x.ex", "defmodule X do end"}])
      )

    :ok = GgenIgniter.Receipt.append!(tmp_dir, receipt)

    [line] = GgenIgniter.Receipt.read_all!(tmp_dir)

    assert validate(schema, line) == :ok
  end

  # -- Lane L3 (v26.10.20): additive risk-classification fields ---------------

  describe "risk_tier/risk_score/risk_approvals (lane L3, additive)" do
    @old_shape_receipt %{
      id: "rcpt_0000000000000000",
      standing: :alive,
      recipe_key: "a=>b",
      started_at: "2026-08-27T00:00:00.000000Z",
      finished_at: "2026-08-27T00:00:00.000000Z"
    }

    test "old-shape receipt (no risk fields) has a stable receipt_hash" do
      r = GgenIgniter.Receipt.new(@old_shape_receipt)
      assert r.risk_tier == nil and r.risk_score == nil and r.risk_approvals == nil

      # to_json_map must not emit the risk keys at all when unset (same
      # put_optional precedent as pack_name/pack_digest).
      refute Map.has_key?(GgenIgniter.Receipt.to_json_map(r), "risk_tier")
      refute Map.has_key?(GgenIgniter.Receipt.to_json_map(r), "risk_score")
      refute Map.has_key?(GgenIgniter.Receipt.to_json_map(r), "risk_approvals")

      # Deterministic: identical old-shape attrs rebuild to the same hash.
      assert GgenIgniter.Receipt.new(@old_shape_receipt).receipt_hash == r.receipt_hash
    end

    test "round-trip with risk fields populated: emitted as strings/ints, hash covers them" do
      r =
        GgenIgniter.Receipt.new(
          standing: :alive,
          recipe_key: "a=>b",
          risk_tier: :high,
          risk_score: 12,
          risk_approvals: 2
        )

      json_map = GgenIgniter.Receipt.to_json_map(r)

      assert json_map["risk_tier"] == "high"
      assert json_map["risk_score"] == 12
      assert json_map["risk_approvals"] == 2

      # Hash covers the new fields: removing them changes the digest.
      stripped = Map.delete(json_map, "risk_tier") |> Map.delete("risk_score") |> Map.delete("risk_approvals")

      hash_of_stripped =
        stripped
        |> Enum.sort_by(&elem(&1, 0))
        |> Map.new()
        |> Jason.encode!()
        |> then(&("sha256:" <> GgenIgniter.Digest.hex(&1)))

      assert r.receipt_hash != hash_of_stripped
    end

    test "risk_tier round-trips through Jason encode/decode" do
      r =
        GgenIgniter.Receipt.new(
          standing: :compensated,
          risk_tier: :medium,
          risk_score: 5,
          risk_approvals: 1
        )

      encoded = r |> GgenIgniter.Receipt.to_json_map() |> Jason.encode!() |> Jason.decode!()

      assert encoded["risk_tier"] == "medium"
      assert encoded["risk_score"] == 5
      assert encoded["risk_approvals"] == 1
    end

    test "a populated receipt's to_json_map validates against the real schema", %{schema: schema} do
      r =
        GgenIgniter.Receipt.new(
          standing: :alive,
          recipe_key: "a=>b",
          risk_tier: :high,
          risk_score: 12,
          risk_approvals: 2
        )

      populated = r |> GgenIgniter.Receipt.to_json_map() |> Jason.encode!() |> Jason.decode!()
      assert validate(schema, populated) == :ok
    end

    test "an old-shape receipt (no risk keys) still validates against the real schema", %{
      schema: schema
    } do
      old = GgenIgniter.Receipt.new(@old_shape_receipt)

      old_json = old |> GgenIgniter.Receipt.to_json_map() |> Jason.encode!() |> Jason.decode!()
      assert validate(schema, old_json) == :ok
    end
  end

  # -- Lane C18 (v26.10.20): additive F2 measurement field ---------------------

  describe "human_minutes (lane C18, additive F2 seed)" do
    test "schema declares human_minutes as integer-or-null, not required" do
      schema = @schema_path |> File.read!() |> Jason.decode!()

      assert schema["properties"]["human_minutes"]["type"] == ["integer", "null"]
      refute "human_minutes" in schema["required"]
    end

    test "a receipt carrying human_minutes: 42 validates against the schema", %{schema: schema} do
      data = @old_shape_receipt |> GgenIgniter.Receipt.new() |> GgenIgniter.Receipt.to_json_map() |> Map.put("human_minutes", 42)

      assert validate(schema, Jason.decode!(Jason.encode!(data))) == :ok
    end

    test "a receipt carrying human_minutes: null validates against the schema", %{schema: schema} do
      data =
        @old_shape_receipt
        |> GgenIgniter.Receipt.new()
        |> GgenIgniter.Receipt.to_json_map()
        |> Map.put("human_minutes", nil)

      assert validate(schema, Jason.decode!(Jason.encode!(data))) == :ok
    end

    test "a non-integer human_minutes fails schema type validation", %{schema: schema} do
      data =
        @old_shape_receipt
        |> GgenIgniter.Receipt.new()
        |> GgenIgniter.Receipt.to_json_map()
        |> Map.put("human_minutes", "forty-two")

      assert {:error, errors} = validate(schema, Jason.decode!(Jason.encode!(data)))
      assert Enum.any?(errors, &String.contains?(&1, "human_minutes"))
    end

    test "an old-shape receipt (no human_minutes key) still validates — the field is additive", %{
      schema: schema
    } do
      old = GgenIgniter.Receipt.new(@old_shape_receipt)

      refute Map.has_key?(GgenIgniter.Receipt.to_json_map(old), "human_minutes")

      old_json = old |> GgenIgniter.Receipt.to_json_map() |> Jason.encode!() |> Jason.decode!()
      assert validate(schema, old_json) == :ok
    end

    @tag :tmp_dir
    test "landing receipt emits human_minutes only when set (put_optional, old shape stable)" do
      tmp_root =
        Path.join(System.tmp_dir!(), "ggen_igniter_human_minutes_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_root)
      on_exit(fn -> File.rm_rf!(tmp_root) end)

      base_opts = [base: "HEAD", run_id: "pl-human-minutes-probe"]

      {0, old_report} =
        GgenIgniter.LandingPipeline.run(
          [stages: [], receipts_dir: Path.join(tmp_root, "old")] ++ base_opts
        )

      refute Map.has_key?(old_report, "human_minutes")
      assert old_report["status"] == "ALIVE"

      {0, new_report} =
        GgenIgniter.LandingPipeline.run(
          [stages: [], receipts_dir: Path.join(tmp_root, "new"), human_minutes: 42] ++ base_opts
        )

      assert new_report["human_minutes"] == 42

      # Non-integer input is refused silently: no key, same shape as unset.
      {0, bad_report} =
        GgenIgniter.LandingPipeline.run(
          [stages: [], receipts_dir: Path.join(tmp_root, "bad"), human_minutes: "42"] ++
            base_opts
        )

      refute Map.has_key?(bad_report, "human_minutes")

      # The persisted landing-receipt.json matches the returned report shape.
      persisted =
        Path.join([tmp_root, "new", "pl-human-minutes-probe", "landing-receipt.json"])
        |> File.read!()
        |> Jason.decode!()

      assert persisted["human_minutes"] == 42
    end
  end
end
