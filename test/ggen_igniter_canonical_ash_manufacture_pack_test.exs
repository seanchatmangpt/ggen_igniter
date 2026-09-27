defmodule GgenIgniter.CanonicalAshManufacturePackTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Pack}

  @pack Path.expand("../priv/ggen/ash-manufacture-pack", __DIR__)

  @expected_queries ~w(
    project
    domains
    resources
    default_actions
    attributes
    relationships
    extensions
    support_modules
    enum_values
    capabilities
    refusals
    citations
    dependency_pins
  )

  test "the shipped Ash manufacture profile is Core-admitted and has one deterministic discovery surface" do
    graph = Ontology.load!(Path.join(@pack, "ontology.ttl"))

    assert :ok = Pack.admit_pack_manifest(@pack, graph)
    assert @pack == Pack.resolve_dir!(%{pack_dir: @pack})

    assert @expected_queries ==
             @pack
             |> Pack.discover_queries()
             |> Enum.map(&elem(&1, 0))

    assert {:ok, template} = Pack.discover_template(@pack)
    assert Path.basename(template) == "manufacture.ex.eex"
  end

  test "the canonical profile composes upstream Ash generators instead of rendering Ash resources" do
    template = File.read!(Path.join(@pack, "templates/manufacture.ex.eex"))

    assert template =~ "Igniter.compose_task"
    assert template =~ ~s(task: "ash.gen.resource")
    assert template =~ ~s(task: "ash.gen.domain")
    assert template =~ "capability_refused"

    refute template =~ "use Ash.Resource"
    refute template =~ "use Ash.Domain"
  end

  test "the shipped gates preserve the qualified fixture projections byte-for-byte" do
    fixture = Path.expand("fixtures/ash_manufacture_pack", __DIR__)

    for {_name, canonical_path} <- Pack.discover_queries(@pack) do
      basename = Path.basename(canonical_path)
      fixture_path = Path.join([fixture, "gates", basename])

      assert File.read!(canonical_path) == File.read!(fixture_path),
             "canonical gate #{basename} drifted from the qualified fixture"
    end
  end
end
