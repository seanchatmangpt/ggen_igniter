defmodule GgenIgniterOcel2ExportTest do
  @moduledoc """
  Chicago-school tests for `GgenIgniter.Telemetry.Ocel2Export`: real event
  maps in, a real file on a real temp directory out, assertions on the real
  decoded document. No doubles -- the collaborators under test are JSON
  encoding and the filesystem, both genuinely runnable in-process.

  Every activity name, object id, object type, qualifier, attribute name and
  attribute value is generated with `Faker` rather than hardcoded, so an
  assertion can only pass by way of the property it names. A test that says
  "the activity becomes a declared eventType" must hold for
  `Faker.Lorem.word()` exactly as it holds for `"task_composed"`; if it only
  passed for a literal we wrote by hand, it was asserting a coincidence.
  Generating the *qualifiers* and *attribute names* matters for the same
  reason: an implementation that recognised only a fixed `"subject"` /
  `"generator"` vocabulary would have satisfied an earlier revision of this
  file, which hardcoded exactly those.

  Four kinds of fixed value survive on purpose, and only these:

    * `@fixed_time` -- byte-determinism cannot be tested against a moving
      clock.
    * `@required_keys` -- the four OCEL 2.0 top-level key names are the
      external contract with `beam4pm`'s importer, not test data.
    * `@run_qualifier` -- `"run"` is hardcoded in the implementation
      (`ocel2_export.ex:163`), so it is part of the contract under test.
      Generating it by coincidence would make the run-relationship
      assertions ambiguous, so `words/1` excludes it from the pool.
    * The OCEL attribute type names (`"integer"`, `"float"`, `"boolean"`,
      `"string"`) -- the implementation's output vocabulary being asserted,
      not an input being chosen.

  The load-bearing property is that the emitted document satisfies the
  exact OCEL 2.0 shape `beam4pm`'s importer
  (`BeamPM.Rust4PM.import_ocel_json/2`, backed by `process_mining` 0.6.2)
  requires: those four top-level keys, and per-event `relationships`
  entries carrying `objectId` + `qualifier`. A document missing
  `eventTypes` is rejected there with a typed refusal, so "we emitted some
  events" is not the property worth asserting.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Telemetry.Ocel2Export

  # Fixed because determinism is under test, not because the value matters.
  @fixed_time "2026-01-01T00:00:00Z"

  # The OCEL 2.0 contract with beam4pm's importer. Not test data.
  @required_keys ["eventTypes", "events", "objectTypes", "objects"]

  # Hardcoded by the implementation at `ocel2_export.ex:163`: the name under
  # which every event is related to its run. A contract, not test data.
  @run_qualifier "run"

  defp module_name,
    do: Enum.map_join(1..3, ".", fn _ -> Faker.Lorem.word() |> String.capitalize() end)

  defp run_id, do: "run_" <> Faker.String.base64(8)

  defp activity, do: Faker.Lorem.word() <> "_" <> Faker.Lorem.word()

  # Faker draws from a 249-word lorem pool, so two independent draws collide
  # often enough to matter at this sample size. A collision between two
  # qualifiers, two object types or two attribute names would make an
  # assertion ambiguous rather than false, so distinctness is enforced here
  # instead of hoped for. `@run_qualifier` is excluded so a generated
  # qualifier can never be mistaken for the run relationship.
  defp words(n) do
    Stream.repeatedly(&Faker.Lorem.word/0)
    |> Stream.reject(&(&1 == @run_qualifier))
    |> Stream.uniq()
    |> Enum.take(n)
  end

  defp iso!(string) do
    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(string)
    datetime
  end

  defp scenario do
    [
      run_type,
      subject_type,
      generator_type,
      absent_type,
      subject_qualifier,
      generator_qualifier,
      phase_attr,
      retries_attr,
      standing_attr,
      composed_a,
      composed_b,
      refused_a,
      refused_b,
      absent_a,
      absent_b,
      generator_a,
      generator_b,
      broken_a,
      broken_b
    ] = words(19)

    s = %{
      run_id: run_id(),
      run_type: run_type,
      composed_activity: composed_a <> "_" <> composed_b,
      refused_activity: refused_a <> "_" <> refused_b,
      # An activity and an object type this scenario never emits. Built from
      # the same distinct pool, so "never declared" is guaranteed by
      # construction rather than left to a lucky draw.
      absent_activity: absent_a <> "_" <> absent_b,
      absent_type: absent_type,
      subject: module_name(),
      subject_type: subject_type,
      subject_qualifier: subject_qualifier,
      generator: generator_a <> "." <> generator_b,
      broken_generator: broken_a <> "." <> broken_b,
      generator_type: generator_type,
      generator_qualifier: generator_qualifier,
      phase_attr: phase_attr,
      phase: Faker.Lorem.word(),
      retries_attr: retries_attr,
      retries: Faker.random_between(0, 9),
      standing_attr: standing_attr,
      standing: Faker.Lorem.word() |> String.upcase()
    }

    Map.put(s, :events, [
      %{
        "activity" => s.composed_activity,
        "objects" => [
          %{"type" => s.subject_type, "id" => s.subject, "qualifier" => s.subject_qualifier},
          %{
            "type" => s.generator_type,
            "id" => s.generator,
            "qualifier" => s.generator_qualifier
          }
        ],
        "attributes" => %{s.phase_attr => s.phase, s.retries_attr => s.retries}
      },
      %{
        "activity" => s.refused_activity,
        "objects" => [
          %{
            "type" => s.generator_type,
            "id" => s.broken_generator,
            "qualifier" => s.generator_qualifier
          }
        ],
        "attributes" => %{s.standing_attr => s.standing}
      }
    ])
  end

  defp document(s) do
    Ocel2Export.document(s.events, run_id: s.run_id, run_type: s.run_type, time: @fixed_time)
  end

  test "emits exactly the top-level keys beam4pm's importer requires" do
    assert document(scenario()) |> Map.keys() |> Enum.sort() == @required_keys
  end

  test "event types are synthesized from the activities actually present, and no others" do
    s = scenario()
    names = document(s)["eventTypes"] |> Enum.map(& &1["name"])

    assert Enum.sort(names) == Enum.sort([s.composed_activity, s.refused_activity])

    # An activity that never occurred must never be declared.
    refute s.absent_activity in names
  end

  test "object types are synthesized from the objects actually present, and no others" do
    s = scenario()
    names = document(s)["objectTypes"] |> Enum.map(& &1["name"])

    # The two generators share one type, so three distinct types exist even
    # though four objects do.
    assert Enum.sort(names) == Enum.sort([s.run_type, s.subject_type, s.generator_type])
    assert names == Enum.sort(names), "declared object types must be deterministically ordered"

    refute s.absent_type in names
  end

  test "declared attribute types come from the real runtime values" do
    s = scenario()
    declared = Enum.find(document(s)["eventTypes"], &(&1["name"] == s.composed_activity))

    assert %{"name" => s.phase_attr, "type" => "string"} in declared["attributes"]
    assert %{"name" => s.retries_attr, "type" => "integer"} in declared["attributes"]
  end

  test "every declared attribute type follows its value's real runtime type" do
    [float_attr, bool_attr, atom_attr, term_attr, int_attr] = words(5)
    act = activity()

    # Division always yields a float in Elixir, so this is a generated float
    # without going through `Faker.random_uniform/0`, whose 0.18.0
    # implementation emits a `map.field` deprecation warning at every call.
    float_value = Faker.random_between(1, 9_999) / 100
    bool_value = Faker.Util.pick([true, false])
    atom_value = String.to_atom(Faker.Lorem.word())
    # A term Jason cannot encode at all: the reason `encodable/1` exists.
    term_value = {Faker.Lorem.word(), Faker.random_between(1, 99)}
    int_value = Faker.random_between(10, 99)

    doc =
      Ocel2Export.document(
        [
          %{
            "activity" => act,
            "objects" => [],
            "attributes" => %{
              float_attr => float_value,
              bool_attr => bool_value,
              atom_attr => atom_value,
              term_attr => term_value,
              int_attr => int_value
            }
          }
        ],
        run_id: run_id(),
        time: @fixed_time
      )

    values = hd(doc["events"])["attributes"]

    # Numbers and booleans are JSON-native and survive as themselves.
    assert %{"name" => float_attr, "value" => float_value} in values
    assert %{"name" => bool_attr, "value" => bool_value} in values
    assert %{"name" => int_attr, "value" => int_value} in values

    # An atom is not JSON-native, so it degrades to its own string form --
    # not to a placeholder, and not by being dropped.
    assert %{"name" => atom_attr, "value" => Atom.to_string(atom_value)} in values

    # An arbitrary term degrades far enough to encode while still carrying
    # the term's own content, rather than crashing the writer.
    fallback = Enum.find(values, &(&1["name"] == term_attr))["value"]
    assert is_binary(fallback)
    assert fallback =~ elem(term_value, 0)

    # The whole point of the degradation: the document is encodable.
    assert is_binary(Jason.encode!(doc))

    declared = Enum.find(doc["eventTypes"], &(&1["name"] == act))["attributes"]

    assert %{"name" => float_attr, "type" => "float"} in declared
    assert %{"name" => bool_attr, "type" => "boolean"} in declared
    assert %{"name" => int_attr, "type" => "integer"} in declared
    assert %{"name" => atom_attr, "type" => "string"} in declared
    assert %{"name" => term_attr, "type" => "string"} in declared
  end

  test "every event relates to its objects by qualifier, plus the run object" do
    s = scenario()
    events = document(s)["events"]

    composed = Enum.find(events, &(&1["type"] == s.composed_activity))
    refused = Enum.find(events, &(&1["type"] == s.refused_activity))

    assert %{"objectId" => s.subject, "qualifier" => s.subject_qualifier} in composed[
             "relationships"
           ]

    assert %{"objectId" => s.generator, "qualifier" => s.generator_qualifier} in composed[
             "relationships"
           ]

    # Every event relates to the run, so one qualification run is a single
    # traceable object rather than a pile of unlinked events.
    for e <- [composed, refused] do
      assert %{"objectId" => s.run_id, "qualifier" => @run_qualifier} in e["relationships"]
    end
  end

  test "an event that also lists the run among its own objects relates to it exactly once" do
    s = scenario()

    # `mix ggen_igniter.ocel.seal` builds exactly this shape
    # (`ggen_igniter.ocel.seal.ex:111`): the run object appears both in the
    # event's own objects and in the relationship the exporter appends. The
    # caller cannot know about the appended one, so reconciling them is the
    # exporter's job -- before it did, every sealed log carried the pair
    # twice.
    event = %{
      "activity" => s.composed_activity,
      "objects" => [%{"type" => s.run_type, "id" => s.run_id, "qualifier" => @run_qualifier}]
    }

    doc = Ocel2Export.document([event], run_id: s.run_id, run_type: s.run_type, time: @fixed_time)

    assert hd(doc["events"])["relationships"] == [
             %{"objectId" => s.run_id, "qualifier" => @run_qualifier}
           ]
  end

  test "no event repeats an (objectId, qualifier) pair" do
    s = scenario()

    seal_shaped = %{
      "activity" => activity(),
      "objects" => [%{"type" => s.run_type, "id" => s.run_id, "qualifier" => @run_qualifier}],
      "attributes" => %{}
    }

    doc =
      Ocel2Export.document(s.events ++ [seal_shaped],
        run_id: s.run_id,
        run_type: s.run_type,
        time: @fixed_time
      )

    for e <- doc["events"] do
      pairs = Enum.map(e["relationships"], &{&1["objectId"], &1["qualifier"]})
      assert pairs == Enum.uniq(pairs), "#{e["id"]} repeats a relationship: #{inspect(pairs)}"
    end
  end

  test "an object reference without an explicit qualifier degrades to its own type" do
    [type] = words(1)
    id = Faker.File.file_name(:text)

    doc =
      Ocel2Export.document(
        [%{"activity" => activity(), "objects" => [%{"type" => type, "id" => id}]}],
        run_id: run_id(),
        time: @fixed_time
      )

    assert %{"objectId" => id, "qualifier" => type} in hd(doc["events"])["relationships"]
  end

  test "objects are declared once per referenced id, in deterministic order" do
    s = scenario()
    ids = document(s)["objects"] |> Enum.map(& &1["id"])

    assert ids == Enum.sort(ids), "objects must be deterministically ordered"
    assert ids == Enum.uniq(ids), "each referenced object must be declared once"

    for id <- [s.run_id, s.subject, s.generator, s.broken_generator] do
      assert id in ids
    end
  end

  test "each event carries its own time, strictly increasing and in array order" do
    count = Faker.random_between(5, 12)
    events = for _ <- 1..count, do: %{"activity" => activity(), "objects" => []}

    doc = Ocel2Export.document(events, run_id: run_id(), time: @fixed_time)
    times = Enum.map(doc["events"], & &1["time"])

    assert length(times) == count

    assert length(Enum.uniq(times)) == count,
           "a tied timestamp leaves array position as the only carrier of order, and array " <>
             "position is not part of the OCEL 2.0 contract"

    parsed = Enum.map(times, &iso!/1)

    assert parsed == Enum.sort(parsed, DateTime),
           "timestamp order must agree with the order the events were emitted in"

    for [earlier, later] <- Enum.chunk_every(parsed, 2, 1, :discard) do
      assert DateTime.compare(earlier, later) == :lt
    end

    # Every derived stamp is after the run instant it was derived from, so a
    # consumer can still bound the run by that instant.
    assert Enum.all?(parsed, &(DateTime.compare(&1, iso!(@fixed_time)) == :gt))
  end

  test "an event that carries its own time keeps it byte-for-byte" do
    own =
      Faker.random_between(1, 30)
      |> Faker.DateTime.backward()
      |> DateTime.truncate(:millisecond)
      |> DateTime.to_iso8601()

    doc =
      Ocel2Export.document(
        [%{"activity" => activity(), "objects" => [], "time" => own}],
        run_id: run_id(),
        time: @fixed_time
      )

    assert hd(doc["events"])["time"] == own
  end

  test "a :time that is not parseable ISO8601 is passed through unchanged" do
    junk = Faker.Lorem.sentence()
    count = Faker.random_between(2, 5)
    events = for _ <- 1..count, do: %{"activity" => activity(), "objects" => []}

    doc = Ocel2Export.document(events, run_id: run_id(), time: junk)

    # Degenerate, but visibly so: the caller gets back exactly what it passed
    # rather than an invented instant.
    assert Enum.map(doc["events"], & &1["time"]) == List.duplicate(junk, count)
  end

  test "an explicitly supplied object wins over the bare reference-derived one" do
    s = scenario()
    [attr] = words(1)
    value = Faker.Lorem.word()

    doc =
      Ocel2Export.document(s.events,
        run_id: s.run_id,
        run_type: s.run_type,
        time: @fixed_time,
        objects: [
          %{"id" => s.subject, "type" => s.subject_type, "attributes" => %{attr => value}}
        ]
      )

    declarations = Enum.filter(doc["objects"], &(&1["id"] == s.subject))

    assert [%{"attributes" => attributes}] = declarations

    # The reference-derived declaration carries no attributes at all, so
    # seeing the supplied ones is what proves the precedence held.
    assert attributes == [%{"name" => attr, "value" => value, "time" => @fixed_time}]

    # ...and the declared object type picks the attribute up too.
    declared = Enum.find(doc["objectTypes"], &(&1["name"] == s.subject_type))
    assert %{"name" => attr, "type" => "string"} in declared["attributes"]
  end

  test ":objects declares an object that no event references" do
    s = scenario()
    orphan_id = module_name()
    [orphan_type] = words(1)

    doc =
      Ocel2Export.document(s.events,
        run_id: s.run_id,
        run_type: s.run_type,
        time: @fixed_time,
        objects: [%{"id" => orphan_id, "type" => orphan_type}]
      )

    assert orphan_id in Enum.map(doc["objects"], & &1["id"])
    assert orphan_type in Enum.map(doc["objectTypes"], & &1["name"])

    referenced =
      doc["events"] |> Enum.flat_map(& &1["relationships"]) |> Enum.map(& &1["objectId"])

    refute orphan_id in referenced
  end

  test "the same events serialize to the same bytes, with positional ids" do
    s = scenario()

    assert Jason.encode!(document(s)) == Jason.encode!(document(s))

    # Positional, not random: a run-1/run-2 log diff is only evidence if
    # identical input produces identical output.
    assert document(s)["events"] |> Enum.map(& &1["id"]) == ["ev_0001", "ev_0002"]
  end

  test "write!/3 puts a real, re-readable OCEL document on disk" do
    s = scenario()
    dir = Path.join(System.tmp_dir!(), "ggen_igniter_ocel2_#{System.unique_integer([:positive])}")
    path = Path.join([dir, Faker.Lorem.word(), "run.ocel.json"])

    on_exit(fn -> File.rm_rf!(dir) end)

    written =
      Ocel2Export.write!(path, s.events,
        run_id: s.run_id,
        run_type: s.run_type,
        time: @fixed_time
      )

    assert File.exists?(written)

    decoded = written |> File.read!() |> Jason.decode!()
    assert decoded == document(s) |> Jason.encode!() |> Jason.decode!()
  end

  test "an empty log is still a structurally valid OCEL document" do
    doc = Ocel2Export.document([], run_id: run_id(), time: @fixed_time)

    assert Map.keys(doc) |> Enum.sort() == @required_keys
    assert doc["events"] == []
    assert doc["eventTypes"] == []

    # The run object is declared only because an event relates to it, so an
    # empty log declares no objects rather than a lone orphan run.
    assert doc["objects"] == []
    assert doc["objectTypes"] == []
  end
end
