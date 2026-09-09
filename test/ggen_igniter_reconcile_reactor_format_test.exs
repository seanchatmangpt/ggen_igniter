defmodule GgenIgniter.ReconcileReactorFormatTest do
  @moduledoc """
  Chicago-style, no-mocks proof of the real in-process auto-formatting step
  added to `GgenIgniter.Reactors.ReconcileReactor.render_target/2`
  (`format_generated_content/2`) -- see that module's own moduledoc "`:verify`
  scope" section for the disclosed design.

  Every assertion here reads REAL bytes back from a REAL file on disk,
  written by a REAL `ReconcileReactor.run/1` call against a real, minimal
  scratch Mix project. No `Code`/`File`/`Mix` mocking anywhere in this file.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_format_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "fmt_fixture_#{System.unique_integer([:positive])}"

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
    @prefix ex: <http://example.org/rr#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterFormatFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    """)

    path
  end

  defp write_query!(dir, name, subject) do
    path = Path.join(dir, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rr#>
    SELECT ?module_name ?greeting WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  # Real, VALID, but deliberately badly-formatted Elixir: inconsistent
  # indentation, extra blank lines, a trailing space before the newline --
  # exactly the "formatting noise" defect class disclosed in the task
  # (bare hyphenated-atom-key content aside), not a parse failure.
  defp write_messy_template!(dir) do
    path = Path.join(dir, "messy.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do


        def greeting,     do:    "<%= greeting %>"


      def   other  do
            :ok
      end
    end
    """)

    path
  end

  # Deliberately invalid Elixir -- an unclosed `(` before `end`. Neither
  # `Code.format_string!/1` nor `mix compile` can parse this.
  defp write_broken_template!(dir) do
    path = Path.join(dir, "broken.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def broken(
    end
    """)

    path
  end

  # A non-Elixir target: JSON body, deliberately not what `jq`/`Jason` would
  # consider "canonically formatted" (irregular spacing) -- proves this pass
  # never touches non-`.ex`/`.exs` output.
  defp write_json_template!(dir) do
    path = Path.join(dir, "data.json.eex")

    File.write!(path, ~s({"name":  "<%= module_name %>" ,"greeting":"<%= greeting %>"}))

    path
  end

  describe "real .ex output is auto-formatted before it reaches disk" do
    test "badly-formatted but valid Elixir is written already correctly formatted" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      template_path = write_messy_template!(fixtures)

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "messy.ex"])

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: template_path, query: "spec=#{query_path}", out: out_path]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert File.exists?(out_path)

      written = File.read!(out_path)

      # The real, load-bearing proof: the bytes on disk are exactly what
      # `Code.format_string!/1` produces for THIS SAME rendered content --
      # not merely "compiles", but genuinely reformatted.
      expected =
        written
        |> String.trim_trailing("\n")
        |> Code.format_string!()
        |> IO.iodata_to_binary()

      assert String.trim_trailing(written, "\n") == expected

      # And it is real, valid, differently-shaped Elixir than the messy
      # source -- the messy double-blank-line/indentation noise is gone.
      refute written =~ "\n\n\n"
      refute written =~ "    def greeting"
    end
  end

  describe "non-Elixir output is never run through the formatter" do
    test "a .json target's rendered content is passed through byte-identical" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      template_path = write_json_template!(fixtures)

      project_dir = new_mix_project!()
      out_path = Path.join(project_dir, "data.json")

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: template_path, query: "spec=#{query_path}", out: out_path]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert File.exists?(out_path)

      # Byte-identical to the raw rendered body -- irregular JSON spacing
      # and all. If this pass ever touched non-`.ex`/`.exs` output, this
      # exact string would change.
      assert File.read!(out_path) ==
               ~s({"name":  "GgenIgniterFormatFixture.Alpha" ,"greeting":"hello_from_alpha"})
    end
  end

  describe "a Code.format_string!/1 failure never crashes or blocks the sync" do
    test "invalid Elixir is still written unformatted; mix compile is what fails the run" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      broken_template = write_broken_template!(fixtures)

      # Independent, direct confirmation that Code.format_string!/1 itself
      # really rejects this exact rendered content (this is what the
      # `rescue` clause added to `format_generated_content/2` must catch).
      raw_broken = "defmodule GgenIgniterFormatFixture.Alpha do\n  def broken(\nend\n"

      assert_raise MismatchedDelimiterError, fn ->
        Code.format_string!(raw_broken)
      end

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "broken.ex"])

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: broken_template, query: "spec=#{query_path}", out: out_path]
        ]
      ]

      # The real proof this task requires: the run does NOT crash/raise --
      # it returns a real, admitted `{:error, receipt}` result, because
      # `:verify`'s real `mix compile --warnings-as-errors` subprocess is
      # the thing that correctly rejects this content, not the formatter.
      result = ReconcileReactor.run(reconcile_opts)
      assert {:error, receipt} = result
      assert receipt.standing == :build_broken

      # Because :verify fails, :actuate's own undo/4 restores pre-run state
      # -- there was no pre-existing file here, so it is deleted again. This
      # confirms the write really happened (the formatter's rescue path let
      # unformatted content reach :actuate) and was then genuinely reverted
      # by the SAME real compensation mechanism the other reactor tests
      # exercise -- not a crash inside formatting itself.
      refute File.exists?(out_path)
    end
  end
end
