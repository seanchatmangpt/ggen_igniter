defmodule GgenIgniter.SemanticJiraHandsFreeTwinCourtTest do
  @moduledoc """
  Chicago court for Mix ↔ hands-free eligible-set parity
  (`scripts/sjira/hands_free_twin_parity.py`).

  Anti-vacuity (skeptic L19): a JSON-ok Rust frontier with `eligible=[]`
  while Mix has `eligible=[FRI-FMT-A]` MUST refuse
  `REFUSED:HANDS_FREE_TWIN_DRIFT`. Matching eligible identity sets PASS.
  """

  use ExUnit.Case, async: true

  @parity_py Path.expand("../scripts/sjira/hands_free_twin_parity.py", __DIR__)
  @tag :hands_free_twin_court

  setup do
    assert File.exists?(@parity_py), "parity helper missing at #{@parity_py}"
    tmp =
      Path.join(
        System.tmp_dir!(),
        "sjira-hf-twin-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    %{tmp: tmp}
  end

  test "match: identical eligible identity sets PASS", %{tmp: tmp} do
    mix =
      write_json(tmp, "mix.json", %{
        "eligible" => [%{"identity" => "FRI-FMT-A"}],
        "blocked" => [%{"identity" => "FRI-FMT-B", "reason" => "dependencies_unsatisfied"}]
      })

    hf =
      write_json(tmp, "hf.json", %{
        "eligible" => [%{"identity" => "FRI-FMT-A"}],
        "blocked" => [%{"identity" => "FRI-FMT-B", "reason" => "dependencies_unsatisfied"}]
      })

    {out, code} = System.cmd("python3", [@parity_py, mix, hf], stderr_to_stdout: true)
    assert code == 0, "match must PASS, got exit=#{code} out=#{out}"
    assert out =~ "hands-free twin parity: ok"
  end

  test "FLIP: Mix eligible≠[] vs Rust eligible=[] REFUSES HANDS_FREE_TWIN_DRIFT", %{
    tmp: tmp
  } do
    # Skeptic L19 evidence shape: Mix friday eligible=1; Rust authority_index_unavailable.
    mix =
      write_json(tmp, "mix.json", %{
        "status" => "ok",
        "eligible" => [%{"identity" => "FRI-FMT-A"}],
        "blocked" => [%{"identity" => "FRI-FMT-B", "reason" => "dependencies_unsatisfied"}]
      })

    hf =
      write_json(tmp, "hf.json", %{
        "blocked" => [
          %{"identity" => "FRI-FMT-A", "reason" => "authority_index_unavailable"},
          %{"identity" => "FRI-FMT-B", "reason" => "authority_index_unavailable"}
        ],
        "eligible" => [],
        "eligible_count" => 0,
        "standings" => %{}
      })

    {out, code} = System.cmd("python3", [@parity_py, mix, hf], stderr_to_stdout: true)
    assert code == 1, "mismatch must REFUSE exit=1, got exit=#{code} out=#{out}"
    assert out =~ "HANDS_FREE_TWIN_DRIFT"
    assert out =~ "FRI-FMT-A"
  end

  test "self-test harness: match PASS + mismatch REFUSE", %{tmp: _tmp} do
    {out, code} =
      System.cmd("python3", [@parity_py, "--self-test"], stderr_to_stdout: true)

    assert code == 0, "self-test must PASS, got exit=#{code} out=#{out}"
    assert out =~ "HANDS_FREE_TWIN_DRIFT"
  end

  defp write_json(tmp, name, doc) do
    path = Path.join(tmp, name)
    File.write!(path, Jason.encode!(doc) <> "\n")
    path
  end
end
