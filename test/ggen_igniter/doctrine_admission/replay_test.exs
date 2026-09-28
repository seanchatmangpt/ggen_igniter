defmodule GgenIgniter.DoctrineAdmission.ReplayTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.{Receipt, Replay}

  test "replay admits exact subject and rejects mismatched subject" do
    work = %{"identity" => "doctrine:s1:o1", "subject_sha" => String.duplicate("c", 40)}
    {:ok, receipt} = Receipt.issue(work, %{"result" => "ok"})
    assert :ok = Replay.verify(receipt, work)

    other = %{"identity" => work["identity"], "subject_sha" => String.duplicate("d", 40)}
    assert {:error, {:refused_doctrine, :replay, :subject_mismatch}} = Replay.verify(receipt, other)
  end
end
