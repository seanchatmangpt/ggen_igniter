defmodule GgenIgniter.DoctrineAdmission.ReplayTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.{Receipt, Replay}

  defp work(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "doctrine:s1:o1",
        "subject_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa",
        "source_repository" => "seanchatmangpt/ggen-marketplace",
        "source_artifact_sha" => "225e3eff18f0570817646ebf7c210117ee1a82b5",
        "source_path" => "packs/strategic-doctrine-pack"
      },
      overrides
    )
  end

  test "replay admits exact source-bound subject" do
    subject = work()
    {:ok, receipt} = Receipt.issue(subject, %{"result" => "ok"})
    assert :ok = Replay.verify(receipt, subject)
  end

  test "replay refuses source/path drift" do
    subject = work()
    {:ok, receipt} = Receipt.issue(subject, %{"result" => "ok"})

    assert {:error, {:refused_doctrine, :replay, :subject_mismatch}} =
             Replay.verify(receipt, work(%{"source_artifact_sha" => String.duplicate("d", 40)}))

    assert {:error, {:refused_doctrine, :replay, :subject_mismatch}} =
             Replay.verify(receipt, work(%{"source_path" => "packs/not-doctrine"}))
  end
end
