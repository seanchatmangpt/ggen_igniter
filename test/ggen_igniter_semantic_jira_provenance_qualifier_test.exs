defmodule GgenIgniter.SemanticJiraProvenanceQualifierTest do
  @moduledoc """
  QUALIFIER falsifiers for `GgenIgniter.SemanticJira.Provenance` at c402a46.
  Both tests are EXPECTED TO FAIL against that head: each pins a defect the
  builder's own suite does not reach. They stay red until the defect is fixed.

  Chicago-style like the builder's suite: real `TransitionLog` on disk, the real
  PROV-O template, real RDF.ex parsing, the real oxigraph NIF, state-based
  assertions on returned event maps and standing maps. No test doubles.

  1. `started_at` round trip. `to_turtle/1` accepts any ISO-8601 datetime string
     as `prov:startedAtTime ... ^^xsd:dateTime`, but oxigraph returns the
     canonical lexical form on replay (`.000Z` -> `Z`, `.500Z` -> `.5Z`,
     `+00:00` -> `Z`), so an honest, untampered export is refused with
     `:event_digest_mismatch`. `DateTime.to_iso8601/1` output with trailing
     zero microseconds is such a value.
  2. `sj:seq` datatype. `replay/1` accepts a plain-string `sj:seq` (it parses
     the lexical form), but `standing_projection/1`'s SPARQL then compares the
     sequence numbers as strings ("10" < "9"), so a graph that passed
     verification reports an older standing than `SemanticJira.project/2`.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Provenance, TransitionLog}

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_prov_qual_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "started_at round trip (falsifier)" do
    for {label, started_at} <- [
          {"trailing-zero fraction", "2026-09-21T10:11:12.000Z"},
          {"millisecond fraction with trailing zeros", "2026-09-21T10:11:12.500Z"},
          {"microsecond fraction with trailing zero", "2026-09-21T10:11:12.123450Z"},
          {"zero numeric offset", "2026-09-21T10:11:12+00:00"}
        ] do
      test "an honest export carrying #{label} replays equal to the log", %{dir: dir} do
        started_at = unquote(started_at)

        assert {:ok, _, :appended} =
                 TransitionLog.append(dir, %{
                   "identity" => "X",
                   "to" => "ALIVE",
                   "started_at" => started_at
                 })

        events = TransitionLog.read(dir)
        assert [%{"started_at" => ^started_at}] = events
        assert {:ok, ttl} = TransitionLog.export_turtle(dir)

        assert Provenance.replay(ttl) == {:ok, events}
      end
    end
  end

  describe "sj:seq datatype (falsifier)" do
    test "a graph whose sj:seq lost its xsd:integer type is refused or projects identically",
         %{dir: dir} do
      for n <- 1..11 do
        assert {:ok, _, :appended} =
                 TransitionLog.append(dir, %{
                   "kind" => "standing_transition_event",
                   "identity" => "ROOT",
                   "from" => "S#{n - 1}",
                   "to" => "S#{n}"
                 })
      end

      events = TransitionLog.read(dir)
      assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..11)
      assert {:ok, ttl} = TransitionLog.export_turtle(dir)

      {_projected, logged} = SemanticJira.project([%{"identity" => "ROOT"}], events)
      assert %{"ROOT" => %{"standing" => "S11"}} = logged
      assert Provenance.standing_projection(ttl) == {:ok, logged}

      retyped = Regex.replace(~r/sj:seq "(\d+)"\^\^xsd:integer/, ttl, ~S(sj:seq "\1"))
      refute retyped == ttl

      case Provenance.standing_projection(retyped) do
        {:error, {:refused, _reason}} -> :ok
        {:ok, projection} -> assert projection == logged
      end
    end
  end
end
