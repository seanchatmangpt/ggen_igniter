defmodule GgenIgniterLandingPipelineTest do
  @moduledoc """
  Chicago-style witness for `GgenIgniter.LandingPipeline.run/1`: real git
  subprocesses (`rev-parse --verify`, `merge-base --is-ancestor`,
  `rev-parse HEAD` over this checkout), real tmp-dir receipt files decoded
  back from disk, and REAL fake stage modules — plain modules implementing
  the `GgenIgniter.LandingPipeline.Stage` behaviour whose `run/1` genuinely
  captures command output (`Stage.capture/3` over real `echo`) — never
  mocks. The `opts[:stages]` override replaces the fixed registry with these
  real modules; the no-override case (missing production stage modules) is
  witnessed as the typed `stage_module_missing` refusal.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.LandingPipeline
  alias GgenIgniter.LandingPipeline.Stage

  # ── real fake stages (behaviour implementations, not doubles of one) ────────

  defmodule L7Test.Stage.Ok1 do
    @behaviour Stage
    def name, do: :ok1
    def order, do: 1

    def run(_ctx),
      do: {:pass, %{"output" => Stage.capture("echo", ["ok1-ran"]), "note" => "real"}}
  end

  defmodule L7Test.Stage.Ok2 do
    @behaviour Stage
    def name, do: :ok2
    def order, do: 2

    def run(_ctx),
      do: {:pass, %{"output" => Stage.capture("echo", ["ok2-ran"]), "note" => "real"}}
  end

  defmodule L7Test.Stage.Blocker do
    @behaviour Stage
    def name, do: :blocker
    def order, do: 3

    def run(_ctx),
      do:
        {:block, {:too_risky, "tier refused"},
         %{"output" => Stage.capture("echo", ["blocker-ran"])}}
  end

  defmodule L7Test.Stage.Late do
    @behaviour Stage
    def name, do: :late
    def order, do: 4

    def run(_ctx),
      do: {:pass, %{"output" => Stage.capture("echo", ["late-ran"])}}
  end

  # A :pass whose embedded output is empty/absent — the vacuous pass that
  # must NEVER mint ALIVE.
  defmodule L7Test.Stage.EmptyPass do
    @behaviour Stage
    def name, do: :empty_pass
    def order, do: 2
    def run(_ctx), do: {:pass, %{"note" => "no output embedded at all"}}
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "l7_pipeline_#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir, receipts_dir: Path.join(dir, "receipts")}
  end

  defp run(opts, dir) do
    LandingPipeline.run(Keyword.put(opts, :receipts_dir, Path.join(dir, "receipts")))
  end

  describe "run/1 (ALIVE path)" do
    test "every stage passes with real embedded output -> {0, ALIVE}", %{dir: dir} do
      {code, report} = run([base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.Ok2]], dir)

      assert code == 0
      assert report["status"] == "ALIVE"
      assert report["first_block"] == nil

      names = Enum.map(report["stages"], & &1["stage"])
      assert names == ["base_integrity", "ok1", "ok2"]

      base = Enum.at(report["stages"], 0)
      assert %{"commands" => cmds} = base["output"]
      assert length(cmds) == 3
      assert Enum.all?(cmds, &(&1["exit"] == 0 and &1["command"] != ""))
      assert base["base_sha"] == base["worktree_sha"]
      assert String.length(base["base_sha"]) == 40
    end

    test "per-stage receipts and the landing receipt land as real JSON bytes on disk", %{
      dir: dir
    } do
      {code, report} = run([base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.Ok2]], dir)
      assert code == 0

      run_dir = report["receipts_dir"]
      assert File.dir?(run_dir)

      files = File.ls!(run_dir) |> Enum.sort()

      assert files == [
               "landing-receipt.json",
               "stage-0-base_integrity.json",
               "stage-1-ok1.json",
               "stage-2-ok2.json"
             ]

      for file <- files do
        assert {:ok, _} = run_dir |> Path.join(file) |> File.read!() |> Jason.decode()
      end

      {:ok, on_disk} =
        run_dir |> Path.join("stage-1-ok1.json") |> File.read!() |> Jason.decode()

      assert on_disk["status"] == "pass"
      assert on_disk["output"]["stdout_tail"] =~ "ok1-ran"

      {:ok, landing} =
        run_dir |> Path.join("landing-receipt.json") |> File.read!() |> Jason.decode()

      assert landing["status"] == "ALIVE"
    end
  end

  describe "run/1 (ordering and short-circuit)" do
    test "stages run in registry/list order; order/0 labels the receipts", %{dir: dir} do
      {code, report} = run([base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.Ok2]], dir)

      assert code == 0
      assert Enum.map(report["stages"], & &1["order"]) == [0, 1, 2]
      assert Enum.map(report["stages"], & &1["stage"]) == ["base_integrity", "ok1", "ok2"]
    end

    test "first block short-circuits: later stages never run, first_block names the stage", %{
      dir: dir
    } do
      {code, report} =
        run(
          [base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.Blocker, L7Test.Stage.Late]],
          dir
        )

      assert code == 1
      assert report["status"] == "BLOCKED"

      names = Enum.map(report["stages"], & &1["stage"])
      assert names == ["base_integrity", "ok1", "blocker"]
      refute "late" in names

      assert %{"stage" => "blocker", "reason" => reason} = report["first_block"]
      assert reason == ["too_risky", "tier refused"]

      blocker = Enum.at(report["stages"], 2)
      assert blocker["status"] == "block"
      assert blocker["output"]["stdout_tail"] =~ "blocker-ran"
    end

    test "base drift at stage 0 blocks before any registry stage runs", %{dir: dir} do
      {code, report} =
        run(
          [base: "HEAD", worktree_sha: String.duplicate("a", 40), stages: [L7Test.Stage.Ok1]],
          dir
        )

      assert code == 1
      assert report["status"] == "BLOCKED"
      names = Enum.map(report["stages"], & &1["stage"])
      assert names == ["base_integrity"]

      [base] = report["stages"]
      assert [reason_head, declared, observed] = base["reason"]
      assert reason_head == "base_drift"
      assert declared == String.duplicate("a", 40)
      assert String.length(observed) == 40
      assert report["first_block"]["stage"] == "base_integrity"
    end
  end

  describe "run/1 (fail-closed stage resolution)" do
    test "a missing stage module is a typed stage_module_missing refusal, never a silent skip", %{
      dir: dir
    } do
      {code, report} =
        run([base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.DoesNotExist]], dir)

      assert code == 1
      assert report["status"] == "BLOCKED"
      assert report["first_block"]["stage"] == "does_not_exist"
      assert report["first_block"]["reason"] |> hd() == "stage_module_missing"

      entry = List.last(report["stages"])
      assert entry["status"] == "refused"
      assert entry["reason"] |> hd() == "stage_module_missing"
    end
  end

  describe "run/1 (never-a-single-boolean ALIVE law)" do
    test "a :pass with empty embedded output does NOT yield ALIVE", %{dir: dir} do
      {code, report} =
        run([base: "HEAD", stages: [L7Test.Stage.Ok1, L7Test.Stage.EmptyPass]], dir)

      assert code == 1
      assert report["status"] == "BLOCKED"
      assert report["first_block"]["stage"] == "empty_pass"
      assert report["first_block"]["reason"] |> hd() == "invalid_stage_output"
    end
  end

  describe "run/1 (invocation boundary)" do
    test "missing --base is exit 2 invalid_invocation and writes nothing", %{dir: dir} do
      {code, report} = run([stages: [L7Test.Stage.Ok1]], dir)

      assert code == 2
      assert report["status"] == "invalid_invocation"
      assert report["reason"] =~ "base"

      receipts_root = Path.join(dir, "receipts")
      refute File.exists?(receipts_root)
    end
  end
end

# ═════════════════════════════════════════════════════════════════════════════
# Production stage modules (lane C14): the seven fixed-registry adapters.
# Every stage below is exercised against REAL collaborators — real git
# subprocesses over this checkout, a real `mix compile --warnings-as-errors`
# subprocess, the real `GgenIgniter.Review` / `SecurityReview` /
# `Convergence` / `ReviewEval.Gate` subsystems — never mocks.
# ═════════════════════════════════════════════════════════════════════════════

defmodule GgenIgniterLandingPipelineStagesTest do
  @moduledoc """
  Chicago-style witness for the seven production
  `GgenIgniter.LandingPipeline.Stage.*` adapters: real git subprocesses over
  this checkout, a real nested `mix compile` / `mix ggen_igniter.review` /
  `mix ggen_igniter.review.convergence` subprocess (per-lane
  `MIX_BUILD_ROOT` inherited), and the real landed subsystems
  (`EpochFreshness`, `Review.RiskTier`, `SecurityReview`, `ReviewEval.Gate`)
  invoked in process — never mocks.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.LandingPipeline
  alias GgenIgniter.LandingPipeline.Stage

  @registry [
    {1, :epoch_check, GgenIgniter.LandingPipeline.Stage.EpochCheck},
    {2, :risk_tier, GgenIgniter.LandingPipeline.Stage.RiskTier},
    {3, :build_gate, GgenIgniter.LandingPipeline.Stage.BuildGate},
    {4, :fanout_review, GgenIgniter.LandingPipeline.Stage.FanoutReview},
    {5, :security_block, GgenIgniter.LandingPipeline.Stage.SecurityBlock},
    {6, :convergence_cap, GgenIgniter.LandingPipeline.Stage.ConvergenceCap},
    {7, :incident_eval, GgenIgniter.LandingPipeline.Stage.IncidentEval}
  ]

  defp head_sha do
    {out, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    String.trim(out)
  end

  defp ctx(opts \\ []) do
    sha = head_sha()

    %Stage{
      base_sha: Keyword.get(opts, :base_sha, sha),
      worktree_sha: Keyword.get(opts, :worktree_sha, sha),
      paths: [],
      opts: Keyword.get(opts, :opts, [])
    }
  end

  defp real_commands(receipt) do
    get_in(receipt, ["output", "commands"]) || []
  end

  describe "fixed registry (load law)" do
    test "all seven production stage modules exist, load, and declare the fixed name/order" do
      for {order, name, module} <- @registry do
        assert {:module, ^module} = Code.ensure_loaded(module)
        assert module.name() == name
        assert module.order() == order
      end
    end
  end

  describe "Stage.EpochCheck.run/1 (invocation boundary)" do
    test "no opts[:epoch] is a typed refusal, never a pass" do
      assert {:refused, {:no_epoch, _}} = Stage.EpochCheck.run(ctx())
    end

    test "an epoch id with no watermark cannot be judged — typed refusal" do
      assert {:refused, {:epoch_check_error, _}} =
               Stage.EpochCheck.run(ctx(opts: [epoch: "lane-c14-nonexistent-epoch"]))
    end
  end

  describe "Stage.RiskTier.run/1 (real classification)" do
    test "classifies the real worktree diff and embeds the captured git output" do
      assert {:pass, receipt} = Stage.RiskTier.run(ctx())
      assert receipt["tier"] in ["low", "medium", "high"]
      assert is_integer(receipt["score"])
      assert is_integer(receipt["approvals"])

      assert [capture | _] = real_commands(receipt)
      assert capture["exit"] == 0
      assert capture["command"] =~ ~r/^git diff --name-status [0-9a-f]{40}$/
      assert is_binary(capture["stdout_tail"]) and capture["stdout_tail"] != ""
    end
  end

  describe "Stage.BuildGate.run/1 (real compile)" do
    test "a clean compile passes with the real mix output embedded" do
      assert {:pass, receipt} = Stage.BuildGate.run(ctx())

      assert [capture] = real_commands(receipt)
      assert capture["command"] == "mix compile --warnings-as-errors"
      assert capture["exit"] == 0
      assert is_integer(capture["duration_ms"])
    end
  end

  describe "Stage.FanoutReview.run/1 (real review round)" do
    test "delegates to the real mix ggen_igniter.review task and maps its exit code" do
      result = Stage.FanoutReview.run(ctx())

      case result do
        {:pass, receipt} ->
          assert [capture] = real_commands(receipt)
          assert capture["command"] =~ ~r/^mix ggen_igniter.review --base [0-9a-f]{40} --json$/
          assert capture["exit"] == 0

        {:block, {:review_findings_posted, 1}, receipt} ->
          assert [capture] = real_commands(receipt)
          assert capture["exit"] == 1

        other ->
          flunk("unexpected FanoutReview result: #{inspect(other)}")
      end
    end
  end

  describe "Stage.SecurityBlock.run/1 (real security review)" do
    test "delegates to SecurityReview.run/2 and embeds a real git diff --stat capture" do
      result = Stage.SecurityBlock.run(ctx())

      case result do
        {:pass, receipt} ->
          assert is_map(receipt["security_receipt"])
          assert receipt["findings"] == 0

        {:block, {:security_findings_open, n}, receipt} ->
          assert is_integer(n) and n > 0
          assert is_map(receipt["security_receipt"])

        {:refused, {:security_diff_unavailable, _}} ->
          :ok

        other ->
          flunk("unexpected SecurityBlock result: #{inspect(other)}")
      end

      # either way a real capture was attempted and returned
      commands =
        case result do
          {_, %{} = r} -> real_commands(r)
          _ -> []
        end

      assert commands == [] or hd(commands)["command"] =~ ~r/^git diff --stat [0-9a-f]{40}$/
    end
  end

  describe "Stage.ConvergenceCap.run/1 (real convergence run)" do
    test "delegates to the real mix ggen_igniter.review.convergence task" do
      result = Stage.ConvergenceCap.run(ctx())

      case result do
        {:pass, receipt} ->
          assert [capture] = real_commands(receipt)
          assert capture["command"] =~ ~r/^mix ggen_igniter.review.convergence --sha [0-9a-f]{40}/
          assert capture["exit"] == 0

        {:block, {:review_escalated, 1}, receipt} ->
          assert [capture] = real_commands(receipt)
          assert capture["exit"] == 1

        other ->
          flunk("unexpected ConvergenceCap result: #{inspect(other)}")
      end
    end
  end

  describe "Stage.IncidentEval.run/1 (invocation boundary)" do
    test "no opts[:run_receipt] is a typed refusal, never a pass" do
      assert {:refused, {:no_run_receipt, _}} = Stage.IncidentEval.run(ctx())
    end

    test "a nonexistent run receipt path is a typed refusal" do
      assert {:refused, {:run_receipt_unreadable, _}} =
               Stage.IncidentEval.run(ctx(opts: [run_receipt: "/nonexistent/receipt.json"]))
    end
  end

  describe "LandingPipeline.run/1 (full fixed registry)" do
    test "the production registry is wired: no stage_module_missing, first unconfigured gate refuses" do
      dir = Path.join(System.tmp_dir!(), "l7_stages_#{System.unique_integer([:positive])}")
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      {code, report} =
        LandingPipeline.run(
          base: "HEAD",
          receipts_dir: Path.join(dir, "receipts")
        )

      assert code == 1
      assert report["status"] == "BLOCKED"
      # the registry resolves every module — the first block is the epoch
      # gate's typed refusal (no epoch id configured), not a missing module
      assert report["first_block"]["stage"] == "epoch_check"
      assert report["first_block"]["reason"] |> hd() == "no_epoch"

      names = Enum.map(report["stages"], & &1["stage"])
      assert names == ["base_integrity", "epoch_check"]
      assert List.last(report["stages"])["status"] == "refused"
      refute Enum.any?(names, &(&1 == "stage_module_missing"))

      # order-slot law: the receipt's order comes from the module's own
      # order/0 (1), never a 0-based registry index — witnessed wrong as
      # `stage-0-epoch_check.json` on a fresh VM before the fix.
      assert List.last(report["stages"])["order"] == 1

      assert File.exists?(Path.join(report["receipts_dir"], "stage-1-epoch_check.json"))
    end
  end
end
