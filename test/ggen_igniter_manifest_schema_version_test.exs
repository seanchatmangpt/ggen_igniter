defmodule GgenIgniter.ManifestSchemaVersionTest do
  @moduledoc """
  Real, on-disk proof of `GgenIgniter.Manifest`'s `schema_version` field,
  corruption detection, and unsupported-future-version refusal -- per
  AR-9 (absent `schema_version` on an old manifest.json is treated as `"1"`
  for backward compat, never silently reinterpreted).

  Every case here writes a REAL `manifest.json` fixture to a real tmp
  directory via `File.write!/2`, then exercises the REAL `Manifest.load/1`
  and `Manifest.load_safe/1` against it -- no mocking, no in-memory fakes of
  the manifest file.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Manifest

  defp tmp_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_manifest_schema_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp write_manifest!(base_dir, content) when is_binary(content) do
    manifest_path = Manifest.path(base_dir)
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, content)
  end

  # -- 1. A brand-new manifest (persisted via put/persist!) carries both
  # the legacy integer "version" and the new string "schema_version". -------
  test "a freshly built and persisted manifest carries schema_version \"1\" alongside version 1" do
    base_dir = tmp_dir!("fresh")

    manifest =
      Manifest.load(base_dir)
      |> Manifest.put(
        Manifest.recipe_key("t.eex", "out.ex"),
        Manifest.build_entry("t.eex", "out.ex", nil, %{})
      )

    Manifest.persist!(manifest, base_dir)

    on_disk = base_dir |> Manifest.path() |> File.read!() |> Jason.decode!()
    assert on_disk["version"] == 1
    assert on_disk["schema_version"] == "1"

    reloaded = Manifest.load(base_dir)
    assert reloaded["schema_version"] == "1"
  end

  # -- 2. A valid, CURRENT-schema manifest.json loads cleanly. ---------------
  test "a valid current-schema manifest.json (schema_version \"1\") loads via load/1 and load_safe/1" do
    base_dir = tmp_dir!("valid_current")

    write_manifest!(base_dir, ~s({"version":1,"schema_version":"1","entries":{}}))

    assert %{"schema_version" => "1", "entries" => %{}} = Manifest.load(base_dir)
    assert {:ok, %{"schema_version" => "1"}} = Manifest.load_safe(base_dir)
  end

  # -- 3. A legacy manifest.json with NO schema_version field at all is
  # treated as version "1" for backward compat (AR-9), not an error. -------
  test "a legacy manifest.json with no schema_version field loads as schema_version \"1\" (AR-9 backward compat)" do
    base_dir = tmp_dir!("legacy_no_version")

    legacy_json =
      Jason.encode!(%{
        "version" => 1,
        "entries" => %{
          "t.eex=>out.ex" => %{
            "template" => "t.eex",
            "out_template" => "out.ex",
            "pack_dir" => nil,
            "updated_at" => "2025-01-01T00:00:00Z",
            "outputs" => %{"out.ex" => "sha256:deadbeef"}
          }
        }
      })

    write_manifest!(base_dir, legacy_json)

    assert {:ok, manifest} = Manifest.load_safe(base_dir)
    # No "schema_version" key was ever written to disk here...
    refute Map.has_key?(Jason.decode!(legacy_json), "schema_version")
    # ...but load/1 and load_safe/1 both treat it as understood schema "1":
    # the real entry is readable, not refused as corrupt/unknown.
    entry = Manifest.get_entry(manifest, "t.eex=>out.ex")
    assert entry["template"] == "t.eex"
    assert entry["outputs"] == %{"out.ex" => "sha256:deadbeef"}

    # load/1 (the raising API every existing caller uses) also succeeds,
    # not raises, on this legacy shape.
    assert %{"entries" => _} = Manifest.load(base_dir)
  end

  # -- 4. Corrupt JSON on disk -> {:error, :corrupt_manifest, detail} from
  # load_safe/1, and a raised ArgumentError with the same detail from
  # load/1 -- never a bare crash / unhandled exception type. ----------------
  test "corrupt (invalid) JSON manifest.json is refused as :corrupt_manifest, not a crash" do
    base_dir = tmp_dir!("corrupt_json")

    write_manifest!(base_dir, "{not valid json at all")

    assert {:error, :corrupt_manifest, detail} = Manifest.load_safe(base_dir)
    assert is_binary(detail)
    assert detail =~ "not valid JSON"

    assert_raise ArgumentError, ~r/not valid JSON/, fn ->
      Manifest.load(base_dir)
    end
  end

  # -- 4b. Valid JSON but missing the required "entries" key is also a
  # real corrupt-manifest refusal, distinct from an ordinary crash. --------
  test "valid JSON missing the required entries key is refused as :corrupt_manifest" do
    base_dir = tmp_dir!("missing_entries")

    write_manifest!(base_dir, ~s({"version":1,"schema_version":"1"}))

    assert {:error, :corrupt_manifest, detail} = Manifest.load_safe(base_dir)
    assert detail =~ "unexpected shape"

    assert_raise ArgumentError, ~r/unexpected shape/, fn ->
      Manifest.load(base_dir)
    end
  end

  # -- 5. An unsupported FUTURE schema_version (e.g. "2") is explicitly
  # refused, never silently misread as schema "1". --------------------------
  test "an unsupported future schema_version is refused, not silently misread" do
    base_dir = tmp_dir!("future_version")

    future_json =
      Jason.encode!(%{
        "version" => 2,
        "schema_version" => "2",
        "entries" => %{
          "t.eex=>out.ex" => %{
            "template" => "t.eex",
            "out_template" => "out.ex",
            "some_new_field_this_code_has_never_seen" => %{"nested" => true}
          }
        }
      })

    write_manifest!(base_dir, future_json)

    assert {:error, :corrupt_manifest, detail} = Manifest.load_safe(base_dir)
    assert detail =~ "schema_version"
    assert detail =~ "\"2\""
    assert detail =~ "\"1\""

    assert_raise ArgumentError, ~r/schema_version/, fn ->
      Manifest.load(base_dir)
    end
  end

  # -- 6. A missing manifest file entirely is the honest "first run" state,
  # already stamped with the current schema_version -- not an error. -------
  test "a missing manifest file loads as a fresh first-run manifest stamped with the current schema_version" do
    base_dir = tmp_dir!("missing_file")
    refute File.exists?(Manifest.path(base_dir))

    assert {:ok, manifest} = Manifest.load_safe(base_dir)
    assert manifest["schema_version"] == Manifest.current_schema_version()
    assert manifest["entries"] == %{}
  end
end
