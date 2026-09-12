defmodule GgenIgniter.EDS.WorkedExampleTest do
  @moduledoc """
  A real Executable Research Claim, per Executable Design Science S16
  ("PPCX as a Flagship EDS Experiment" -- this is the same shape, one
  concrete claim rather than the full PPCX closure loop), drawn directly
  from real work landed in `~/ggen-marketplace/packs/ex-noun-verb-cli-pack`
  this session: ontology-driven generation of `MarketplaceCli.Registry`.

  H: rendering `templates/registry.ex.tmpl` against
  `instances/marketplace-cli.ttl` via `ggen_igniter`'s real
  oxigraph+TeraWasm pipeline produces (a) syntactically valid Elixir naming
  the real noun/verb/module/function facts declared in the ttl, and (b) is
  genuinely ontology-driven, not hardcoded: mutating one fact in the ttl
  changes the corresponding fact in the rendered output while leaving
  everything else unchanged.

  This uses `GgenIgniter`'s real modules directly (Chicago style: real
  oxigraph NIF, real WASM Tera renderer, real files on disk) -- no mock of
  the query engine or the renderer. The one legitimate skip: this test
  requires the real `~/ggen-marketplace` checkout (a sibling repo, not a
  dependency of this one) to exist on disk; it is not vendored here and has
  no fixed relative path, so it degrades to a named, visible skip rather
  than a mocked substitute when absent, following the same pattern
  documented in `packages/marketplace-cli/mix.exs`'s own env-var-path
  convention.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.EDS.{Claim, Falsifier}

  @marketplace_path System.get_env("GGEN_MARKETPLACE_PATH", Path.expand("~/ggen-marketplace"))
  @pack_dir Path.join(@marketplace_path, "packs/ex-noun-verb-cli-pack")
  @instance_path Path.join(@pack_dir, "instances/marketplace-cli.ttl")
  @template_path Path.join(@pack_dir, "templates/registry.ex.tmpl")

  @moduletag :eds_worked_example

  setup do
    unless File.exists?(@instance_path) and File.exists?(@template_path) do
      raise "expected #{@instance_path} and #{@template_path} to exist"
    end

    :ok
  end

  # ---------------------------------------------------------------------
  # The artifact: a real, minimal render of one template against one ttl,
  # using ggen_igniter's own real ontology/query/render modules directly
  # (the same machinery `verify/generate.exs` uses, inlined here so this
  # test needs no subprocess).
  # ---------------------------------------------------------------------

  defp render_registry!(ttl_path) do
    graph = GgenIgniter.Ontology.load!(ttl_path)
    raw = File.read!(@template_path)
    {frontmatter, :file, body} = GgenIgniter.Frontmatter.split_template(raw)

    project = GgenIgniter.Query.Oxigraph.run(graph, frontmatter.sparql["project"])
    verb_rows = GgenIgniter.Query.Oxigraph.run(graph, frontmatter.sparql["verbs"])
    args_rows = GgenIgniter.Query.Oxigraph.run(graph, frontmatter.sparql["args"])

    enriched_verbs =
      Enum.map(verb_rows, fn v ->
        args =
          args_rows
          |> Enum.filter(&(&1["noun"] == v["noun"] and &1["verb"] == v["verb"]))
          |> Enum.sort_by(&String.to_integer(&1["arg_order"]))

        schema_str = Enum.map_join(args, ", ", &"#{&1["arg_name"]}: :#{&1["arg_type"]}")

        required_str =
          args
          |> Enum.filter(&(&1["arg_required"] == "true"))
          |> Enum.map_join(", ", &":#{&1["arg_name"]}")

        Map.merge(v, %{"schema_str" => schema_str, "required_str" => required_str})
      end)

    context = %{"project" => project, "verbs" => enriched_verbs}
    {:ok, rendered} = GgenIgniter.Render.TeraWasm.render(body, context)
    %{rendered: rendered, verb_count: length(verb_rows), project: List.first(project)}
  end

  # ---------------------------------------------------------------------
  # The falsifiers: contradictory evidence this artifact CAN produce, per
  # EDS S9 -- not checks wired to always pass.
  # ---------------------------------------------------------------------

  defp falsifiers do
    [
      Falsifier.new(
        "rendered output is valid Elixir",
        "the rendered registry.ex body fails Code.string_to_quoted!/1",
        fn %{rendered: rendered} ->
          try do
            Code.string_to_quoted!(rendered)
            {:survived, "parses"}
          rescue
            e -> {:falsified, Exception.message(e)}
          end
        end
      ),
      Falsifier.new(
        "real verb count reflected",
        "the rendered output does not mention both real marketplace-cli verbs (validate, catalog)",
        fn %{rendered: rendered} ->
          if String.contains?(rendered, ~s(verb: "validate")) and
               String.contains?(rendered, ~s(verb: "catalog")) do
            {:survived, "both verbs present"}
          else
            {:falsified, "missing an expected verb entry"}
          end
        end
      ),
      Falsifier.new(
        "handler module is the real Inspector, not hardcoded",
        "the rendered output names a handler module other than MarketplaceCli.Inspector",
        fn %{rendered: rendered} ->
          if String.contains?(rendered, "module: MarketplaceCli.Inspector") do
            {:survived, "real handler module present"}
          else
            {:falsified, "expected handler module not found"}
          end
        end
      )
    ]
  end

  defp verifier(_evidence, verdicts) do
    if Falsifier.all_survived?(verdicts) do
      {:verified, %{validators: ["Code.string_to_quoted!/1", "string containment on real facts"]}}
    else
      {:falsified,
       %{validators: ["Code.string_to_quoted!/1", "string containment on real facts"]}}
    end
  end

  test "ERC: registry.ex generation is real, valid, and genuinely ontology-driven" do
    claim =
      Claim.new(%{
        hypothesis:
          "rendering templates/registry.ex.tmpl against instances/marketplace-cli.ttl produces valid, " <>
            "genuinely ontology-derived Elixir naming the real marketplace-cli verbs",
        artifact: @instance_path,
        falsifiers: falsifiers(),
        protocol:
          "GgenIgniter.Ontology.load!/1 -> Query.Oxigraph.run/2 -> Render.TeraWasm.render/2 -> Code.string_to_quoted!/1",
        identity: %{
          source: @instance_path,
          environment: %{oxigraph_nif: true, tera_wasm: true},
          inputs: %{template: @template_path}
        },
        verifier: &verifier/2
      })

    claim = Claim.execute(claim, &render_registry!/1)
    claim = Claim.verify(claim)

    assert claim.state == :verified
    assert claim.receipt.fingerprint =~ ~r/^[0-9a-f]{64}$/
    assert Falsifier.all_survived?(claim.receipt.falsifier_verdicts)
    assert claim.evidence.verb_count == 2
  end

  test "falsifier ADVERSARIAL CHECK: mutating the ttl genuinely changes the rendered output (not hardcoded)" do
    original = render_registry!(@instance_path)

    # Real mutation: write a scratch copy of the instance with one fact
    # changed (handlerFunction "validate" -> "check"), mirroring the
    # adversarial falsifier already run and reported during this session's
    # ex-noun-verb-cli-pack generator build. If the template output does
    # not change accordingly, generation is not actually ontology-driven.
    mutated_ttl =
      String.replace(
        File.read!(@instance_path),
        ~s(nvc:handlerFunction "validate"),
        ~s(nvc:handlerFunction "check")
      )

    refute mutated_ttl == File.read!(@instance_path),
           "the mutation string was not found in the real instance ttl -- update this test's mutation to match the current file"

    scratch_path =
      Path.join(
        System.tmp_dir!(),
        "eds_mutated_marketplace_cli_#{System.unique_integer([:positive])}.ttl"
      )

    File.write!(scratch_path, mutated_ttl)

    mutated = render_registry!(scratch_path)
    File.rm!(scratch_path)

    falsifier =
      Falsifier.new(
        "mutation changes generated output",
        "mutating handlerFunction in the ttl does not change the corresponding rendered function name",
        fn {orig, mut} ->
          function_changed? =
            String.contains?(mut, "function: :check") and
              not String.contains?(mut, "function: :validate")

          catalog_unchanged? =
            String.contains?(orig, "function: :catalog") and
              String.contains?(mut, "function: :catalog")

          if function_changed? and catalog_unchanged? do
            {:survived, "mutated fact changed in output; unrelated fact (catalog) unchanged"}
          else
            {:falsified, "mutation did not propagate correctly to rendered output"}
          end
        end
      )

    assert {:survived, _} = Falsifier.run(falsifier, {original.rendered, mutated.rendered})
  end
end
