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

    # Real compile, not just parse -- catches the guaranteed-crash regression where
    # `transformers:`/`verifiers:` name companion modules (`<module>.Persist`,
    # `<module>.Verify`) that no template ever emits. Spark.Dsl.Extension.run_transformers/4
    # calls `transformer.transform(dsl)` on every listed transformer the first time ANY
    # module `use`s the extension, so an undefined module there raises `UndefinedFunctionError`
    # at that point, not at this compile. We therefore also `use` the rendered extension in a
    # throwaway module here, which is the real trigger for both the transformer and verifier
    # call sites.
    compiled_modules = Code.compile_string(rendered) |> Enum.map(&elem(&1, 0))
    assert AuditTrail.Resource in compiled_modules
    assert Code.ensure_loaded?(AuditTrail.Resource.Persist)
    assert Code.ensure_loaded?(AuditTrail.Resource.Verify)
    assert function_exported?(AuditTrail.Resource.Persist, :transform, 1)
    assert function_exported?(AuditTrail.Resource.Verify, :verify, 1)

    consumer_source = """
    defmodule GgenIgniterTest.AuditTrailConsumer do
      use Spark.Dsl,
        default_extensions: [extensions: [AuditTrail.Resource]]
    end
    """

    # This is the real crash site: compiling a module that `use`s the manufactured
    # extension runs Spark's transformer pipeline (transformers, then verifiers) against
    # it. Before the fix, this raised UndefinedFunctionError for `.Persist`/`.Verify`.
    consumer_modules = Code.compile_string(consumer_source) |> Enum.map(&elem(&1, 0))
    assert GgenIgniterTest.AuditTrailConsumer in consumer_modules
  end
end
