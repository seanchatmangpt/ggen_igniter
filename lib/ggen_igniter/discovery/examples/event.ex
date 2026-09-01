defmodule GgenIgniter.Discovery.Examples.Event do
  @moduledoc """
  Minimal real canonical event struct used as the dogfood target for
  `incremental-discovery-pack` and `sensor-sink-pack` -- mirrors the shape of
  ex4pm's canonical `Ex4pm.Event` (`activity`, `object_ids`, `timestamp`,
  `id`, `attributes`) closely enough that the ported discovery/sink logic
  needs no struct-shape translation, without this repo depending on ex4pm
  itself. A real consumer (e.g. beam4pm) points `dfg:eventModule`/
  `ss:eventModule` at its own canonical event struct instead.
  """

  @enforce_keys [:activity]
  defstruct id: nil,
            activity: nil,
            timestamp: nil,
            object_ids: [],
            relationships: [],
            attributes: %{}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          activity: String.t(),
          timestamp: DateTime.t() | non_neg_integer() | nil,
          object_ids: [String.t()],
          relationships: list(),
          attributes: map()
        }
end
