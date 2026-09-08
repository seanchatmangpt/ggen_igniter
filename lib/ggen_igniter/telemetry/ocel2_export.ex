defmodule GgenIgniter.Telemetry.Ocel2Export do
  @moduledoc """
  Serializes ggen_igniter's in-memory OCEL-shaped events into a real
  **OCEL 2.0 JSON** document that `beam4pm`'s importer accepts as-is.

  ## Why this module exists

  `GgenIgniter.Telemetry.OcelEmitter` produces 5-key event maps
  (`"id"`/`"activity"`/`"time"`/`"objects"`/`"attributes"`) whose object
  references are bare `%{"type" => _, "id" => _}` pairs with no qualifier
  (`ocel_emitter.ex:203-233`). That is a useful internal trace, but it is
  **not** an importable OCEL 2.0 log: `BeamPM.Rust4PM.import_ocel_json/2`
  (`beam4pm/lib/beam4pm_rust4pm.ex:427-435`) is backed by `process_mining`
  0.6.2, whose serde document requires four top-level keys --
  `eventTypes`, `objectTypes`, `events`, `objects` -- with per-event
  `relationships: [%{"objectId" => _, "qualifier" => _}]`. Feeding it a
  document without `eventTypes` fails with a real, typed refusal
  (`missing field 'eventTypes'`), which `beam4pm`'s own qualification
  fixture documents.

  This module closes exactly that gap, and nothing more:

    * `eventTypes` is **synthesized from the distinct `"activity"` values**
      actually present in the log -- never from a hardcoded list, so an
      activity that was never emitted never appears as a declared type.
    * `objectTypes` is synthesized the same way from the distinct object
      `"type"` values.
    * A missing `"qualifier"` on an object reference degrades to the
      object's own type rather than being invented, and that degradation is
      visible in the output rather than silent.

  ## What it deliberately does not do

  It does not fabricate attribute *type declarations* it cannot observe:
  a declared attribute's `"type"` is derived from the real runtime value
  (`is_integer/1` -> `"integer"`, and so on), and any attribute never seen
  with a value is not declared. It performs no aggregation, no conformance
  checking and no statistics -- two runs are not a time series, and this
  module will not pretend otherwise.

  ## Determinism

  Event ids are assigned positionally (`ev_0001`, ...) rather than randomly,
  and every collection is sorted, so the same event list always serializes
  to the same bytes. That is what makes a run-1/run-2 log diff meaningful
  evidence instead of noise.

  Event *times* are positional in the same sense: an event with no `"time"`
  of its own is stamped with the run instant offset by its 1-based index in
  milliseconds. Order therefore lives in the timestamps, not only in array
  position -- so a consumer that sorts by `time` recovers the order this
  module actually emitted -- while the document stays a pure function of
  (run instant, event list) and so stays byte-reproducible.
  """

  @typedoc """
  One input event. `"activity"` and `"objects"` are required; `"time"` and
  `"attributes"` are optional and default to the run timestamp / `%{}`.
  """
  @type in_event :: %{required(String.t()) => term()}

  @doc """
  Builds the OCEL 2.0 document (a plain map, ready for `Jason.encode!/1`).

  ## Options

    * `:run_id` - stable identity for the run object every event is related
      to. Required in spirit; defaults to `"run"`.
    * `:run_type` - the run object's OCEL object type. Defaults to `"run"`.
    * `:time` - ISO8601 string naming the run instant. An event that carries
      no `"time"` of its own is stamped with that instant offset by its own
      1-based position in milliseconds, so event order survives in the
      timestamps rather than only in array position. Defaults to
      `DateTime.utc_now/0`; pass it explicitly to make a document
      byte-reproducible. A value this module cannot parse as ISO8601 is
      passed through unchanged to every such event, which is the pre-offset
      behaviour and is visibly degenerate rather than silently wrong.
    * `:objects` - extra object maps (`%{"id" => _, "type" => _, "attributes" => %{}}`)
      to declare beyond those referenced by events.
  """
  @spec document([in_event()], keyword()) :: map()
  def document(events, opts \\ []) when is_list(events) do
    run_id = Keyword.get(opts, :run_id, "run")
    run_type = Keyword.get(opts, :run_type, "run")
    now = Keyword.get_lazy(opts, :time, fn -> DateTime.utc_now() |> DateTime.to_iso8601() end)
    clock = clock(now)

    normalized =
      Enum.with_index(events, 1) |> Enum.map(&normalize_event(&1, clock, run_id, run_type))

    extra_objects =
      opts
      |> Keyword.get(:objects, [])
      |> Enum.map(fn o ->
        %{
          "id" => Map.fetch!(o, "id"),
          "type" => Map.fetch!(o, "type"),
          "attributes" => attribute_values(Map.get(o, "attributes", %{}), now)
        }
      end)

    referenced =
      normalized
      |> Enum.flat_map(fn e -> e["relationships"] end)
      |> Enum.map(fn r -> {r["objectId"], r["__type__"]} end)
      |> Enum.uniq()
      |> Enum.map(fn {id, type} -> %{"id" => id, "type" => type, "attributes" => []} end)

    objects =
      (extra_objects ++ referenced)
      # An explicitly supplied object (with attributes) wins over the bare
      # reference-derived one for the same id.
      |> Enum.reduce(%{}, fn o, acc -> Map.put_new(acc, o["id"], o) end)
      |> Map.values()
      |> Enum.sort_by(& &1["id"])
      |> Enum.map(&Map.put(&1, "relationships", []))

    %{
      "eventTypes" => event_types(normalized),
      "objectTypes" => object_types(objects),
      "events" =>
        Enum.map(normalized, &Map.drop(&1, ["__attrmap__"]))
        |> Enum.map(fn e ->
          Map.update!(e, "relationships", fn rels ->
            Enum.map(rels, &Map.drop(&1, ["__type__"]))
          end)
        end),
      "objects" => objects
    }
  end

  @doc """
  Writes `document/2` to `path` as pretty JSON, creating parent directories.

  Returns the absolute path actually written.
  """
  @spec write!(Path.t(), [in_event()], keyword()) :: Path.t()
  def write!(path, events, opts \\ []) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(document(events, opts), pretty: true))
    Path.expand(path)
  end

  # -- internals ------------------------------------------------------------

  defp normalize_event({event, index}, clock, run_id, run_type) do
    activity = Map.fetch!(event, "activity")
    attrs = Map.get(event, "attributes", %{})

    rels =
      event
      |> Map.get("objects", [])
      |> Enum.map(fn o ->
        %{
          "objectId" => Map.fetch!(o, "id"),
          # A reference without an explicit qualifier degrades to its own
          # object type rather than to an invented relation name.
          "qualifier" => Map.get(o, "qualifier") || Map.fetch!(o, "type"),
          "__type__" => Map.fetch!(o, "type")
        }
      end)

    run_rel = %{"objectId" => run_id, "qualifier" => "run", "__type__" => run_type}

    %{
      "id" => Map.get(event, "id") || "ev_" <> String.pad_leading(to_string(index), 4, "0"),
      "type" => activity,
      "time" => Map.get(event, "time") || event_time(clock, index),
      "attributes" => attribute_values(attrs, nil),
      # The run relationship is appended here and ONLY here. A caller that
      # also lists the run among its own objects (`mix
      # ggen_igniter.ocel.seal` does, at ggen_igniter.ocel.seal.ex:111)
      # cannot know that, so reconciling the two is this function's job
      # rather than every caller's: without it the sealed event carried the
      # same (objectId, qualifier) pair twice. First occurrence wins, so an
      # explicitly supplied reference keeps its own declared object type.
      "relationships" => Enum.uniq_by(rels ++ [run_rel], &{&1["objectId"], &1["qualifier"]}),
      "__attrmap__" => attrs
    }
  end

  # A single run instant stamped on every event would leave array position as
  # the only carrier of event order, and array position is not part of the
  # OCEL 2.0 contract -- a consumer that sorts by `time` would get an order
  # nobody chose. Each event therefore gets the run instant plus its own
  # 1-based index in milliseconds: still a pure function of (run instant,
  # position), so the document stays byte-reproducible, but strictly
  # increasing and in agreement with array order.
  defp clock(now) when is_binary(now) do
    case DateTime.from_iso8601(now) do
      # Precision is pinned rather than inherited so the rendered offsets are
      # identical whether the caller passed second- or microsecond-resolution
      # input; millisecond resolution is what the +index offset needs to show.
      {:ok, dt, _utc_offset} -> {:offset, %{dt | microsecond: {elem(dt.microsecond, 0), 3}}}
      {:error, _reason} -> {:flat, now}
    end
  end

  defp clock(now), do: {:flat, now}

  defp event_time({:offset, base}, index),
    do: base |> DateTime.add(index, :millisecond) |> DateTime.to_iso8601()

  defp event_time({:flat, now}, _index), do: now

  # OCEL event attributes are {name, value}; object attributes additionally
  # carry a {time}, which is why the timestamp is an argument rather than
  # assumed.
  defp attribute_values(attrs, nil) do
    attrs
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> %{"name" => to_string(k), "value" => encodable(v)} end)
  end

  defp attribute_values(attrs, time) do
    attrs
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} ->
      %{"name" => to_string(k), "value" => encodable(v), "time" => time}
    end)
  end

  defp event_types(normalized) do
    normalized
    |> Enum.group_by(& &1["type"])
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, evs} ->
      %{"name" => name, "attributes" => declared_attributes(Enum.map(evs, & &1["__attrmap__"]))}
    end)
  end

  defp object_types(objects) do
    objects
    |> Enum.group_by(& &1["type"])
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, objs} ->
      declared =
        objs
        |> Enum.flat_map(& &1["attributes"])
        |> Enum.map(fn a -> %{"name" => a["name"], "type" => json_type(a["value"])} end)
        |> Enum.uniq_by(& &1["name"])
        |> Enum.sort_by(& &1["name"])

      %{"name" => name, "attributes" => declared}
    end)
  end

  # An attribute is declared only if it was actually observed carrying a
  # value somewhere in the log -- never predeclared from a schema guess.
  defp declared_attributes(attrmaps) do
    attrmaps
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.map(fn {k, v} -> %{"name" => to_string(k), "type" => json_type(encodable(v))} end)
    |> Enum.uniq_by(& &1["name"])
    |> Enum.sort_by(& &1["name"])
  end

  defp json_type(v) when is_integer(v), do: "integer"
  defp json_type(v) when is_float(v), do: "float"
  defp json_type(v) when is_boolean(v), do: "boolean"
  defp json_type(_), do: "string"

  defp encodable(v) when is_binary(v) or is_number(v) or is_boolean(v), do: v
  defp encodable(v) when is_atom(v), do: to_string(v)
  defp encodable(v), do: inspect(v)
end
