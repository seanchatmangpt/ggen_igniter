defmodule GgenIgniter.SemanticA2AExternalDoOntologyFalsifierTest do
  @moduledoc """
  QUALIFIER ontology falsifier (errc/external-do-capability). Real ontology,
  real SPARQL engine, no test doubles.

  Q3: ash_a2a keys a skill's capability id and consequence on the Ash ACTION
  (`SemanticJira.Work.Task.update`), not on the ontology's skill name. The
  ontology maps the exposed `external_do` court AND the REFUSED
  `push_candidate` / `publish_candidate` (consequence `change`) to the same Ash
  action `update`. Exposing `update` therefore exposes the one capability id
  that Push and Publish would also need, under a different consequence class,
  and no SHACL shape or gate notices. A REFUSED action must not share an Ash
  action with an exposed skill.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query}

  @ontology "priv/ggen/semantic-jira-pack/ontology.ttl"

  @query """
  PREFIX sj: <https://ggen-igniter.dev/ontology/semantic-jira#>
  PREFIX a2a: <https://ggen-igniter.dev/ontology/a2a#>
  SELECT DISTINCT ?refused_skill ?exposed_skill ?ash_action ?refused_consequence ?exposed_consequence WHERE {
    ?refused a sj:Action ;
             a2a:exposed false ;
             a2a:skillName ?refused_skill ;
             a2a:ashAction ?ash_action ;
             a2a:consequence ?refused_consequence .
    ?exposed a sj:Action ;
             a2a:exposed true ;
             a2a:skillName ?exposed_skill ;
             a2a:ashAction ?ash_action ;
             a2a:consequence ?exposed_consequence .
  }
  ORDER BY ?refused_skill
  """

  test "Q3: no REFUSED action shares an Ash action with an exposed skill" do
    rows = Query.run(Ontology.load!(@ontology), @query)

    assert rows == [],
           "REFUSED action(s) share an Ash action (hence capability id) with an exposed skill: " <>
             inspect(rows)
  end
end
