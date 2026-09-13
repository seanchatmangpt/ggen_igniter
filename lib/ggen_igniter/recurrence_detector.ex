defmodule GgenIgniter.RecurrenceDetector do
  @moduledoc """
  Detects repeated reasoning classes across OCEL-shaped reconciliation events
  and returns deterministic candidates for externalizing that recurrence into
  a reusable pack/template.

  This module is deliberately OBSERVE/SELECT only. It never writes a pack,
  edits a template, invokes ggen, or acquires actuation authority. A returned
  candidate has `standing: "CANDIDATE"` and `authority: "NONE"` until a
  separate manufacturing/admission path constructs and verifies a reusable
  artifact.

  The detector consumes the event shape emitted by
  `GgenIgniter.Telemetry.OcelEmitter`: the reasoning class is read from the
  event attributes (`reasoning_class` or `reasoning_class_id`) and run
  identity is read from explicit `reconcile_run` objects. Repetition inside a
  single run is not sufficient evidence of cross-run recurrence.
  """

  @default_min_occurrences 3
  @default_min_distinct_runs 2

  @typedoc "A deterministic recommendation to externalize repeated reasoning."
  @type candidate :: %{
          required(String.t()) => String.t() | non_neg_integer() | [String.t()]
        }

  @doc """
  Scans OCEL-shaped events and returns recurrence candidates.

  Options:

    * `:min_occurrences` - minimum classified event count, default 3
    * `:min_distinct_runs` - minimum distinct explicit reconciliation runs,
      default 2

  Events without an explicit reasoning class or explicit `reconcile_run`
  object remain observable input but do not qualify a cross-run candidate.
  """
  @spec scan([map()], keyword()) :: [candidate()]
  def scan(events, opts \\ []) when is_list(events) and is_list(opts) do
    min_occurrences = positive_integer!(opts, :min_occurrences, @default_min_occurrences)
    min_distinct_runs = positive_integer!(opts, :min_distinct_runs, @default_min_distinct_runs)

    events
    |> Enum.reduce(%{}, &accumulate/2)
    |> Enum.flat_map(fn {reasoning_class, evidence} ->
      occurrence_count = length(evidence.events)
      run_ids = evidence.run_ids |> MapSet.to_list() |> Enum.sort()

      if occurrence_count >= min_occurrences and length(run_ids) >= min_distinct_runs do
        activities = evidence.activities |> MapSet.to_list() |> Enum.sort()

        [
          %{
            "kind" => "reusable_reasoning_candidate",
            "reasoning_class" => reasoning_class,
            "occurrences" => occurrence_count,
            "distinct_runs" => length(run_ids),
            "run_ids" => run_ids,
            "activities" => activities,
            "recommendation" => "pack_or_template",
            "standing" => "CANDIDATE",
            "authority" => "NONE"
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1["reasoning_class"])
  end

  defp accumulate(event, acc) when is_map(event) do
    with reasoning_class when is_binary(reasoning_class) <- reasoning_class(event),
         run_ids when run_ids != [] <- run_ids(event) do
      activity = Map.get(event, "activity")

      Map.update(
        acc,
        reasoning_class,
        %{events: [event], run_ids: MapSet.new(run_ids), activities: activity_set(activity)},
        fn evidence ->
          %{
            events: [event | evidence.events],
            run_ids: Enum.reduce(run_ids, evidence.run_ids, &MapSet.put(&2, &1)),
            activities:
              if(is_binary(activity),
                do: MapSet.put(evidence.activities, activity),
                else: evidence.activities
              )
          }
        end
      )
    else
      _ -> acc
    end
  end

  defp reasoning_class(event) do
    attributes = Map.get(event, "attributes", %{})

    case attributes do
      %{} ->
        Map.get(attributes, "reasoning_class") ||
          Map.get(attributes, "reasoning_class_id") ||
          Map.get(attributes, :reasoning_class) ||
          Map.get(attributes, :reasoning_class_id)

      _ ->
        nil
    end
  end

  defp run_ids(event) do
    event
    |> Map.get("objects", [])
    |> Enum.flat_map(fn
      %{"type" => "reconcile_run", "id" => id} when is_binary(id) -> [id]
      %{type: "reconcile_run", id: id} when is_binary(id) -> [id]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp activity_set(activity) when is_binary(activity), do: MapSet.new([activity])
  defp activity_set(_), do: MapSet.new()

  defp positive_integer!(opts, key, default) do
    value = Keyword.get(opts, key, default)

    if is_integer(value) and value > 0 do
      value
    else
      raise ArgumentError, "#{key} must be a positive integer"
    end
  end
end
