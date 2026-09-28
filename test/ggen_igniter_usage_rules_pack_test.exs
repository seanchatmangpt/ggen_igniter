defmodule GgenIgniter.UsageRulesPackTest do
  @moduledoc """
  Chicago-style: the real `priv/ggen/usage-rules-pack` ontology loaded by the
  real `GgenIgniter.Ontology`, its real gate queries run by the real
  `GgenIgniter.Query.Oxigraph` engine, bindings built by the real
  `Mix.Tasks.GgenIgniter.Sync.build_bindings/1`, the real template rendered by
  `GgenIgniter.Render` into a scratch file, and every documented flag
  cross-checked against the REAL `info/2` schema of the named
  `Mix.Tasks.GgenIgniter.*` module. No doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Query.Oxigraph
  alias Mix.Tasks.GgenIgniter.Sync

  @pack Path.expand("../priv/ggen/usage-rules-pack", __DIR__)

  defp graph, do: GgenIgniter.Ontology.load!(Path.join(@pack, "ontology.ttl"))

  defp bindings(graph) do
    @pack
    |> GgenIgniter.Pack.discover_queries()
    |> Enum.map(fn {name, path} -> {name, Oxigraph.run(graph, File.read!(path))} end)
    |> Sync.build_bindings()
  end

  defp render(graph) do
    ["", _fm, body] =
      [@pack, "templates", "usage-rules.md.eex"]
      |> Path.join()
      |> File.read!()
      |> String.split("---\n", parts: 3)

    GgenIgniter.Render.render(body, bindings(graph))
  end

  defp task_module(name) do
    mod =
      Module.concat(["Mix", "Tasks" | name |> String.split(".") |> Enum.map(&Macro.camelize/1)])

    Code.ensure_loaded!(mod)
    mod
  end

  test "rendered rules land in a scratch file with the Ash-style heading" do
    scratch = Path.join(System.tmp_dir!(), "usage_rules_#{System.unique_integer([:positive])}.md")
    on_exit(fn -> File.rm(scratch) end)
    File.write!(scratch, render(graph()))
    out = File.read!(scratch)

    assert out =~ "# Rules for working with ggen_igniter"
    assert out =~ "### `mix ggen_igniter.sync`"
    assert out =~ "## Invariants"
    assert out =~ "GENERATED from priv/ggen/usage-rules-pack/ontology.ttl"
  end

  test "rendering is deterministic" do
    assert render(graph()) == render(graph())
  end

  test "every documented task module exists and every documented flag is in its info/2 schema" do
    rows = Oxigraph.run(graph(), File.read!(Path.join(@pack, "gates/030_flags.rq")))
    assert length(rows) > 20

    for %{"task" => task, "name" => "--" <> flag} <- rows do
      schema = task_module(task).info([], nil).schema
      key = flag |> String.replace("-", "_") |> String.to_atom()

      assert Keyword.has_key?(schema, key),
             "#{task}: documented --#{flag} absent from info/2 schema"
    end
  end

  test "every documented task appears in the render with its flags" do
    out = render(graph())
    rows = Oxigraph.run(graph(), File.read!(Path.join(@pack, "gates/030_flags.rq")))
    for %{"name" => name} <- rows, do: assert(out =~ "`#{name}`")
  end

  test "falsifier: a flag absent from the schema is detected by the same check" do
    bogus =
      RDF.Graph.add(
        graph(),
        RDF.Description.new(RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#bogus"),
          init: [
            {RDF.type(), RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#Flag")},
            {RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#task"), "ggen_igniter.plan"},
            {RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#name"), "--no-such-flag"},
            {RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#type"), "string"},
            {RDF.iri("https://ggen-igniter.dev/ontology/usage-rules#summary"), "x"}
          ]
        )
      )

    schema = task_module("ggen_igniter.plan").info([], nil).schema
    rows = Oxigraph.run(bogus, File.read!(Path.join(@pack, "gates/030_flags.rq")))

    assert Enum.any?(rows, fn %{"name" => "--" <> f} ->
             not Keyword.has_key?(schema, f |> String.replace("-", "_") |> String.to_atom())
           end)
  end
end
