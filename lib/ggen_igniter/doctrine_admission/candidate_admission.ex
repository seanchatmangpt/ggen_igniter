defmodule GgenIgniter.DoctrineAdmission.CandidateAdmission do
  @moduledoc "Strategic-doctrine candidate_admission boundary."
  def admit(%{"subject"=>s,"source_sha"=>sha}=v) when is_binary(s) and byte_size(s)>0 and is_binary(sha) and byte_size(sha)==40, do: {:ok,Map.merge(v,%{"boundary"=>"candidate_admission","authority"=>"NONE","ceiling"=>"CONSTRUCT"})}
  def admit(_), do: {:error,{:refused_doctrine,:candidate_admission,:invalid_exact_subject}}
end
