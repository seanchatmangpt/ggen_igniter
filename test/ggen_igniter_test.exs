defmodule GgenIgniterTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query, Render}

  @fixtures Path.join(__DIR__, "fixtures")

  test "loads the real ash-extension-core-pack AuditTrail ontology and reproduces its row shapes" do
    graph = Ontology.load!(Path.join(@fixtures, "audit_trail_ontology.ttl"))
    assert %RDF.Graph{} = graph

    spec = Query.run(graph, File.read!(Path.join(@fixtures, "spec.rq")))
    assert [%{"package_name" => "audit_trail", "module_name" => "AuditTrail.Resource"}] = spec

    sections = Query.run(graph, File.read!(Path.join(@fixtures, "sections.rq")))
    assert [%{"section_name" => "audit"}] = sections

    entities = Query.run(graph, File.read!(Path.join(@fixtures, "entities.rq")))
    entity_names = entities |> Enum.map(& &1["entity_name"]) |> Enum.sort()
    assert entity_names == ["event", "projection"]

    fields = Query.run(graph, File.read!(Path.join(@fixtures, "fields.rq")))
    assert length(fields) == 3
  end

  test "renders a real, syntactically-valid Elixir extension module via EEx, matching the Rust-ggen structural shape" do
    graph = Ontology.load!(Path.join(@fixtures, "audit_trail_ontology.ttl"))

    [spec_row] = Query.run(graph, File.read!(Path.join(@fixtures, "spec.rq")))
    sections = Query.run(graph, File.read!(Path.join(@fixtures, "sections.rq")))
    entities = Query.run(graph, File.read!(Path.join(@fixtures, "entities.rq")))
    fields = Query.run(graph, File.read!(Path.join(@fixtures, "fields.rq")))

    template = File.read!(Path.join(@fixtures, "extension.ex.eex"))

    rendered =
      Render.render(template,
        module_name: spec_row["module_name"],
        package_name: spec_row["package_name"],
        sections: sections,
        entities: entities,
        fields: fields
      )

    # Real syntax validity -- not a mocked/asserted-only check.
    quoted = Code.string_to_quoted!(rendered)
    assert {:defmodule, _, _} = quoted

    # Structural equivalence against the actual Rust-ggen-generated resource.ex for the
    # SAME AuditTrailSpec (from this session's earlier ash-extension-core-pack work) --
    # same module name, same two entity structs, same section wiring. Not byte-identical
    # (different formatting/comment style is expected and fine).
    assert rendered =~ "defmodule AuditTrail.Resource do"
    assert rendered =~ "defmodule AuditTrail.Dsl.Event do"
    assert rendered =~ "defmodule AuditTrail.Dsl.Projection do"
    assert rendered =~ "name: :event,"
    assert rendered =~ "name: :projection,"
    assert rendered =~ "sections: [@audit],"
    assert rendered =~ "transformers: [AuditTrail.Resource.Persist],"
    assert rendered =~ "verifiers: [AuditTrail.Resource.Verify]"
  end
end
