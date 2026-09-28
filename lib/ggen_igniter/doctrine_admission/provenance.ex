defmodule GgenIgniter.DoctrineAdmission.Provenance do
  @moduledoc "Bounded strategic-doctrine admission boundary: provenance."
  @authority "NONE"
  @ceiling "CONSTRUCT"
  def admit(%{"subject" => subject, "source_sha" => sha}=value)
      when is_binary(subject) and byte_size(subject)>0 and is_binary(sha) and byte_size(sha)==40 do
    {:ok, Map.merge(value, %{"boundary"=>"provenance","authority"=>@authority,"ceiling"=>@ceiling})}
  end
  def admit(_), do: {:error, {:refused_doctrine, :provenance, :invalid_exact_subject}}
end
