defmodule GgenIgniter.DoctrineAdmission.HddlProjection do
  @moduledoc "Projects admitted doctrine methods into a generator-neutral HDDL IR."
  alias GgenIgniter.DoctrineAdmission.Method

  def project(candidate) do
    with {:ok, method} <- Method.build(candidate) do
      ids = Enum.map(method["steps"], &"s#{&1["order"]}")
      subtasks = Enum.zip(ids, Enum.map(method["steps"], & &1["operator"]))
      ordering = ids |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> {a, b} end)
      {:ok, %{"task" => "achieve:" <> method["strategy"], "method" => "method:" <> method["strategy"], "subtasks" => subtasks, "ordering" => ordering, "authority" => "NONE", "ceiling" => "CONSTRUCT"}}
    end
  end
end
