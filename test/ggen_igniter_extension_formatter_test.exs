defmodule GgenIgniter.ExtensionFormatterTest do
  @moduledoc """
  Chicago-style: the receipted-extension-pack renders the consumer's `.formatter.exs`
  (`spark_locals_without_parens` + `export: [locals_without_parens: ...]`) from entity facts, and
  the installer wire task imports the extension's package into the consumer's `.formatter.exs`.

  The oracle is REAL SPARK, not our arithmetic: a real `mix run` subprocess loads the generated
  extension and runs the real `mix spark.formatter --check --extensions SchemaFixture.Receipted`
  (deps/spark/lib/mix/tasks/spark.formatter.ex) inside a tmp project directory. The rendered file
  must be byte-identical to what Spark would write. The formatted resource is then run through
  the real `Code.format_string!/2` with the rendered `locals_without_parens`: calls stay
  parens-free, and with the export list removed the formatter DOES add parens (non-vacuous).

  Installer: `Igniter.Test.test_project/1` + the rendered wire task, `assert_has_patch` on
  `.formatter.exs` for the first run, `GgenIgniter.Test.IgniterIdempotence` (second run
  `assert_unchanged`).

  Falsifier (second module): rename an entity in the ontology WITHOUT regenerating the formatter
  file -> the real `spark.formatter --check` subprocess fails ("not up to date"), while the
  regenerated file passes. No doubles, no mocks.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 900_000

  alias GgenIgniter.Test.PackCompile

  @pack_dir Path.expand("../priv/ggen/receipted-extension-pack", __DIR__)
  @fixture Path.expand("fixtures/receipted-extension/schema.ttl", __DIR__)
  @widget_src Path.expand("fixtures/receipted-extension/schema_widget.ex.txt", __DIR__)
  @ext "SchemaFixture.Receipted"

  def graph!(mutate \\ & &1) do
    ttl =
      File.read!(Path.join(@pack_dir, "ontology.ttl")) <>
        "\n" <> mutate.(File.read!(@fixture))

    dir = PackCompile.tmp_project!(%{"consumer.ttl" => ttl})
    Path.join(dir, "consumer.ttl")
  end

  def render!(stem, ontology, out) do
    PackCompile.render!("receipted-extension-pack:#{stem}",
      ontology: ontology,
      out: out,
      timeout: 900_000
    )
  end

  # Renders the extension + verifier + transformers + formatter for `ontology`; returns
  # %{files: [...generated .ex...], formatter: path-to-.formatter.exs}.
  def render_project!(ontology) do
    rendered = [
      render!("extension", ontology, "lib/schema_fixture/receipted.ex"),
      render!("verifier", ontology, "lib/schema_fixture/receipted_verifier.ex"),
      render!(
        "transformer",
        ontology,
        "lib/schema_fixture/transformers/<%= transformer_name %>.ex"
      ),
      render!("formatter", ontology, ".formatter.exs")
    ]

    all = Enum.flat_map(rendered, & &1.files)

    %{
      files: Enum.filter(all, &String.ends_with?(&1, ".ex")),
      formatter: Enum.find(all, &(Path.basename(&1) == ".formatter.exs"))
    }
  end

  @script """
  files = "RX_FILES" |> System.fetch_env!() |> String.split("|")
  {:ok, _, _} = Kernel.ParallelCompiler.compile(files)
  File.cd!(System.fetch_env!("RX_DIR"))
  Mix.Task.run("spark.formatter", "RX_ARGS" |> System.fetch_env!() |> String.split(" "))
  """

  @doc """
  Runs the REAL `mix spark.formatter` in `dir` (which must hold a `.formatter.exs`) with the
  extension compiled from `files`. Returns `{output, exit_status}`.
  """
  def spark_formatter(files, dir, args) do
    System.cmd("mix", ["run", "--no-start", "-e", @script],
      cd: File.cwd!(),
      env: [
        {"MIX_ENV", "test"},
        {"RX_FILES", Enum.join(files, "|")},
        {"RX_DIR", dir},
        {"RX_ARGS", Enum.join(["--extensions", @ext | args], " ")}
      ],
      stderr_to_stdout: true
    )
  end

  def eval_formatter!(path) do
    {config, bindings} = Code.eval_file(path)
    {config, Keyword.fetch!(bindings, :spark_locals_without_parens)}
  end

  # ------------------------------------------------------------------------------- baseline

  setup_all do
    project = render_project!(graph!())
    %{project: project}
  end

  # entity -> arities the ontology implies (required positional args r, total positional n:
  # arities r+0..n+1) plus 1-arity option builders for non-required-arg keys.
  @expected [
    attestation: 1,
    attestation: 2,
    attestation: 3,
    level: 1,
    receipt: 1,
    receipt: 2,
    retries: 1,
    role: 1,
    sealed: 1,
    tags: 1,
    weight: 1,
    witness: 1,
    witness: 2
  ]

  test "the .formatter.exs export lists every entity (with arities) and every option key", %{
    project: %{formatter: path}
  } do
    {config, locals} = eval_formatter!(path)

    assert locals == @expected
    assert config[:locals_without_parens] == locals
    assert config[:export][:locals_without_parens] == locals

    for entity <- [:receipt, :attestation, :witness] do
      assert Keyword.has_key?(locals, entity), "entity #{entity} missing from export"
    end
  end

  test "real `mix spark.formatter --check` accepts the rendered file byte-for-byte", %{
    project: %{files: files, formatter: path}
  } do
    dir = PackCompile.tmp_project!(%{".formatter.exs" => File.read!(path)})
    {output, status} = spark_formatter(files, dir, ["--check"])
    PackCompile.cleanup(dir)

    assert status == 0, output
    assert output =~ "The current .formatter.exs is correct"
  end

  test "real `mix spark.formatter` over an empty seed produces exactly the rendered locals", %{
    project: %{files: files, formatter: path}
  } do
    seed = """
    spark_locals_without_parens = []

    [
      locals_without_parens: spark_locals_without_parens,
      export: [locals_without_parens: spark_locals_without_parens]
    ]
    """

    dir = PackCompile.tmp_project!(%{".formatter.exs" => seed})
    {output, status} = spark_formatter(files, dir, [])
    assert status == 0, output

    {_config, spark_locals} = eval_formatter!(Path.join(dir, ".formatter.exs"))
    {_config, rendered_locals} = eval_formatter!(path)
    PackCompile.cleanup(dir)

    assert spark_locals == rendered_locals
    assert spark_locals == @expected
  end

  @resource """
  defmodule SchemaFixture.Formatted do
    use Ash.Resource, extensions: [SchemaFixture.Receipted]

    receipted do
      receipt :order_receipt, retries: 5
      attestation "alice", 2, role: :approver
    end

    audit do
      witness :w1, weight: 4
    end
  end
  """

  test "formatted resource keeps entity calls without parens; without the export it adds them",
       %{project: %{formatter: path}} do
    {config, _locals} = eval_formatter!(path)

    formatted = IO.iodata_to_binary(Code.format_string!(@resource, config))
    assert formatted <> "\n" == @resource
    refute formatted =~ "receipt("
    refute formatted =~ "witness("

    bare = IO.iodata_to_binary(Code.format_string!(@resource, locals_without_parens: []))
    assert bare =~ "receipt(:order_receipt, retries: 5)"
    assert bare =~ "witness(:w1, weight: 4)"
  end

  # -------------------------------------------------------------------------- installer task

  describe "installer imports the extension package into .formatter.exs" do
    import Igniter.Test

    @wire Mix.Tasks.SchemaFixture.Receipted.Wire

    setup do
      rendered = render!("wire", graph!(), "lib/mix/tasks/schema_fixture.receipted.wire.ex")
      path = Enum.find(rendered.files, &String.ends_with?(&1, "receipted.wire.ex"))
      source = File.read!(path)

      previous = Code.get_compiler_option(:ignore_module_conflict)
      Code.put_compiler_option(:ignore_module_conflict, true)

      try do
        compiled = Code.compile_string(source, path)
        assert Enum.any?(compiled, fn {m, _} -> m == @wire end)
      after
        Code.put_compiler_option(:ignore_module_conflict, previous)
      end

      on_exit(fn ->
        :code.purge(@wire)
        :code.delete(@wire)
      end)

      %{source: source}
    end

    defp project do
      [
        app_name: :schema_fixture,
        files: %{"lib/schema_fixture/widget.ex" => File.read!(@widget_src)}
      ]
    end

    defp quiet_compose(igniter, argv \\ []) do
      parent = self()

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        ExUnit.CaptureIO.capture_io(fn ->
          send(
            parent,
            {:ig, Igniter.compose_task(igniter, "schema_fixture.receipted.wire", argv)}
          )
        end)
      end)

      receive do
        {:ig, r} -> r
      after
        10_000 -> flunk("timed out composing wire task")
      end
    end

    test "rendered task carries the fact-derived formatter dep and calls import_dep", %{
      source: source
    } do
      assert source =~ "Igniter.Project.Formatter.import_dep(igniter, @formatter_dep)"
      assert source =~ "@formatter_dep :schema_fixture"
    end

    test "first run patches .formatter.exs (and the resource); second run is inert" do
      first = project() |> Igniter.Test.test_project() |> quiet_compose()

      assert_has_patch(first, ".formatter.exs", """
      + |  import_deps: [:schema_fixture]
      """)

      assert_has_patch(first, "lib/schema_fixture/widget.ex", """
      + |    extensions: [SchemaFixture.Receipted]
      """)

      applied = Igniter.Test.apply_igniter!(first)
      second = quiet_compose(applied)
      assert_unchanged(second)
      assert second.issues == [], inspect(second.issues)

      formatter =
        second.rewrite |> Rewrite.source!(".formatter.exs") |> Rewrite.Source.get(:content)

      assert length(Regex.scan(~r/:schema_fixture/, formatter)) == 1
    end

    test "GgenIgniter.Test.IgniterIdempotence: codemod is idempotent and non-vacuous" do
      final =
        GgenIgniter.Test.IgniterIdempotence.assert_idempotent(
          "schema_fixture.receipted.wire",
          [],
          project()
        )

      content = final.rewrite |> Rewrite.source!(".formatter.exs") |> Rewrite.Source.get(:content)
      assert content =~ "import_deps: [:schema_fixture]"
    end
  end
end

defmodule GgenIgniter.ExtensionFormatterFalsifierTest do
  @moduledoc """
  Falsifier for `GgenIgniter.ExtensionFormatterTest` (Chicago-style: real sync subprocesses and
  the real `mix spark.formatter` subprocess as oracle): an entity renamed in the ontology WITHOUT
  regenerating `.formatter.exs` makes the real formatter check fail; regenerating makes it pass.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 900_000

  import GgenIgniter.ExtensionFormatterTest,
    only: [graph!: 0, graph!: 1, render_project!: 1, spark_formatter: 3]

  alias GgenIgniter.Test.PackCompile

  test "rename an entity without regenerating -> real spark.formatter --check refuses" do
    stale = render_project!(graph!())

    renamed =
      graph!(&String.replace(&1, ~s|rx:entityName "witness"|, ~s|rx:entityName "observer"|))

    fresh = render_project!(renamed)

    stale_text = File.read!(stale.formatter)
    fresh_text = File.read!(fresh.formatter)
    refute stale_text == fresh_text, "mutation did not change the rendered formatter file"
    assert stale_text =~ "witness: 1"
    assert fresh_text =~ "observer: 1"
    refute fresh_text =~ "witness: 1"

    # Stale file + renamed extension: the REAL formatter check fails.
    stale_dir = PackCompile.tmp_project!(%{".formatter.exs" => stale_text})
    {out_stale, status_stale} = spark_formatter(fresh.files, stale_dir, ["--check"])
    PackCompile.cleanup(stale_dir)
    assert status_stale != 0, out_stale
    assert out_stale =~ ".formatter.exs is not up to date"

    # Regenerated file + renamed extension: the REAL formatter check passes.
    fresh_dir = PackCompile.tmp_project!(%{".formatter.exs" => fresh_text})
    {out_fresh, status_fresh} = spark_formatter(fresh.files, fresh_dir, ["--check"])
    PackCompile.cleanup(fresh_dir)
    assert status_fresh == 0, out_fresh
  end
end
