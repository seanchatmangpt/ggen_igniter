defmodule GgenIgniter.DoctrineAdmission.SourceIdentity do
  @moduledoc """
  Exact source contract for strategic doctrine.

  The canonical semantic owner is the merged ggen-marketplace strategic-doctrine
  pack. Consumers may project it, but may not redefine or widen its authority.
  """

  @repository "seanchatmangpt/ggen-marketplace"
  @source_sha "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"
  @artifact_sha "225e3eff18f0570817646ebf7c210117ee1a82b5"
  @source_path "packs/strategic-doctrine-pack"
  @authority "NONE"
  @ceiling "CONSTRUCT"

  def contract do
    %{
      "source_repository" => @repository,
      "source_sha" => @source_sha,
      "source_artifact_sha" => @artifact_sha,
      "source_path" => @source_path,
      "authority" => @authority,
      "ceiling" => @ceiling
    }
  end

  def admit(%{
        "subject" => subject,
        "source_repository" => @repository,
        "source_sha" => @source_sha
      } = value)
      when is_binary(subject) and byte_size(subject) > 0 do
    {:ok,
     value
     |> Map.put("source_artifact_sha", @artifact_sha)
     |> Map.put("source_path", @source_path)
     |> Map.put("boundary", "source_identity")
     |> Map.put("authority", @authority)
     |> Map.put("ceiling", @ceiling)}
  end

  def admit(%{"source_repository" => repository, "source_sha" => sha})
      when is_binary(repository) and is_binary(sha),
      do: {:error, {:refused_doctrine, :source_identity, {:source_mismatch, repository, sha}}}

  def admit(_),
    do: {:error, {:refused_doctrine, :source_identity, :invalid_exact_subject}}
end
