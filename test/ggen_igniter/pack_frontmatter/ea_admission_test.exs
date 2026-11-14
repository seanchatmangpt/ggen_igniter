defmodule GgenIgniter.PackFrontmatter.EaAdmissionTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.PackFrontmatter.EaAdmission

  @toml "[project]\nname = \"x\"\n"

  setup do
    dir = Path.join(System.tmp_dir!(), "ea_adm_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "ggen.toml"), @toml)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "ea.graph.json present admits without receipt", %{dir: dir} do
    File.write!(Path.join(dir, "ea.graph.json"), "{}")
    assert EaAdmission.admit(dir) == {:ok, :ea_graph_present}
  end

  test "no graph and no receipt is a typed refusal", %{dir: dir} do
    assert EaAdmission.admit(dir) ==
             {:error, {:ea_admission_refused, :no_ea_graph_and_no_skip_receipt}}
  end

  test "skip receipt bytes carry reason, toml sha, ts and admit passes", %{dir: dir} do
    assert {:ok, path} = EaAdmission.skip_receipt(dir, "generated-only project")
    assert Path.dirname(path) == Path.join(dir, ".ggen_igniter/receipts")
    assert Path.basename(path) =~ ~r/^ea-skip-.+\.json$/

    m = path |> File.read!() |> Jason.decode!()
    assert m["skipped"] == true
    assert m["reason"] == "generated-only project"
    assert m["ggen_toml_sha256"] == :crypto.hash(:sha256, @toml) |> Base.encode16(case: :lower)
    assert {:ok, _, _} = DateTime.from_iso8601(m["ts"])

    assert EaAdmission.admit(dir) == {:ok, {:skipped, path}}
  end

  test "receipt goes stale when ggen.toml changes", %{dir: dir} do
    {:ok, _} = EaAdmission.skip_receipt(dir, "r")
    File.write!(Path.join(dir, "ggen.toml"), @toml <> "# changed\n")
    assert EaAdmission.admit(dir) == {:error, {:ea_admission_refused, :stale_skip_receipt}}
  end

  test "empty reason refuses and writes nothing", %{dir: dir} do
    assert EaAdmission.skip_receipt(dir, "  ") == {:error, :empty_reason}
    refute File.exists?(Path.join(dir, ".ggen_igniter/receipts"))
  end

  test "garbage receipt file does not admit", %{dir: dir} do
    rd = Path.join(dir, ".ggen_igniter/receipts")
    File.mkdir_p!(rd)
    File.write!(Path.join(rd, "ea-skip-bogus.json"), "not json")
    assert {:error, {:ea_admission_refused, _}} = EaAdmission.admit(dir)
  end
end
