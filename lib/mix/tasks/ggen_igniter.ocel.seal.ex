defmodule Mix.Tasks.GgenIgniter.Ocel.Seal do
  @shortdoc "Seals an OCEL v2 manufacturing log with the run's observed outcome."

  @moduledoc """
  Appends an outcome event to an OCEL 2.0 log written by a composed
  manufacture task, based on what the caller OBSERVED after the run.

  ## Why this exists

  A composed `Igniter.Mix.Task` emits its decisions from inside `igniter/1`
  -- that is the only place the decisions exist. But `igniter/1` runs
  BEFORE `Igniter.do_or_dry_run/2` applies anything
  (`igniter/lib/mix/task.ex:112` then `:119`), so a run that is declined at
  the confirmation prompt, or that aborts mid-apply, still leaves a log
  full of `task_composed` events for files that never reached disk.
  Reproduced: killing a `--phase core` run at the confirmation prompt left
  no `sort_by_title.ex` on disk and a log asserting its composition.

  Emitting the log later cannot fix this, because the guard decisions
  (composed vs admission-refused) depend on module existence BEFORE the run
  and are unrecoverable afterwards. So the log stays where it is and stops
  being self-certifying instead: this task appends the outcome the CALLER
  observed, and the conformance checker treats a log with no seal as
  non-conformant. An aborted run therefore produces an UNSEALED log, which
  reads as a failure rather than as success.

  The seal records an observation, not a judgement -- it does not re-check
  the tree, because the caller (the qualification harness) is the thing
  that holds the exit code and the compile result.

  ## Example

      mix ggen_igniter.ocel.seal path/to/run.ocel.json --exit 0 \\
        --observed "compile ok; 11 files manufactured"

  Exit code `0` seals the log `applied`; any other value seals it
  `aborted`. Sealing a log twice is refused rather than silently appended
  to, so a stale seal cannot be laundered into a fresh one.
  """

  use Mix.Task

  @activity_applied "manufacture_run_applied"
  @activity_aborted "manufacture_run_aborted"

  @doc false
  def activities, do: {@activity_applied, @activity_aborted}

  @impl Mix.Task
  def run(argv) do
    {opts, positional, _} =
      OptionParser.parse(argv,
        strict: [exit: :integer, observed: :string, run_id: :string],
        aliases: [e: :exit, o: :observed]
      )

    path =
      case positional do
        [path] ->
          path

        other ->
          Mix.raise("""
          expected exactly one OCEL log path, got: #{inspect(other)}

              mix ggen_igniter.ocel.seal <log.ocel.json> --exit <code>
          """)
      end

    unless File.exists?(path) do
      Mix.raise("no OCEL log at #{path} -- a manufacture run that wrote nothing cannot be sealed")
    end

    doc = path |> File.read!() |> Jason.decode!()
    exit_code = Keyword.get(opts, :exit, 0)
    observed = Keyword.get(opts, :observed, "")

    if sealed?(doc) do
      Mix.raise("""
      #{path} is already sealed.

      Re-sealing would let a stale outcome be replaced by a fresh-looking
      one. Re-run the manufacture step to produce a new log instead.
      """)
    end

    run_id =
      Keyword.get_lazy(opts, :run_id, fn ->
        doc
        |> Map.get("events", [])
        |> Enum.flat_map(&Map.get(&1, "relationships", []))
        |> Enum.find_value("run", fn r ->
          if r["qualifier"] == "run", do: r["objectId"]
        end)
      end)

    activity = if exit_code == 0, do: @activity_applied, else: @activity_aborted

    events =
      rebuild_events(doc) ++
        [
          # The run object is named here so the seal event says what it is
          # about on its own terms. `Ocel2Export.normalize_event/4` also
          # appends the run relationship to every event and dedupes the pair
          # (`ocel2_export.ex:177`), so this does not double it -- and the
          # reconciliation lives THERE, in the one place that knows about
          # both sides. Do not also strip it here: two guards for one
          # invariant is how the duplicate survived the first time.
          %{
            "activity" => activity,
            "objects" => [%{"type" => "manufacture_run", "id" => run_id, "qualifier" => "run"}],
            "attributes" => %{"exit" => exit_code, "observed" => observed}
          }
        ]

    GgenIgniter.Telemetry.Ocel2Export.write!(path, events,
      run_id: run_id,
      run_type: "manufacture_run"
    )

    Mix.shell().info("ggen_igniter: sealed #{path} as #{activity} (exit #{exit_code})")
  end

  defp sealed?(doc) do
    doc
    |> Map.get("events", [])
    |> Enum.any?(&(&1["type"] in [@activity_applied, @activity_aborted]))
  end

  # Turn the serialized OCEL events back into the input shape
  # `Ocel2Export.document/2` accepts, so the seal is appended by the same
  # serializer that wrote the log rather than by a second, divergent writer.
  defp rebuild_events(doc) do
    doc
    |> Map.get("events", [])
    |> Enum.map(fn e ->
      %{
        "activity" => e["type"],
        "time" => e["time"],
        "objects" =>
          e
          |> Map.get("relationships", [])
          |> Enum.reject(&(&1["qualifier"] == "run"))
          |> Enum.map(fn r ->
            %{
              "type" => object_type(doc, r["objectId"]),
              "id" => r["objectId"],
              "qualifier" => r["qualifier"]
            }
          end),
        "attributes" =>
          e
          |> Map.get("attributes", [])
          |> Map.new(fn a -> {a["name"], a["value"]} end)
      }
    end)
  end

  defp object_type(doc, id) do
    doc
    |> Map.get("objects", [])
    |> Enum.find_value("unknown", fn o -> if o["id"] == id, do: o["type"] end)
  end
end
