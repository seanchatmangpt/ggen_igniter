defmodule GgenIgniter.DoctrineAdmission.StepOrder do
  @moduledoc "Strategic-doctrine step_order boundary."
  def admit(%{"subject" => s, "source_sha" => sha} = v)
      when is_binary(s) and byte_size(s) > 0 and is_binary(sha) and byte_size(sha) == 40,
      do:
        {:ok,
         Map.merge(v, %{
           "boundary" => "step_order",
           "authority" => "NONE",
           "ceiling" => "CONSTRUCT"
         })}

  def admit(_), do: {:error, {:refused_doctrine, :step_order, :invalid_exact_subject}}
end
