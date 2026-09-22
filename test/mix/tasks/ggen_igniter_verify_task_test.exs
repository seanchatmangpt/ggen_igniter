defmodule Mix.Tasks.GgenIgniter.VerifyTaskTest do
  @moduledoc """
  Chicago-style tests for `mix ggen_igniter.verify`
  (`lib/mix/tasks/ggen_igniter.verify.ex`): real `System.cmd("mix", ...)`
  subprocesses, mirroring `test/ggen_igniter_hand_authored_task_test.exs`'s
  real-subprocess pattern (`cmd!/3`, real `System.cmd`, real exit codes --
  read that file first, this one is the same shape). No mocks anywhere: the
  task runs against a real, checked-in pack
  (`test/fixtures/ash_manufacture_pack`, the exact fixture
  `GgenIgniter.GateVerify`'s own moduledoc and
  `test/ggen_igniter_gate_verify_test.exs` already use) or a real on-disk copy
  of it with one real triple deleted, and every assertion is against the
  subprocess's real exit code plus its real, `Jason.decode!`-parsed `--json`
  stdout -- never an in-process call, never a captured/faked collaborator.

  Before this file, `mix ggen_igniter.verify` had zero callers anywhere in
  this repo (confirmed by `grep -rn "ggen_igniter.verify" --exclude-dir=deps
  --exclude-dir=_build .` returning only the task's own source and docs) --
  not CI, not another module, not a test. This file is one caller;
  `.github/workflows/ci.yml`'s "mix ggen_igniter.verify (fail-CLOSED pack
  check)" step is the real, production caller that now runs on every PR.

  ## Why the failing case mutates a COPY, never the checked-in fixture

  `test/fixtures/ash_manufacture_pack` is shared, real fixture state --
  `test/ggen_igniter_gate_verify_test.exs` and every gate/pack test in this
  repo depends on it staying lawful (0 gate rows unresolved, 0 unbound
  facts). The failing case below copies the whole pack directory into a fresh
  `System.tmp_dir!()` subdirectory (`on_exit` removes it) and deletes exactly
  one triple from THAT copy -- the same `amp:primaryKeyKind` deletion
  `GgenIgniter.GateVerify`'s own moduledoc documents as the fail-open case
  this task exists to close (`gates/030_resources.rq` 2 rows -> 1,
  `verify/030_resources.unbound.rq` gains exactly the row naming the missing
  predicate). The checked-in fixture is never written to.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @project_root Path.expand("../../..", __DIR__)
  @real_pack "test/fixtures/ash_manufacture_pack"

  # The exact triple `GgenIgniter.GateVerify`'s moduledoc documents deleting
  # to reproduce the fail-open `gates/030_resources.rq` regression: real bytes
  # copied from the checked-in fixture, not typed out by hand here.
  @deleted_triple ~s(    amp:primaryKeyKind "uuid" ;\n)

  setup_all do
    broken_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_verify_task_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(broken_dir)
    File.cp_r!(Path.join(@project_root, @real_pack), broken_dir)

    ontology_path = Path.join(broken_dir, "ontology.ttl")
    content = File.read!(ontology_path)
    assert content =~ @deleted_triple, "fixture ontology no longer contains the expected triple"

    idx = :binary.match(content, @deleted_triple) |> elem(0)
    len = byte_size(@deleted_triple)

    mutated =
      binary_part(content, 0, idx) <>
        binary_part(content, idx + len, byte_size(content) - idx - len)

    File.write!(ontology_path, mutated)

    on_exit(fn -> File.rm_rf!(broken_dir) end)

    {:ok, broken_pack: broken_dir}
  end

  defp cmd!(args) do
    System.cmd("mix", args, cd: @project_root)
  end

  describe "a lawful pack (real fixture, --json)" do
    test "exits 0 and reports ok: true with every gate passing" do
      {output, status} = cmd!(["ggen_igniter.verify", "--pack", @real_pack, "--json"])

      assert status == 0
      json = Jason.decode!(output)

      assert json["ok"] == true
      assert json["gates"]["status"] == "pass"
      assert json["verify"] == %{"status" => "pass", "findings" => []}
      assert "resources" in json["gates"]["passed"]
      assert json["cardinality"]["note"] =~ "loaded 11 gate contract(s)"
    end
  end

  describe "a lawful pack (real fixture, human-readable)" do
    test "exits 0 and prints the passing summary" do
      {output, status} = cmd!(["ggen_igniter.verify", "--pack", @real_pack])

      assert status == 0
      assert output =~ "ggen_igniter.verify: #{@real_pack}"
      assert output =~ "gates: 13 passed, 11 under contract"
      assert output =~ "verify: 0 unbound facts"
    end
  end

  describe "an unlawful pack (real deletion of amp:primaryKeyKind, --json)" do
    test "exits 1 and names the exact dropped predicate and gate cardinality mismatch", %{
      broken_pack: broken_pack
    } do
      {output, status} = cmd!(["ggen_igniter.verify", "--pack", broken_pack, "--json"])

      assert status == 1
      json = Jason.decode!(output)

      assert json["ok"] == false

      assert json["gates"] == %{
               "status" => "gate_cardinality",
               "gate" => "resources",
               "expected" => 2,
               "actual" => 1
             }

      assert %{"status" => "unbound_facts", "findings" => [finding]} = json["verify"]
      assert finding["gate"] == "resources"
      assert finding["missing_property"] == "amp:primaryKeyKind"
      assert finding["subject"] =~ "BookResource"
    end
  end

  describe "invalid invocation" do
    test "exits 1 when --pack is omitted" do
      {output, status} = cmd!(["ggen_igniter.verify"])
      assert status == 1
      assert output == ""
    end

    test "exits 1 when the pack directory does not exist" do
      {output, status} = cmd!(["ggen_igniter.verify", "--pack", "does/not/exist"])
      assert status == 1
      assert output == ""
    end
  end
end
