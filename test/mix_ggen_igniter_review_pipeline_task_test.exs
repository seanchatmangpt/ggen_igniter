defmodule MixGgenIgniterReviewPipelineTaskTest do
  @moduledoc """
  Chicago-style OS-level witness for `mix ggen_igniter.review.pipeline`: real
  `System.cmd("mix", ["ggen_igniter.review.pipeline", ...])` subprocesses
  (stderr captured through a real shell redirect, never swallowed), run over
  THIS checkout's real git history for `--base HEAD`.

  Exit-code matrix witnessed through the real CLI process boundary:

    * `2` — invalid invocation (missing `--base`)
    * `1` — BLOCKED, typed report JSON as the last line of stderr; on this
      tree today the typed reason is the epoch gate's own `no_epoch`
      refusal (no `--epoch` watermark configured) — the refusal itself is
      the designed verdict being witnessed, and the fresh-VM subprocess
      witnesses the order-slot law (`epoch_check` receipted at order 1)
    * `0` — `--help`

  Disclosed ceiling: the exit-0-ALIVE subprocess case needs all seven real
  stage modules compiled into the app; until those lanes land it is
  witnessed in-process over real fake behaviour implementations in
  `ggen_igniter_landing_pipeline_test.exs` (real modules, real captured
  output, real receipts on disk — no doubles), and this file asserts the
  exit law's `1`/`2`/help arms only.
  """

  use ExUnit.Case, async: true

  @task "ggen_igniter.review.pipeline"

  setup do
    dir =
      Path.join(System.tmp_dir!(), "l7_pipeline_task_#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  # One real mix subprocess, stderr redirected to a real file so the
  # "typed JSON as the last line of stderr" contract is witnessed on the
  # actual stderr stream. This lane's build root so the subprocess never
  # clobbers the shared _build.
  defp mix(args) do
    err_log =
      Path.join(System.tmp_dir!(), "l7-stderr-#{System.unique_integer([:positive])}.log")

    quoted =
      Enum.map_join(args, " ", fn arg ->
        "'" <> String.replace(arg, "'", "'\\''") <> "'"
      end)

    {out, code} =
      System.cmd("sh", ["-c", "mix #{quoted} 2> '#{err_log}'"],
        cd: File.cwd!(),
        env: [{"MIX_BUILD_ROOT", "_build-lane-e5"}]
      )

    err = if File.exists?(err_log), do: File.read!(err_log), else: ""
    File.rm(err_log)
    {code, out, err}
  end

  defp last_json_line(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{} = map} -> map
        _ -> nil
      end
    end)
  end

  describe "mix ggen_igniter.review.pipeline (exit 2: invalid invocation)" do
    test "missing --base prints invalid_invocation JSON on stderr and exits 2", %{dir: _dir} do
      {code, _out, err} = mix([@task])

      assert code == 2

      report = last_json_line(err)
      assert %{"status" => "invalid_invocation"} = report
      assert report["reason"] =~ "base"
    end
  end

  describe "mix ggen_igniter.review.pipeline (exit 1: BLOCKED)" do
    test "unconfigured epoch gate is the typed no_epoch refusal, exit 1, BLOCKED receipt on disk",
         %{
           dir: _dir
         } do
      {code, _out, err} = mix([@task, "--base", "HEAD"])

      assert code == 1

      report = last_json_line(err)
      assert report["status"] == "BLOCKED"
      assert report["first_block"]["stage"] == "epoch_check"
      assert report["first_block"]["reason"] |> hd() == "no_epoch"

      names = Enum.map(report["stages"], & &1["stage"])
      assert names == ["base_integrity", "epoch_check"]

      # Fresh-VM order-slot law (the C16 dry-run regression): this subprocess
      # is a brand-new BEAM, so `epoch_check` is touched for the first time
      # here — its receipt must carry the module's own order/0 (1), not the
      # 0-based registry index that the pre-load fallback used to emit
      # (witnessed as `stage-0-epoch_check.json`).
      [base, epoch] = report["stages"]
      assert base["order"] == 0
      assert epoch["order"] == 1

      # the landing receipt really landed on disk under the gitignored
      # manifest dir, and its bytes agree with the stderr report
      landing =
        report["receipts_dir"] |> Path.join("landing-receipt.json") |> File.read!()

      assert {:ok, on_disk} = Jason.decode(landing)
      assert on_disk["status"] == "BLOCKED"
      assert on_disk["run_id"] == report["run_id"]

      assert File.exists?(Path.join(report["receipts_dir"], "stage-0-base_integrity.json"))
      assert File.exists?(Path.join(report["receipts_dir"], "stage-1-epoch_check.json"))
    end
  end

  describe "mix ggen_igniter.review.pipeline (--out / --json on the blocked path)" do
    test "--out writes the landing receipt at the given path", %{dir: dir} do
      out_path = Path.join(dir, "landing.json")
      {code, out, _err} = mix([@task, "--base", "HEAD", "--out", out_path, "--json"])

      assert code == 1
      # --json: the JSON document is the last (payload) line on stdout
      assert {:ok, streamed} = out |> last_json_line() |> then(&{:ok, &1})
      assert streamed["status"] == "BLOCKED"

      assert {:ok, from_file} = out_path |> File.read!() |> Jason.decode()
      assert from_file["run_id"] == streamed["run_id"]
    end
  end

  describe "mix ggen_igniter.review.pipeline (exit 0: --help)" do
    test "--help prints usage and exits 0" do
      {code, out, _err} = mix([@task, "--help"])

      assert code == 0
      assert out =~ "--base"
    end
  end
end
