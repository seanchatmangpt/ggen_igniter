defmodule GgenIgniter.DoctrineAdmission.Idempotence do
  @moduledoc "Defines duplicate doctrine manufacture by exact identity plus digest."

  def same?(
        %{"identity" => id, "receipt_digest" => digest},
        %{"identity" => id, "receipt_digest" => digest}
      ),
      do: true

  def same?(_, _), do: false

  def classify(previous, next) do
    if same?(previous, next), do: {:ok, :duplicate_noop}, else: {:ok, :distinct}
  end
end
