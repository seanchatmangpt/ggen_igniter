defmodule GgenIgniter.ChicagoFaultInjectionPackTest do
  @moduledoc """
  Chicago-style test over the real `chicago-fault-injection-pack`
  (`priv/ggen/chicago-fault-injection-pack/`): loads the pack's real
  `ontology.ttl` into a real `RDF.Graph`, runs its real gate query against it,
  and renders its real EEx template with the real single-row bindings --
  exactly the `Ontology.load!/1 -> Query.run/2 -> Render.render/2` pipeline
  `mix ggen_igniter.sync` itself wires (see `lib/mix/tasks/ggen_igniter.sync.ex`
  moduledoc). No mocks: real RDF parsing, real SPARQL execution, real EEx
  evaluation, and a real `Code.string_to_quoted!/1` parse of the rendered
  output.

  Also renders the template a second time with a **different** consumer's
  assigns (not the ontology's own `beam4pm` individual) to prove the template
  is genuinely reusable/parameterized, not hardcoded to one app name.
  """

  use ExUnit.Case, async: true

  @pack_dir Path.join([__DIR__, "..", "priv", "ggen", "chicago-fault-injection-pack"])
  @ontology_path Path.join(@pack_dir, "ontology.ttl")
  @gate_path Path.join([@pack_dir, "gates", "010_suites.rq"])
  @template_path Path.join([@pack_dir, "templates", "fault_injection_test.exs.eex"])

  describe "the pack's own ontology individual (beam4pm)" do
    setup do
      graph = GgenIgniter.Ontology.load!(@ontology_path)
      query_string = File.read!(@gate_path)
      [row] = GgenIgniter.Query.run(graph, query_string)

      bindings = %{
        moduleName: row["moduleName"],
        appName: row["appName"],
        targetModule: row["targetModule"],
        nodePrefix: row["nodePrefix"]
      }

      template = File.read!(@template_path) |> strip_frontmatter()

      {:ok, bindings: bindings, template: template}
    end

    test "the real gate query returns beam4pm's real row", %{bindings: bindings} do
      assert bindings.moduleName == "Beam4pm.Chicago.FaultInjectionTest"
      assert bindings.appName == "beam4pm"
      assert bindings.targetModule == "Beam4pm.Store"
      assert bindings.nodePrefix == "beam4pm_chicago"
    end

    test "rendering produces valid, parseable Elixir source", %{
      bindings: bindings,
      template: template
    } do
      rendered = GgenIgniter.Render.render(template, bindings)

      assert {:ok, _quoted} = Code.string_to_quoted(rendered)
    end

    test "rendered source carries the real @moduletag :chicago and the real fault-injection calls",
         %{bindings: bindings, template: template} do
      rendered = GgenIgniter.Render.render(template, bindings)

      assert rendered =~ "defmodule Beam4pm.Chicago.FaultInjectionTest do"
      assert rendered =~ "@moduletag :chicago"
      assert rendered =~ "use ExUnit.Case, async: false"

      # Real network-partition fault injection: cookie desync + disconnect.
      assert rendered =~ ":erlang.set_cookie(node, :beam4pm_chicago_wrong_cookie)"
      assert rendered =~ "true = :net_kernel.disconnect(node)"

      # Real process-crash fault injection against the parameterized target.
      assert rendered =~ "Process.whereis(Beam4pm.Store)"
      assert rendered =~ "Process.exit(old_pid, :kill)"

      # Node-prefix assign actually threaded through (not hardcoded "ex4pm").
      assert rendered =~ "beam4pm_chicago_os_peer_"
      refute rendered =~ "ex4pm_chicago"
    end
  end

  describe "reused against a second, different consumer's assigns" do
    test "the same template renders a second app's fault-injection suite with no leftover beam4pm identifiers" do
      template = File.read!(@template_path) |> strip_frontmatter()

      bindings = %{
        moduleName: "Ex4pmPro.Chicago.FaultInjectionTest",
        appName: "ex4pm_pro",
        targetModule: "Ex4pmPro.Runtime.Governor",
        nodePrefix: "ex4pm_pro_chicago"
      }

      rendered = GgenIgniter.Render.render(template, bindings)

      assert {:ok, _quoted} = Code.string_to_quoted(rendered)

      assert rendered =~ "defmodule Ex4pmPro.Chicago.FaultInjectionTest do"
      assert rendered =~ "Process.whereis(Ex4pmPro.Runtime.Governor)"
      assert rendered =~ ":erlang.set_cookie(node, :ex4pm_pro_chicago_wrong_cookie)"
      assert rendered =~ "ex4pm_pro_chicago_os_peer_"

      refute rendered =~ "Beam4pm"
      refute rendered =~ "beam4pm"
    end
  end

  # The template file has a ggen frontmatter block (`---\nto: ...\nmode: ...\n---`)
  # ahead of the real EEx body, matching every other real pack template in this
  # repo (see `priv/ggen/reactor-scaffold-pack/templates/reactor.ex.eex`). Strip
  # it here since this test calls `Render.render/2` directly rather than going
  # through the frontmatter-aware `mix ggen_igniter.sync` task.
  defp strip_frontmatter(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", _frontmatter, body] -> body
      [only] -> only
    end
  end
end
