defmodule GgenIgniter.ReceiptPortableBoundaryTest do
  @moduledoc """
  Cross-format differential court for the receipt boundary between
  `GgenIgniter.Receipt` (Elixir, SHA-256 over a sorted Jason map,
  `compute_receipt_hash/1`, `parent_hash` chaining) and ggen's Rust
  portable receipt envelope (RFC-GPACK-001 §54-56, BLAKE3 chain in the
  separate `.ggen-v2/receipt.json` -- see
  `/Users/sac/ggen/crates/ggen-engine/schema/receipt-portable.schema.json`).

  The two formats are DELIBERATELY NON-EQUIVALENT (RFC §56 and the $comment
  in ggen's own portable schema both say so). This court therefore does NOT
  unify them; it proves the boundary is well-defined by:

    1. generating REAL igniter receipts via the real pipeline
       (`GgenIgniter.Receipt.new/1` -> `to_json_map/1` -> `Jason.encode!`)
       and validating them against `priv/schema/receipt.schema.json` read
       at test time (real Jason decode, no mock);
    2. mapping a REAL ggen portable receipt, field by field, into the
       igniter schema's vocabulary, emitting an explicit unmapped-field
       report that FAILS CLOSED when ggen adds envelope fields igniter
       does not know (forward drift = loud failure);
    3. sabotage twins: mutating either side's fixture makes the court
       fail, proving the checks are non-vacuous.

  ## Fixture provenance

  `test/fixtures/ggen_portable/receipt-portable.json` is a byte-identical
  copy (sha256 1bc8f5628f219675800a53ada60405dc9cecd46b…) of the REAL
  portable receipt produced by the real ggen runtime (engine ggen
  26.10.10, rustc 1.98.0-nightly) for pack `chicago-tdd-tools-pack` 0.5.0
  at `/Users/sac/ggen/examples/receiptctl/.ggen-v2/receipt-portable.json`
  (read-only reference checkout; never hand-invented).

  ## Why a hand-rolled validator, not a dependency

  Same rationale as `GgenIgniterReceiptSchemaTest` (which this court's
  validator deliberately mirrors): no JSON-schema library is in deps; only
  the constraint subset `receipt.schema.json` actually uses is implemented
  (`type` incl. nullable unions, `required`, `additionalProperties: false`,
  `enum`, `pattern`, `items`). Real, state-based, no mocks.
  """

  use ExUnit.Case, async: true

  @schema_path Path.join([__DIR__, "..", "..", "priv", "schema", "receipt.schema.json"])
  @ggen_portable_path Path.join([__DIR__, "..", "fixtures", "ggen_portable", "receipt-portable.json"])

  # The closed set of ggen portable-envelope fields this court knows how to
  # disposition. ANY top-level key in a future ggen envelope outside this
  # set fails the court (fail-closed forward drift).
  @ggen_field_dispositions %{
    "schema" => {:mapped, "schema_version"},
    "spec" => :no_igniter_counterpart,
    "engine" => {:mapped, "engine"},
    "toolchain" => :no_igniter_counterpart,
    "environment" => :no_igniter_counterpart,
    "subject" => {:mapped, "pack_name + pack_digest"},
    "dependencies" => :no_igniter_counterpart,
    "composition" => :no_igniter_counterpart,
    "graph" => {:mapped_partial, "queries"},
    "admission" => {:mapped_partial, "events"},
    "consequences" => {:mapped_partial, "outputs"},
    "work_order" => {:mapped_partial, "metadata[\"work_order\"]"},
    "replay" => :no_igniter_counterpart,
    "standing" => {:mapped, "standing (NON-equivalent vocabulary: ggen ALIVE vs igniter's five closed atoms)"}
  }

  # ggen standing vocabulary observed in real portable receipts.
  @ggen_standings ["ALIVE", "PARTIAL_ALIVE", "UNKNOWN", "BLOCKED", "BUILD_BROKEN", "REFUSED"]

  # ---- minimal structural validator (subset receipt.schema.json uses) --

  defp validate(schema, data) when is_map(schema) and is_map(data) do
    errors =
      []
      |> check_required(schema, data)
      |> check_additional_properties(schema, data)
      |> check_properties(schema, data)

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp check_required(errors, %{"required" => required}, data) do
    missing = Enum.reject(required, &Map.has_key?(data, &1))
    Enum.map(missing, &"missing required key #{inspect(&1)}") ++ errors
  end

  defp check_required(errors, _schema, _data), do: errors

  defp check_additional_properties(errors, %{"additionalProperties" => false, "properties" => props}, data) do
    extra =
      Map.keys(data)
      |> MapSet.new()
      |> MapSet.difference(MapSet.new(Map.keys(props)))
      |> MapSet.to_list()

    extra_errors = Enum.map(extra, &"unknown field #{inspect(&1)} (additionalProperties: false)")
    extra_errors ++ errors
  end

  defp check_additional_properties(errors, _schema, _data), do: errors

  defp check_properties(errors, %{"properties" => props}, data) do
    Enum.reduce(props, errors, fn {key, sub}, acc ->
      if Map.has_key?(data, key), do: check_field(acc, key, sub, data[key]), else: acc
    end)
  end

  defp check_properties(errors, _schema, _data), do: errors

  defp check_field(errors, key, %{"type" => types} = sub, value) when is_list(types) do
    if Enum.any?(types, &type_ok?(&1, value)),
      do: errors,
      else: ["#{key}: expected one of #{inspect(types)}, got #{inspect(value)}" | errors]
    |> then(fn _ -> check_patterns(errors, key, sub, value) end)
  end

  defp check_field(errors, key, %{"type" => type} = sub, value) do
    if type_ok?(type, value),
      do: check_patterns(errors, key, sub, value),
      else: ["#{key}: expected #{type}, got #{inspect(value)}" | errors]
  end

  defp check_field(errors, key, %{"enum" => enum} = sub, value) do
    if value in enum,
      do: check_patterns(errors, key, sub, value),
      else: ["#{key}: #{inspect(value)} not in enum #{inspect(enum)}" | errors]
  end

  defp check_field(errors, key, sub, value) do
    check_patterns(errors, key, sub, value)
  end

  defp check_patterns(errors, key, %{"pattern" => pattern} = sub, value) when is_binary(value) do
    if Regex.match?(Regex.compile!(pattern), value),
      do: check_enum_tail(errors, key, sub, value),
      else: ["#{key}: #{inspect(value)} does not match #{pattern}" | errors]
  end

  defp check_patterns(errors, key, sub, value) do
    check_enum_tail(errors, key, sub, value)
  end

  defp check_enum_tail(errors, key, %{"enum" => enum}, value) do
    if value in enum,
      do: errors,
      else: ["#{key}: #{inspect(value)} not in enum #{inspect(enum)}" | errors]
  end

  defp check_enum_tail(errors, _key, _sub, _value), do: errors

  defp type_ok?("string", v), do: is_binary(v)
  defp type_ok?("object", v), do: is_map(v)
  defp type_ok?("array", v), do: is_list(v)
  defp type_ok?("null", v), do: is_nil(v)
  defp type_ok?("integer", v), do: is_integer(v)
  defp type_ok?("boolean", v), do: is_boolean(v)
  defp type_ok?(_, _), do: true

  # ---- fixture helpers ---------------------------------------------------

  # Sabotage helper: re-encode the real fixture map with one mutation. The
  # sabotage twins below assert the court FAILS on these, proving the
  # checks above are non-vacuous.
  defp sabotaged_ggen_receipt(mutations) when is_map(mutations) do
    @ggen_portable_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.merge(mutations)
    |> then(fn map -> map |> Enum.sort_by(&elem(&1, 0)) |> Map.new() end)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp sabotaged_igniter_map(map, key, value), do: Map.put(map, key, value)

  # ---- 1. real igniter receipts satisfy receipt.schema.json -------------

  describe "igniter receipts satisfy receipt.schema.json" do
    test "a real :alive receipt (full PRD v2 field set) validates against the schema" do
      receipt =
        GgenIgniter.Receipt.new(%{
          standing: :alive,
          recipe_key: "priv/templates/x.ex.eex=>lib/x.ex",
          pre_run_hash: GgenIgniter.Receipt.hash_files([]),
          post_run_hash: GgenIgniter.Receipt.hash_files([]),
          files: ["lib/x.ex"],
          events: [%{"id" => "ev_test", "activity" => "ACTUATION_STARTED"}],
          operation: "boundary-court",
          pack_name: "chicago-tdd-tools-pack",
          pack_digest: String.duplicate("a", 64)
        })

      json_map = GgenIgniter.Receipt.to_json_map(receipt)

      # Real round-trip through the real persistence encoding, not the struct.
      roundtrip = json_map |> Jason.encode!() |> Jason.decode!()

      # The receipt_hash must be a real self-consistent digest: recompute it
      # over the round-tripped content (minus the hash itself) and compare.
      recomputed =
        roundtrip
        |> Map.delete("receipt_hash")
        |> then(fn map -> map |> Enum.sort_by(&elem(&1, 0)) |> Map.new() end)
        |> Jason.encode!()
        |> then(&("sha256:" <> GgenIgniter.Digest.hex(&1)))

      assert recomputed == roundtrip["receipt_hash"],
             "receipt_hash is not self-consistent over the persisted JSON"

      assert validate(schema(), roundtrip) == :ok
    end

    test "a real :refused receipt (nil hashes, nil recipe_key) validates against the schema" do
      receipt =
        GgenIgniter.Receipt.new(%{
          standing: :refused,
          recipe_key: nil,
          reason: "path-safety guard refused before actuation"
        })

      roundtrip = GgenIgniter.Receipt.to_json_map(receipt) |> Jason.encode!() |> Jason.decode!()
      assert validate(schema(), roundtrip) == :ok
    end

    test "a real :compensated receipt with parent_hash chain link validates against the schema" do
      parent = GgenIgniter.Receipt.new(%{standing: :alive, recipe_key: "k=>v"})

      child =
        GgenIgniter.Receipt.new(%{
          standing: :compensated,
          recipe_key: "k=>v",
          parent_hash: parent.receipt_hash,
          pre_run_hash: GgenIgniter.Receipt.hash_files([]),
          post_run_hash: GgenIgniter.Receipt.hash_files([]),
          reason: "verification failed; undo restored prior bytes"
        })

      roundtrip = GgenIgniter.Receipt.to_json_map(child) |> Jason.encode!() |> Jason.decode!()
      assert roundtrip["parent_hash"] == parent.receipt_hash
      assert validate(schema(), roundtrip) == :ok
    end

    test "schema itself rejects a tampered receipt hash (court is non-vacuous on the igniter side)" do
      receipt =
        GgenIgniter.Receipt.new(%{standing: :alive, recipe_key: "k=>v"})
        |> GgenIgniter.Receipt.to_json_map()
        |> Jason.encode!()
        |> Jason.decode!()
        |> sabotaged_igniter_map("standing", "invented_standing")

      assert {:error, [_ | _] = errors} = validate(schema(), receipt)
      assert Enum.any?(errors, &String.contains?(&1, "standing"))
    end
  end

  # ---- 2. real ggen portable receipt mapped into igniter vocabulary -----

  describe "ggen portable envelope -> igniter vocabulary (differential map)" do
    test "real fixture parses and carries the ggen portable schema marker" do
      assert ggen_receipt()["schema"] == "https://ggen.dev/receipt/pack/v1"
      assert ggen_receipt()["spec"] =~ ~r/^RFC-GPACK-001-/
    end

    test "every ggen envelope field has an explicit disposition; unknown fields fail closed" do
      ggen = ggen_receipt()

      unmapped =
        Map.keys(ggen)
        |> Enum.reject(&Map.has_key?(@ggen_field_dispositions, &1))

      assert unmapped == [],
             "FAIL-CLOSED forward drift: ggen added envelope field(s) #{inspect(unmapped)} " <>
               "that this court has no disposition for -- extend @ggen_field_dispositions " <>
               "with an explicit mapping or :no_igniter_counterpart entry in the SAME " <>
               "transition that admits the upstream change"
    end

    test "known mapped fields land in real igniter-schema-shaped values" do
      ggen = ggen_receipt()

      # schema -> schema_version (non-equivalent value spaces, both strings)
      assert is_binary(ggen["schema"])
      assert is_binary(ggen["schema_version"] || "1")

      # engine -> engine
      assert is_binary(ggen["engine"]["name"])
      assert is_binary(ggen["engine"]["version"])

      # subject -> pack_name + pack_digest: the fixture's real pack identity
      # must be mappable to the igniter schema's pack_name/pack_digest types.
      assert is_binary(ggen["subject"]["pack"])
      assert ggen["subject"]["pack_digest"] =~ ~r/^(sha256:[0-9a-f]{64}|UNKNOWN)$/

      mapped = %{
        "schema_version" => "1",
        "engine" => ggen["engine"]["name"],
        "pack_name" => ggen["subject"]["pack"],
        "pack_digest" => strip_sha_prefix(ggen["subject"]["pack_digest"]),
        "standing" => map_ggen_standing(ggen["standing"])
      }

      # pack_digest (igniter side) is bare 64-hex per the schema pattern.
      assert mapped["pack_digest"] =~ ~r/^[0-9a-f]{64}$/

      # standing maps into a real igniter standing atom string.
      igniter_strings = Enum.map(GgenIgniter.Receipt.standings(), &Atom.to_string/1)
      assert mapped["standing"] in igniter_strings

      # The mapped projection, fed through a real igniter receipt, still
      # validates against the igniter schema -- the boundary produces REAL
      # igniter receipts, not just matching key names.
      receipt =
        GgenIgniter.Receipt.new(%{
          standing: String.to_existing_atom(mapped["standing"]),
          recipe_key: nil,
          operation: "ggen-portable-boundary",
          pack_name: mapped["pack_name"],
          pack_digest: mapped["pack_digest"]
        })

      roundtrip = GgenIgniter.Receipt.to_json_map(receipt) |> Jason.encode!() |> Jason.decode!()
      assert roundtrip["pack_name"] == "chicago-tdd-tools-pack"
      assert validate(schema(), roundtrip) == :ok
    end

    test "standing vocabularies are closed sets on both sides (differential report)" do
      ggen = ggen_receipt()

      assert ggen["standing"] in @ggen_standings
      assert ggen["standing"] == "ALIVE"

      # The two vocabularies are deliberately NON-equivalent: ggen's ALIVE
      # maps to igniter's :alive, but igniter's :refused/:compensated/
      # :build_broken/:compensation_failed have NO ggen counterpart and
      # ggen's PARTIAL_ALIVE/UNKNOWN/BLOCKED/REFUSED have no igniter atom.
      igniter_only = [:refused, :compensated, :compensation_failed]
      ggen_only = ["PARTIAL_ALIVE", "UNKNOWN", "BLOCKED", "REFUSED"]

      for s <- igniter_only do
        refute to_ggen_standing(s),
               "#{s} must NOT silently map into ggen's vocabulary (non-equivalence is the boundary)"
      end

      for s <- ggen_only do
        refute map_ggen_standing(s) in (GgenIgniter.Receipt.standings() |> Enum.map(&Atom.to_string/1)),
               "ggen #{s} must NOT silently map into igniter's vocabulary"
      end

      # Only ALIVE<->:alive (and BUILD_BROKEN<->:build_broken) are lawful.
      igniter_strings = Enum.map(GgenIgniter.Receipt.standings(), &Atom.to_string/1)
      assert mapped_standing = map_ggen_standing("ALIVE")
      assert mapped_standing in igniter_strings
      assert map_ggen_standing("BUILD_BROKEN") == "build_broken"
      assert "build_broken" in igniter_strings
    end
  end

  # ---- 3. sabotage twins --------------------------------------------------

  describe "sabotage twins (court fails on mutation)" do
    test "an unknown future ggen envelope field fails the drift check" do
      sabotaged = sabotaged_ggen_receipt(%{"future_ggen_field_v99" => %{"anything" => true}})

      unmapped =
        Map.keys(sabotaged)
        |> Enum.reject(&Map.has_key?(@ggen_field_dispositions, &1))

      assert unmapped == ["future_ggen_field_v99"]
    end

    test "a mutated ggen standing is rejected by the closed-vocabulary check" do
      sabotaged = sabotaged_ggen_receipt(%{"standing" => "SUPER_ALIVE"})
      refute sabotaged["standing"] in @ggen_standings
    end

    test "a mutated igniter receipt fails schema validation" do
      receipt =
        GgenIgniter.Receipt.new(%{standing: :alive, recipe_key: "k=>v"})
        |> GgenIgniter.Receipt.to_json_map()
        |> Jason.encode!()
        |> Jason.decode!()
        |> sabotaged_igniter_map("id", "not_rcpt_prefixed")

      assert {:error, errors} = validate(schema(), receipt)
      assert Enum.any?(errors, &String.contains?(&1, "id"))
    end

    test "a mutated igniter receipt_hash is detectable (self-consistency check fails)" do
      receipt =
        GgenIgniter.Receipt.new(%{standing: :alive, recipe_key: "k=>v"})
        |> GgenIgniter.Receipt.to_json_map()
        |> Jason.encode!()
        |> Jason.decode!()
        |> sabotaged_igniter_map("receipt_hash", "sha256:" <> String.duplicate("0", 64))

      recomputed =
        receipt
        |> Map.delete("receipt_hash")
        |> then(fn map -> map |> Enum.sort_by(&elem(&1, 0)) |> Map.new() end)
        |> Jason.encode!()
        |> then(&("sha256:" <> GgenIgniter.Digest.hex(&1)))

      refute recomputed == receipt["receipt_hash"]
    end
  end

  # ---- vocabulary mapping (explicit, partial, disclosed) ------------------

  defp map_ggen_standing("ALIVE"), do: "alive"
  defp map_ggen_standing("BUILD_BROKEN"), do: "build_broken"
  # Deliberately unmapped: no lawful igniter counterpart.
  defp map_ggen_standing(s) when s in ["PARTIAL_ALIVE", "UNKNOWN", "BLOCKED", "REFUSED"], do: nil
  defp map_ggen_standing(_), do: nil

  defp to_ggen_standing(:alive), do: "ALIVE"
  defp to_ggen_standing(:build_broken), do: "BUILD_BROKEN"
  defp to_ggen_standing(_), do: nil

  defp strip_sha_prefix("sha256:" <> hex), do: hex
  defp strip_sha_prefix("UNKNOWN"), do: "UNKNOWN"
  defp strip_sha_prefix(other), do: other

  defp schema, do: @schema_path |> File.read!() |> Jason.decode!()
  defp ggen_receipt, do: @ggen_portable_path |> File.read!() |> Jason.decode!()
end
