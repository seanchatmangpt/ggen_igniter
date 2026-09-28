defmodule GgenIgniter.DoctrineAdmission.StandingGuard do
  @moduledoc "Strategic-doctrine standing_guard boundary."
  def admit(%{"subject"=>s,"source_sha"=>sha}=v) when is_binary(s) and byte_size(s)>0 and is_binary(sha) and byte_size(sha)==40, do: {:ok,Map.merge(v,%{"boundary"=>"standing_guard","authority"=>"NONE","ceiling"=>"CONSTRUCT"})}
  def admit(_), do: {:error,{:refused_doctrine,:standing_guard,:invalid_exact_subject}}
end
