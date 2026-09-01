defmodule GgenIgniterEvalModeIgniterTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mode: eval` templates can drive real
  `Igniter.Project.*` codemods as part of a real
  `GgenIgniter.Reactors.ReconcileReactor.run/1` invocation -- real ontology
  files, a real SPARQL query, real EEx-templated eval bodies, real
  `Igniter.Project.Module.create_module/3` calls against the live
  `igniter:` binding `actuate_eval_sequential/2` threads into
  `Actuate.eval_code!/2`, and real assertions on the resulting
  `%GgenIgniter.Receipt{}`'s `metadata["igniter_diverged"]`/
  `metadata["igniter_paths"]`.

  This is the first test in this repo where a rendered ggen template's
  `mode: eval` body genuinely drives Igniter's own AST-mutation API as part
  of a real ontology->render->actuate run -- see `lib/ggen_igniter/actuate.ex`'s
  `eval_code!/2` moduledoc ("The `igniter:` binding contract") for the full
  contract this test exercises.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_eval_igniter_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project: enough for a real `mix
  # compile --warnings-as-errors` subprocess (`:verify`) to succeed honestly.
  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "eval_igniter_fixture_#{System.unique_integer([:positive])}"

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(app)}.MixProject do
      use Mix.Project

      def project do
        [app: :#{app}, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
    end
    """)

    dir
  end

  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/evi#> .
    ex:Alpha a ex:Module ;
      ex:name "Alpha" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/evi#>
    SELECT ?name WHERE {
      ex:Alpha ex:name ?name .
    }
    """)

    path
  end

  defp write_eval_template!(dir, filename, body) do
    path = Path.join(dir, filename)
    File.write!(path, body)
    path
  end

  describe "single mode: eval target driving a real Igniter codemod" do
    test "the created module's path lands in the receipt's igniter_paths" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      project_dir = new_mix_project!()

      eval_template_path =
        write_eval_template!(fixtures, "create_one.exs.eex", """
        Igniter.Project.Module.create_module(
          igniter,
          GgenIgniterEvalIgniterFixture.One,
          "def hello, do: :one"
        )
        """)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: eval_template_path, mode: "eval", query: "spec=#{query_path}"]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert receipt.metadata["igniter_diverged"] == true

      assert Enum.any?(
               receipt.metadata["igniter_paths"],
               &String.contains?(&1, "ggen_igniter_eval_igniter_fixture/one")
             )
    end

    test "a non-Igniter eval body leaves igniter_diverged false (zero regression)" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      project_dir = new_mix_project!()

      eval_template_path = write_eval_template!(fixtures, "plain.exs.eex", "1 + 1\n")

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: eval_template_path, mode: "eval", query: "spec=#{query_path}"]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert receipt.metadata["igniter_diverged"] == false
      assert receipt.metadata["igniter_paths"] == []
      assert receipt.metadata["notice"] =~ "-> 2"
    end
  end

  describe "multiple mode: eval targets: real cross-target composition" do
    test "N eval'd Igniter codemods compose into ONE final %Igniter{}, in row order" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      project_dir = new_mix_project!()

      # Row 1: creates a real module against a fresh accumulator.
      row1_template =
        write_eval_template!(fixtures, "row1.exs.eex", """
        Igniter.Project.Module.create_module(
          igniter,
          GgenIgniterEvalIgniterFixture.RowOne,
          "def hello, do: :row_one"
        )
        """)

      # Row 2: a plain, non-Igniter passthrough -- proves the accumulator
      # survives an intervening non-Igniter target unchanged, rather than
      # being reset or lost.
      row2_template = write_eval_template!(fixtures, "row2.exs.eex", "\"row two, no igniter\"\n")

      # Row 3: creates a SECOND real module -- if this row's own body only
      # saw a FRESH Igniter.new/0 (composition broken), the final result
      # would contain only RowThree's module. If composition works, the
      # final accumulator (surfaced via row 3's own :eval item -- the LAST
      # item run in the fold) contains BOTH RowOne's and RowThree's paths.
      row3_template =
        write_eval_template!(fixtures, "row3.exs.eex", """
        Igniter.Project.Module.create_module(
          igniter,
          GgenIgniterEvalIgniterFixture.RowThree,
          "def hello, do: :row_three"
        )
        """)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: row1_template, mode: "eval", query: "spec=#{query_path}"],
          [template: row2_template, mode: "eval", query: "spec=#{query_path}"],
          [template: row3_template, mode: "eval", query: "spec=#{query_path}"]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert receipt.metadata["igniter_diverged"] == true

      paths = receipt.metadata["igniter_paths"]

      assert Enum.any?(paths, &String.contains?(&1, "ggen_igniter_eval_igniter_fixture/row_one")),
             "expected row 1's created module to survive into the final composed result: #{inspect(paths)}"

      assert Enum.any?(
               paths,
               &String.contains?(&1, "ggen_igniter_eval_igniter_fixture/row_three")
             ),
             "expected row 3's created module in the final composed result: #{inspect(paths)}"
    end
  end
end
