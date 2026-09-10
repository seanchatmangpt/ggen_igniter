defmodule GgenIgniter.Render.TeraWasmTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `GgenIgniter.Render.TeraWasm` renders a
  real Tera template through the real compiled `native/tera_wasm_renderer`
  `wasm32-wasip1` module via a real `Wasmex` host instance -- no HTTP client
  mock, no stubbed collaborator, the actual WASM binary built in Phase 1
  loaded and executed for real.

  Also proves the real end-to-end dispatch: a `.tera`-suffixed template
  reconciled through `GgenIgniter.Reconcile.run/1` (the real ontology-load ->
  sparql-query -> render -> write-file pipeline) routes through this WASM
  renderer, while a `.eex`-suffixed template through the exact same pipeline
  keeps routing through the pre-existing stdlib-EEx `GgenIgniter.Render`
  path -- both real runs against the same real ontology/query fixtures, not a
  mock of the dispatch decision.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Render.TeraWasm

  describe "render/2 (direct, real wasm host)" do
    test "renders a real Tera template with plain variable interpolation" do
      assert {:ok, "Hello World!"} = TeraWasm.render("Hello {{ name }}!", %{"name" => "World"})
    end

    test "accepts a keyword-list context (normalized to a map before JSON-encoding)" do
      assert {:ok, "Hello World!"} = TeraWasm.render("Hello {{ name }}!", name: "World")
    end

    test "real tera loop/conditional syntax renders for real" do
      template = "{% for x in items %}{{ x }},{% endfor %}"
      assert {:ok, "a,b,c,"} = TeraWasm.render(template, %{"items" => ["a", "b", "c"]})
    end

    test "a real template syntax error surfaces as {:error, reason} via the tera crate itself" do
      assert {:error, reason} = TeraWasm.render("{{ unterminated", %{})
      assert is_binary(reason)
    end
  end

  describe "tera_template?/2" do
    test "true for a .tera path regardless of content" do
      assert TeraWasm.tera_template?("templates/foo.tera", "plain text, no tags")
    end

    test "false for a non-.tera path even when content contains Tera-tag-shaped syntax" do
      refute TeraWasm.tera_template?("templates/foo.txt", "{% if x %}y{% endif %}")
    end

    test "false for an .eex path with EEx-only content" do
      refute TeraWasm.tera_template?("templates/foo.ex.eex", "<%= name %>")
    end

    test "false for a real .eex fixture whose Elixir body incidentally contains '{%' " <>
           "(the exact false-positive shape a content-sniffing predicate would misroute)" do
      refute TeraWasm.tera_template?(
               "foo.ex.eex",
               "{%{igniter | tasks: kept}, events ++ Enum.map(dropped, &dropped_event(step, &1))}"
             )
    end

    test "nil template_path is always false regardless of content" do
      refute TeraWasm.tera_template?(nil, "<%= name %>")
      refute TeraWasm.tera_template?(nil, "{% if x %}y{% endif %}")
    end
  end

  describe "real end-to-end dispatch through GgenIgniter.Reconcile.run/1" do
    setup do
      out_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_tera_wasm_dispatch_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(out_dir)
      File.mkdir_p!(out_dir)
      on_exit(fn -> File.rm_rf!(out_dir) end)

      ontology_path = Path.join(out_dir, "ontology.ttl")

      File.write!(ontology_path, """
      @prefix ex: <http://example.org/> .
      ex:thing ex:greetingName "World" .
      """)

      query_path = Path.join(out_dir, "greeting.rq")

      File.write!(query_path, """
      SELECT ?greeting_name WHERE {
        ?s <http://example.org/greetingName> ?greeting_name .
      }
      """)

      %{out_dir: out_dir, ontology_path: ontology_path, query_path: query_path}
    end

    test "a .tera template routes through the real WASM tera renderer", %{
      out_dir: out_dir,
      ontology_path: ontology_path,
      query_path: query_path
    } do
      template_path = Path.join(out_dir, "greeting.tera")
      File.write!(template_path, "Hello {{ greeting_name }}!")
      out_path = Path.join(out_dir, "greeting.txt")

      assert {:ok, result} =
               GgenIgniter.Reconcile.run(
                 engine: "sparql",
                 ontology: ontology_path,
                 query: "greeting=#{query_path}",
                 template: template_path,
                 out: out_path
               )

      assert result.outcome == :written
      assert File.read!(out_path) == "Hello World!"
    end

    test "an .eex template through the same pipeline still routes through stdlib EEx", %{
      out_dir: out_dir,
      ontology_path: ontology_path,
      query_path: query_path
    } do
      template_path = Path.join(out_dir, "greeting.ex.eex")
      File.write!(template_path, "Hello <%= greeting_name %>!")
      out_path = Path.join(out_dir, "greeting_eex.txt")

      assert {:ok, result} =
               GgenIgniter.Reconcile.run(
                 engine: "sparql",
                 ontology: ontology_path,
                 query: "greeting=#{query_path}",
                 template: template_path,
                 out: out_path
               )

      assert result.outcome == :written
      assert File.read!(out_path) == "Hello World!"
    end
  end
end
