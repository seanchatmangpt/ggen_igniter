defmodule GgenIgniter.EpochAdmissionTest do
  @moduledoc """
  Falsifier corpus for the epoch ADMISSION gate (`GgenIgniter.SemanticJira.EpochPlan`
  and its wiring into `mix semantic_jira.admit_candidates --epoch-manifest`).

  The no-regression law is load-bearing here: a candidate line without an
  "epoch" value must produce a byte-identical verdict whether or not the
  epoch gate is in the run — the canonical fabric set never opts in, so it
  must never notice the gate exists.
  """

  # async: false -- uses the global Mix.shell/captured IO/Mix tasks.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GgenIgniter.SemanticJira.EpochPlan
  alias Mix.Tasks.SemanticJira.AdmitCandidates

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @objective @sj <> "objective-code-work-authority"
  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)

  @watermark %{
    "schema_version" => "1",
    "epoch" => "v26.10.1",
    "implementation_glob" => "lib/**/*.ex",
    "files" => [
      %{"path" => "lib/legacy.ex", "blob_sha" => String.duplicate("a", 40)},
      %{"path" => "lib/deep/old.ex", "blob_sha" => String.duplicate("b", 40)}
    ]
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "epoch_admit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp order(opts \\ []) do
    base = %{
      "identity" => "EPOCH-A",
      "epoch" => "v26.10.1",
      "plan_touches" => ["lib/legacy.ex"]
    }

    base
    |> Map.merge(Keyword.get(opts, :put, %{}))
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # -- EpochPlan.check/2 unit corpus ---------------------------------------------

  test "gate not applied: a candidate without an epoch value is :ok even with nil watermark" do
    assert :ok = EpochPlan.check(%{"identity" => "PLAIN"}, nil)

    assert :ok =
             EpochPlan.check(%{"identity" => "PLAIN", "plan_touches" => ["lib/legacy.ex"]}, nil)
  end

  test "gate applied with an empty-string epoch value is NOT applied" do
    assert :ok = EpochPlan.check(%{"epoch" => "", "plan_touches" => ["lib/legacy.ex"]}, nil)
  end

  test "fail closed: gate applied with nil watermark is :watermark_unavailable" do
    assert {:error, {:refused_epoch_plan, :watermark_unavailable}} =
             EpochPlan.check(order(), nil)
  end

  test "fail closed: a watermark without files is still :watermark_unavailable" do
    assert {:error, {:refused_epoch_plan, :watermark_unavailable}} =
             EpochPlan.check(order(), %{"epoch" => "v26.10.1"})
  end

  test "legacy_edit: plan touching a stamped implementation path without a manufacture plan" do
    assert {:error, {:refused_epoch_plan, :legacy_edit}} = EpochPlan.check(order(), @watermark)
  end

  test "lawful regeneration: the same touch with a generated plan admits" do
    o = order(put: %{"manufacture_plan" => %{"lib/legacy.ex" => "generated"}})
    assert :ok = EpochPlan.check(o, @watermark)
  end

  test "lawful residue: the same touch with a residue plan admits" do
    o = order(put: %{"manufacture_plan" => %{"lib/legacy.ex" => "residue"}})
    assert :ok = EpochPlan.check(o, @watermark)
  end

  test "unattributed_implementation: a new implementation-plane touch with no plan" do
    o = order(put: %{"plan_touches" => ["lib/new.ex"]})

    assert {:error, {:refused_epoch_plan, :unattributed_implementation}} =
             EpochPlan.check(o, @watermark)
  end

  test "knowledge-plane exemption: a docs touch needs no manufacture plan" do
    o = order(put: %{"plan_touches" => ["docs/jira/v26.9.27/notes.md"]})
    assert :ok = EpochPlan.check(o, @watermark)
  end

  test "reuses_pre_watermark_artifact: a stamped path named as a source without a plan" do
    # The plan touches only knowledge-plane paths so rule 2 cannot fire
    # first; the source reuse is then what the gate refuses.
    o =
      order(
        put: %{
          "plan_touches" => ["docs/jira/v26.9.27/notes.md"],
          "source_artifacts" => ["lib/legacy.ex"]
        }
      )

    assert {:error, {:refused_epoch_plan, :reuses_pre_watermark_artifact}} =
             EpochPlan.check(o, @watermark)
  end

  test "a stamped source WITH a regeneration plan admits" do
    o =
      order(
        put: %{
          "source_artifacts" => ["lib/legacy.ex"],
          "plan_touches" => ["docs/jira/v26.9.27/notes.md"],
          "manufacture_plan" => %{"lib/legacy.ex" => "generated"}
        }
      )

    assert :ok = EpochPlan.check(o, @watermark)
  end

  test "malformed tolerance: a bare-binary plan_touches behaves as a one-element list" do
    o = order(put: %{"plan_touches" => "lib/legacy.ex"})
    assert {:error, {:refused_epoch_plan, :legacy_edit}} = EpochPlan.check(o, @watermark)
  end

  test "precedence: legacy_edit wins over unattributed and source-reuse" do
    o =
      order(
        put: %{
          "plan_touches" => ["lib/legacy.ex", "lib/new.ex"],
          "source_artifacts" => ["lib/deep/old.ex"]
        }
      )

    assert {:error, {:refused_epoch_plan, :legacy_edit}} = EpochPlan.check(o, @watermark)
  end

  test "the glob dialect: lib/**/*.ex covers shallow and deep, never other trees" do
    assert {:error, {:refused_epoch_plan, :legacy_edit}} =
             EpochPlan.check(order(put: %{"plan_touches" => ["lib/deep/old.ex"]}), @watermark)

    assert {:error, {:refused_epoch_plan, :unattributed_implementation}} =
             EpochPlan.check(order(put: %{"plan_touches" => ["lib/brand_new.ex"]}), @watermark)

    assert :ok = EpochPlan.check(order(put: %{"plan_touches" => ["test/legacy.ex"]}), @watermark)
  end

  # -- refusal strings -------------------------------------------------------------

  test "refusal_code_string/1 maps the closed set to canonical registry text" do
    assert EpochPlan.refusal_code_string(:legacy_edit) == "REFUSED:EPOCH_LEGACY_EDIT"

    assert EpochPlan.refusal_code_string(:unattributed_implementation) ==
             "REFUSED:EPOCH_UNATTRIBUTED_IMPLEMENTATION"

    assert EpochPlan.refusal_code_string(:reuses_pre_watermark_artifact) ==
             "REFUSED:EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT"

    assert EpochPlan.refusal_code_string(:watermark_unavailable) ==
             "REFUSED:EPOCH_WATERMARK_UNAVAILABLE"

    assert_raise FunctionClauseError, fn -> EpochPlan.refusal_code_string(:nonsense) end
  end

  # -- task wiring (real task, real candidates file, printed verdicts) --------------

  defp base_candidate do
    @fixture
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("work_orders")
    |> Enum.find(&(&1["identity"] == "FRI-FMT-A"))
    |> Map.put("identity", "EPOCH-TASK-A")
    |> Map.put("replay_identity", "epoch-admit:EPOCH-TASK-A")
    |> Map.put("origin_authority", @objective)
  end

  defp run_task(args) do
    Mix.Task.reenable("semantic_jira.admit_candidates")
    capture_io(fn -> AdmitCandidates.run(args) end)
  end

  test "task level: an epoch candidate editing a stamped path is refused with the bare string", %{
    dir: dir
  } do
    manifest = Path.join(dir, "watermark.json")
    File.write!(manifest, Jason.encode!(@watermark))

    candidate =
      Map.merge(base_candidate(), %{
        "epoch" => "v26.10.1",
        "plan_touches" => ["lib/legacy.ex"]
      })

    path = Path.join(dir, "candidates.jsonl")
    File.write!(path, Jason.encode!(candidate) <> "\n")

    out = run_task(["--candidates", path, "--epoch-manifest", manifest])

    assert out =~ "refused 1 EPOCH-TASK-A REFUSED:EPOCH_LEGACY_EDIT"
    assert out =~ "summary admitted=0 refused=1"
  end

  test "task level: epoch candidate with the flag missing is refused fail-closed", %{dir: dir} do
    candidate =
      Map.merge(base_candidate(), %{
        "epoch" => "v26.10.1",
        "plan_touches" => ["lib/legacy.ex"]
      })

    path = Path.join(dir, "candidates.jsonl")
    File.write!(path, Jason.encode!(candidate) <> "\n")

    out = run_task(["--candidates", path])

    assert out =~ "refused 1 EPOCH-TASK-A REFUSED:EPOCH_WATERMARK_UNAVAILABLE"
  end

  test "task level: no-regression — a non-epoch candidate's verdict line is identical with and without the gate",
       %{dir: dir} do
    candidate = Map.merge(base_candidate(), %{"plan_touches" => ["lib/legacy.ex"]})
    path = Path.join(dir, "candidates.jsonl")
    File.write!(path, Jason.encode!(candidate) <> "\n")

    without_gate = run_task(["--candidates", path])

    manifest = Path.join(dir, "watermark.json")
    File.write!(manifest, Jason.encode!(@watermark))
    with_gate = run_task(["--candidates", path, "--epoch-manifest", manifest])

    assert with_gate == without_gate
  end
end
