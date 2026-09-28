defmodule GgenIgniter.DoctrineAdmission.AuditConsumer do
  @moduledoc "Projects receipt/replay identity for an authority-free audit consumer."

  def project(%{"identity" => id, "receipt_digest" => digest, "subject_sha" => sha})
      when is_binary(id) and is_binary(digest) and is_binary(sha) do
    {:ok, %{kind: :audit_record, identity: id, digest: digest, subject_sha: sha, authority: :none}}
  end

  def project(_), do: {:error, {:refused_doctrine, :consumer, :invalid_audit_input}}
end
