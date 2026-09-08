defmodule GgenIgniterOcelSealTest do
  @moduledoc """
  Chicago-school tests for `mix ggen_igniter.ocel.seal`: a real OCEL 2.0 log
  written to a real temp directory by the real serializer
  (`GgenIgniter.Telemetry.Ocel2Export`), then the real task's `run/1` invoked
  against it, then assertions on the real re-decoded file. No doubles --
  every collaborator here (the filesystem, `Jason`, `Mix.shell/0`, the
  serializer) genuinely runs in-process.

  The task advertises three behaviours that nothing previously exercised:

    * exit code `0` seals a log `manufacture_run_applied`, any other value
      seals it `manufacture_run_aborted`
      (`ggen_igniter.ocel.seal.ex:97`);
    * the seal is an *observation about a finished run*, so it must append
      one event and leave every pre-existing event -- its id and its
      timestamp -- untouched;
    * sealing an already-sealed log is REFUSED
      (`ggen_igniter.ocel.seal.ex:78-85`), which is the whole anti-laundering
      claim in the task's moduledoc and had no test at all.

  Activity names, object types, qualifiers, attribute names, event counts,
  timestamps, exit codes and the observation text are all Faker-generated.
  The values that are fixed are fixed because they are contracts with the
  code under test, and each says so where it is defined. The two outcome
  activity names are not hardcoded at all -- they are read back from
  `Seal.activities/0`, which is strictly stronger than restating them.

  `async: false` because `Mix.shell/0` and captured stdout are global
  process state, the same reason `ggen_igniter_sync_inprocess_dispatch_test`
  is serialized.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GgenIgniter.Telemetry.Ocel2Export
  alias Mix.Tasks.GgenIgniter.Ocel.Seal

  # Hardcoded by the task as the run object's OCEL type
  # (`ggen_igniter.ocel.seal.ex:111` and `:118`), so a log it can seal must
  # already use it. A contract with the code under test, not test data.
  @run_type "manufacture_run"

  # Hardcoded by the serializer at `ocel2_export.ex:163` as the name under
  # which every event is related to its run. The task's run-id derivation
  # (`ggen_igniter.ocel.seal.ex:92-94`) searches for exactly this string.
  @run_qualifier "run"

  # The two attribute names the task writes onto its seal event
  # (`ggen_igniter.ocel.seal.ex:112`). Contract, not test data.
  @exit_attr "exit"
  @observed_attr "observed"

  setup do
    dir = Path.join(System.tmp_dir!(), "ggen_igniter_seal_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    run_id = Faker.Lorem.word() <> ".manufacture:" <> Faker.String.base64(6)
    path = Path.join([dir, Faker.Lorem.word(), "run.ocel.json"])

    # Explicit per-event times, spaced by whole seconds, so "the seal did not
    # restamp anything" is a byte-comparison rather than a guess. Truncating
    # to millisecond precision pins the rendered ISO8601 form.
    base =
      Faker.random_between(2, 30)
      |> Faker.DateTime.backward()
      |> DateTime.truncate(:millisecond)

    [subject_type, subject_qualifier, attr] = distinct_words(3)
    count = Faker.random_between(3, 7)

    events =
      for index <- 1..count do
        %{
          "activity" => Faker.Lorem.word() <> "_" <> Faker.Lorem.word(),
          "time" => base |> DateTime.add(index, :second) |> DateTime.to_iso8601(),
          "objects" => [
            %{
              "type" => subject_type,
              "id" => Enum.map_join(1..3, ".", fn _ -> String.capitalize(Faker.Lorem.word()) end),
              "qualifier" => subject_qualifier
            }
          ],
          "attributes" => %{attr => Faker.Lorem.word()}
        }
      end

    Ocel2Export.write!(path, events, run_id: run_id, run_type: @run_type)

    {applied, aborted} = Seal.activities()

    %{
      path: path,
      run_id: run_id,
      count: count,
      before: read!(path),
      applied: applied,
      aborted: aborted
    }
  end

  # Faker's lorem pool is small enough that independent draws collide; a
  # collision between a qualifier and an object type would make an assertion
  # ambiguous rather than false. `@run_qualifier` is excluded so a generated
  # qualifier can never be confused with the run relationship.
  defp distinct_words(n) do
    Stream.repeatedly(&Faker.Lorem.word/0)
    |> Stream.reject(&(&1 == @run_qualifier))
    |> Stream.uniq()
    |> Enum.take(n)
  end

  defp read!(path), do: path |> File.read!() |> Jason.decode!()

  defp seal!(argv), do: capture_io(fn -> Seal.run(argv) end)

  test "exit 0 appends exactly one applied event and restamps nothing", ctx do
    observed = Faker.Lorem.sentence()

    output = seal!([ctx.path, "--exit", "0", "--observed", observed])

    sealed = read!(ctx.path)
    assert length(sealed["events"]) == ctx.count + 1

    appended = List.last(sealed["events"])
    assert appended["type"] == ctx.applied

    assert Enum.count(sealed["events"], &(&1["type"] == ctx.applied)) == 1,
           "a seal must append one outcome event, not several"

    # A seal records an observation about a run that already finished, so
    # every pre-existing event survives byte-for-byte -- id and timestamp
    # alike. If the serializer restamped them, a consumer sorting by time
    # would see the run happen at seal time instead of at run time.
    kept = Enum.take(sealed["events"], ctx.count)
    assert Enum.map(kept, & &1["time"]) == Enum.map(ctx.before["events"], & &1["time"])
    assert Enum.map(kept, & &1["id"]) == Enum.map(ctx.before["events"], & &1["id"])
    assert Enum.map(kept, & &1["type"]) == Enum.map(ctx.before["events"], & &1["type"])

    assert %{"name" => @exit_attr, "value" => 0} in appended["attributes"]
    assert %{"name" => @observed_attr, "value" => observed} in appended["attributes"]

    assert output =~ ctx.applied
  end

  test "the seal event is related to the run it was derived from, exactly once", ctx do
    seal!([ctx.path, "--exit", "0"])

    appended = List.last(read!(ctx.path)["events"])

    # The run id is never passed on the command line here: the task derives
    # it from the existing log's own run relationship
    # (`ggen_igniter.ocel.seal.ex:88-95`).
    assert appended["relationships"] == [
             %{"objectId" => ctx.run_id, "qualifier" => @run_qualifier}
           ]
  end

  test "no event in a sealed log repeats an (objectId, qualifier) pair", ctx do
    seal!([ctx.path, "--exit", "0"])

    for event <- read!(ctx.path)["events"] do
      pairs = Enum.map(event["relationships"], &{&1["objectId"], &1["qualifier"]})

      assert pairs == Enum.uniq(pairs),
             "#{event["id"]} repeats a relationship: #{inspect(pairs)}"
    end
  end

  test "a non-zero --exit seals the log aborted", ctx do
    code = Faker.random_between(1, 255)

    output = seal!([ctx.path, "--exit", to_string(code)])

    appended = List.last(read!(ctx.path)["events"])
    assert appended["type"] == ctx.aborted
    assert %{"name" => @exit_attr, "value" => code} in appended["attributes"]
    assert output =~ ctx.aborted
  end

  test "the sealed outcome is a declared eventType, not a bare event", ctx do
    seal!([ctx.path, "--exit", "0"])

    names = read!(ctx.path)["eventTypes"] |> Enum.map(& &1["name"])

    assert ctx.applied in names
    refute ctx.aborted in names
  end

  test "sealing an already-sealed log is refused rather than laundered", ctx do
    seal!([ctx.path, "--exit", "0"])
    once_sealed = File.read!(ctx.path)

    assert_raise Mix.Error, ~r/already sealed/, fn ->
      seal!([ctx.path, "--exit", "0"])
    end

    # The refusal must not have rewritten the log on its way out, or a failed
    # re-seal would still have destroyed the original outcome.
    assert File.read!(ctx.path) == once_sealed
  end

  test "an aborted log cannot be re-sealed as applied", ctx do
    seal!([ctx.path, "--exit", to_string(Faker.random_between(1, 255))])

    assert_raise Mix.Error, ~r/already sealed/, fn ->
      seal!([ctx.path, "--exit", "0"])
    end

    assert List.last(read!(ctx.path)["events"])["type"] == ctx.aborted
  end

  test "a run that wrote no log cannot be sealed", ctx do
    missing = Path.join(Path.dirname(ctx.path), Faker.File.file_name(:text))

    assert_raise Mix.Error, ~r/no OCEL log at/, fn -> seal!([missing, "--exit", "0"]) end
  end

  test "the log path is required and must be unambiguous", ctx do
    assert_raise Mix.Error, ~r/exactly one OCEL log path/, fn -> seal!(["--exit", "0"]) end

    assert_raise Mix.Error, ~r/exactly one OCEL log path/, fn ->
      seal!([ctx.path, ctx.path, "--exit", "0"])
    end
  end
end
