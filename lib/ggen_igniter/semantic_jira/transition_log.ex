defmodule GgenIgniter.SemanticJira.TransitionLog do
  @moduledoc """
  Append-only, file-backed log of standing transition events (one immutable
  JSON file per event, named `<seq>-<event_digest>.json` under a caller-given
  directory).

  - `append/2` assigns the next `seq` with an exclusive create, retrying on a
    concurrent writer; an event whose `event_digest` is already present is
    returned unchanged (idempotent). Existing files are never rewritten.
  - `read/1` returns events ordered by `seq`.

  The WorkOrder definition is never touched; current standing is the
  projection `GgenIgniter.SemanticJira.project/2` of this log over the graph.
  """

  alias GgenIgniter.SemanticJira

  @spec read(Path.t()) :: [map()]
  def read(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&(dir |> Path.join(&1) |> File.read!() |> Jason.decode!()))

      {:error, :enoent} ->
        []
    end
  end

  @spec append(Path.t(), map()) :: {:ok, map(), :appended | :already_recorded}
  def append(dir, event) do
    File.mkdir_p!(dir)
    event = Map.put(event, "event_digest", SemanticJira.digest(Map.delete(event, "seq")))

    case Enum.find(read(dir), &(&1["event_digest"] == event["event_digest"])) do
      nil -> write(dir, event, length(read(dir)) + 1)
      existing -> {:ok, existing, :already_recorded}
    end
  end

  defp write(dir, event, seq) do
    stamped = Map.put(event, "seq", seq)

    name =
      "#{String.pad_leading(Integer.to_string(seq), 8, "0")}-#{String.slice(event["event_digest"], 7, 16)}.json"

    case File.open(Path.join(dir, name), [:write, :exclusive]) do
      {:ok, io} ->
        IO.write(io, Jason.encode!(stamped))
        File.close(io)
        {:ok, stamped, :appended}

      {:error, :eexist} ->
        case Enum.find(read(dir), &(&1["event_digest"] == event["event_digest"])) do
          nil -> write(dir, event, seq + 1)
          existing -> {:ok, existing, :already_recorded}
        end
    end
  end
end
