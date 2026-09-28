defmodule GgenIgniter.DoctrineAdmission.ExactSubject do
  @moduledoc "Bounded strategic-doctrine admission boundary: exact_subject."
  def admit(%{"subject" => s, "source_sha" => sha}=v) when is_binary(s) and byte_size(s)>0 and is_binary(sha) and byte_size(sha)==40, do: {:ok, Map.merge(v,%{"boundary"=>"exact_subject","authority"=>"NONE","ceiling"=>"CONSTRUCT"})}
  def admit(_), do: {:error,{:refused_doctrine,:exact_subject,:invalid_exact_subject}}
end
