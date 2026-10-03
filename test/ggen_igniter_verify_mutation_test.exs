defmodule GgenIgniterVerifyMutationTest do
  @moduledoc """
  Chicago-style: real collaborators only. Each mutant is a textual transform
  of a real COPY of `test/fixtures/ash_manufacture_pack/verify/` assets
  materialized into a unique tmp dir under `System.tmp_dir!()` (created and
  `File.rm_rf!`-deleted inside `GgenIgniter.VerifyMutation.run/1` itself), and
  the killer is the REAL verify core -- `GgenIgniter.GateVerify.load_cardinality/1`,
  `GateVerify.run/3` and `GateVerify.verify_unbound/2` in
  `Mix.Tasks.GgenIgniter.verify`'s own order -- executed against the real
  fixture ontology through the real `sparql` engine. No doubles, no BEAM
  hot-patching; the catalog's own anti-vacuity probe (`:weakened_for_test`,
  documented in `VerifyMutation`'s moduledoc) supplies the inversion case.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.VerifyMutation

  describe "catalog/0 (shape)" do
    test "ids are unique and append-only-stable" do
      ids = VerifyMutation.ids()
      assert length(ids) == length(Enum.uniq(ids))
      assert ids == Enum.uniq(ids)
      assert length(ids) in 4..5
    end

    test "every mutant names a real fixture verify asset and a killer" do
      for mutant <- VerifyMutation.catalog() do
        assert File.regular?(Path.join(fixture_pack(), mutant.target_file)),
               "#{mutant.id}: target #{mutant.target_file} is not a fixture verify asset"

        assert is_binary(mutant.killer) and mutant.killer != ""
        assert is_function(mutant.transform, 1)
      end
    end

    test "every transform actually changes its target's body (no no-op mutants)" do
      for mutant <- VerifyMutation.catalog() do
        body = File.read!(Path.join(fixture_pack(), mutant.target_file))
        refute mutant.transform.(body) == body, "#{mutant.id}: transform is a no-op"
      end
    end
  end

  describe "run/1 (the court)" do
    test "every catalog mutant is killed by the real verify" do
      verdicts = VerifyMutation.run(source_pack: fixture_pack())

      assert %{} = verdicts
      assert Map.keys(verdicts) |> Enum.sort() == Enum.sort(VerifyMutation.ids())

      for {id, verdict} <- verdicts do
        assert verdict == :killed, "#{id} SURVIVED -- vacuous gate"
      end
    end

    test "run/1 is deterministic across repeated invocations" do
      assert VerifyMutation.run(source_pack: fixture_pack()) ==
               VerifyMutation.run(source_pack: fixture_pack())
    end

    test "anti-vacuity inversion: a verify with no fail-closed assets lets mutants survive" do
      verdicts = VerifyMutation.run(source_pack: fixture_pack(), weakened_for_test: true)

      assert Enum.any?(verdicts, fn {_id, verdict} -> verdict == :survived end),
             "the weakened verify killed every mutant -- the court is testing its own model"

      # Weakened mode runs the same catalog; no mutant may vanish from the map.
      assert Map.keys(verdicts) |> Enum.sort() == Enum.sort(VerifyMutation.ids())
    end

    test "a control pack that refuses raises ControlRefused instead of measuring" do
      broken_pack = scratch_pack_with_failing_gate()

      assert_raise VerifyMutation.ControlRefused, ~r/control pack refused/, fn ->
        VerifyMutation.run(source_pack: broken_pack)
      end
    end
  end

  # A minimal real pack whose gate returns zero rows against its own ontology:
  # the control-refused path, exercised through real files, not a stub.
  defp scratch_pack_with_failing_gate do
    dir =
      Path.join(System.tmp_dir!(), "verify_mutation_broken-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(dir, "gates"))

    File.write!(Path.join(dir, "ontology.ttl"), """
    @prefix : <http://example.com/broken#> .
    <http://example.com/broken/thing> a :Thing .
    """)

    File.write!(Path.join(dir, "gates/010_thing.rq"), """
    PREFIX : <http://example.com/broken#>
    SELECT ?s WHERE { ?s a :NeverPresent . }
    """)

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp fixture_pack, do: Path.join(__DIR__, "fixtures/ash_manufacture_pack")
end
