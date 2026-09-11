defmodule GgenIgniter.Fixtures.AshNotifierLoad2.RulesInfo do
  @moduledoc """
  Second, independent companion "Info" module for
  `test/ggen_igniter_ash_notifier_load2_pack_test.exs` -- a deliberately
  DIFFERENT DSL vocabulary from `AshEx4pmInfo` (rules/trigger/watched_paths/
  path instead of activities/on/object_relationships/relationship), proving
  `ash-notifier-load2-pack`'s ontology+query+template generalizes across
  subjects rather than being hardcoded to `ash_ex4pm`'s predicate names.
  This is this repo's honest, in-repo substitute for a second real
  EXTERNAL Spark-DSL extension example -- see
  `docs/integrations/ash/notifier-load2.md` for the full disclosure of why
  an external second example was not located this pass.

  One `:update` rule loading `:assignee` and `:status`; `:create` is
  deliberately left undeclared to exercise the `nil -> []` branch.
  """

  defmodule Rule do
    @moduledoc false
    defstruct [:trigger, :watched_paths]
  end

  defmodule WatchedPath do
    @moduledoc false
    defstruct [:path]
  end

  def rules(_resource) do
    [
      %Rule{
        trigger: :update,
        watched_paths: [
          %WatchedPath{path: :assignee},
          %WatchedPath{path: :status}
        ]
      }
    ]
  end
end
