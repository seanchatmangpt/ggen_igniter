defmodule GgenIgniter.DoctrineAdmission.Applicability do
  @moduledoc "Strategic-doctrine applicability boundary."
  def admit(%{"subject" => s, "source_sha" => sha} = v)
      when is_binary(s) and byte_size(s) > 0 and is_binary(sha) and byte_size(sha) == 40,
      do:
        {:ok,
         Map.merge(v, %{
           "boundary" => "applicability",
           "authority" => "NONE",
           "ceiling" => "CONSTRUCT"
         })}

  def admit(_), do: {:error, {:refused_doctrine, :applicability, :invalid_exact_subject}}
end
