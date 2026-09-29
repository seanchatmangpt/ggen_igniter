defmodule GgenIgniter.ExtensionTransformerTest do
  @moduledoc """
  Chicago-style: `rx:Transformer` facts render real `Spark.Dsl.Transformer` modules
  (`<Ext>.Transformers.<Name>`) listed in the generated extension's `transformers:`. Real sync
  subprocesses (via `GgenIgniter.Test.PackCompile`), the real compiler against real spark + ash,
  and a real Ash resource compiled in-test that uses the generated extension.

  State assertions: `Ash.Resource.Info.attribute/2` on the compiled resource (the transformer
  ADDED a fact-declared attribute), `Spark.Dsl.Extension.get_persisted/2` (the persister value
  and the `:rx_trace` of the ACTUAL transformer run order), `<Ext>.transformers/0` (the generated
  list order) and the callable `before?/1` / `after?/1` of each generated module.

  Falsifiers (second module): re-wiring ONE ordering triple changes the generated list AND the
  observed run order; malformed ordering facts (unknown transformer in before/after, unknown
  attribute type, self loop, cycle) make the sync subprocess exit non-zero with a typed
  `REFUSED_EXTENSION_SCHEMA` code and write no file. No doubles, no mocks.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 900_000

  alias GgenIgniter.Test.PackCompile

  @pack_dir Path.expand("../priv/ggen/receipted-extension-pack", __DIR__)
  @fixture Path.expand("fixtures/receipted-extension/schema.ttl", __DIR__)
  @ext SchemaFixture.Receipted
  @t SchemaFixture.Receipted.Transformers

  @stems [
    {"extension", "lib/schema_fixture/receipted.ex"},
    {"verifier", "lib/schema_fixture/receipted_verifier.ex"},
    {"transformer", "lib/schema_fixture/transformers/<%= transformer_name %>.ex"}
  ]

  def graph!(mutate \\ & &1) do
    ttl =
      File.read!(Path.join(@pack_dir, "ontology.ttl")) <>
        "\n" <> mutate.(File.read!(@fixture))

    dir = PackCompile.tmp_project!(%{"consumer.ttl" => ttl})
    Path.join(dir, "consumer.ttl")
  end

  def compile_extension!(ontology) do
    files =
      for {stem, out} <- @stems,
          r =
            PackCompile.render!("receipted-extension-pack:#{stem}",
              ontology: ontology,
              out: out,
              timeout: 900_000
            ),
          f <- r.files,
          String.ends_with?(f, ".ex"),
          do: f

    PackCompile.compile!(files)
  end

  def unload(mods) do
    ebins =
      for m <- mods,
          p = :code.which(m),
          is_list(p),
          uniq: true,
          do: p |> to_string() |> Path.dirname()

    for m <- mods do
      :code.purge(m)
      :code.delete(m)
      :code.purge(m)
    end

    for d <- ebins do
      Code.delete_path(d)
      File.rm_rf!(d)
    end

    :ok
  end

  def compile_resource(name, body) do
    source = """
    defmodule #{name} do
      use Ash.Resource,
        data_layer: Ash.DataLayer.Ets,
        domain: nil,
        validate_domain_inclusion?: false,
        extensions: [#{inspect(@ext)}]

      attributes do
        uuid_primary_key :id
      end

    #{body}
    end
    """

    dir = PackCompile.tmp_project!(%{"resource.ex" => source})

    try do
      Application.put_env(:ash, :validate_domain_config_inclusion?, false)
      PackCompile.compile([Path.join(dir, "resource.ex")])
    after
      Application.delete_env(:ash, :validate_domain_config_inclusion?)
      PackCompile.cleanup(dir)
    end
  end

  def receipted_body, do: "  receipted do\n    receipt :r\n  end\n"

  # ------------------------------------------------------------------------------- baseline

  setup_all do
    mods = compile_extension!(graph!())
    on_exit(fn -> unload(mods) end)
    %{mods: mods}
  end

  test "transformer modules are generated and listed in the ontology's topological order", %{
    mods: mods
  } do
    for n <- [First, Stamp, Seal], do: assert(Module.concat(@t, n) in mods)
    # Declared order in the fixture is seal, stamp, first; the facts say first < stamp < seal.
    assert @ext.transformers() == [@t.First, @t.Stamp, @t.Seal]
  end

  test "before?/1 and after?/1 are rendered from rx:before / rx:after facts" do
    assert @t.First.before?(@t.Stamp)
    refute @t.First.after?(@t.Stamp)
    assert @t.Stamp.after?(@t.First)
    refute @t.Stamp.before?(@t.First)
    assert @t.Seal.after?(@t.Stamp)
    refute @t.Seal.before?(@t.Stamp)
  end

  test "a compiled resource gains the fact-declared attribute and persisted values" do
    on_exit(fn -> unload([SchemaFixture.Stamped]) end)
    assert {:ok, mods, _} = compile_resource("SchemaFixture.Stamped", receipted_body())
    assert SchemaFixture.Stamped in mods

    attr = Ash.Resource.Info.attribute(SchemaFixture.Stamped, :stamped_by)
    refute is_nil(attr), "transformer did not add :stamped_by"
    assert attr.type == Ash.Type.Atom
    assert attr.default == :rx
    assert attr.public? == true

    # persister fact -> Spark.Dsl.Transformer.persist
    assert Spark.Dsl.Extension.get_persisted(SchemaFixture.Stamped, :rx_seal) == "sealed"

    # The trace records the ACTUAL run order of the real Spark transformer pipeline.
    assert Spark.Dsl.Extension.get_persisted(SchemaFixture.Stamped, :rx_trace) ==
             [:first, :stamp, :seal]

    # No transformer facts touched an unrelated attribute.
    assert Ash.Resource.Info.attribute(SchemaFixture.Stamped, :id)
    assert @ext.receipts(SchemaFixture.Stamped) == [:r]
  end
end

defmodule GgenIgniter.ExtensionTransformerFalsifierTest do
  @moduledoc """
  Falsifiers for `GgenIgniter.ExtensionTransformerTest` (Chicago-style, real sync + real compile;
  see that module): one mutated ordering triple flips both the generated list and the observed
  run order; malformed transformer facts are refused with a typed code and no file.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 900_000

  import GgenIgniter.ExtensionTransformerTest,
    only: [graph!: 1, compile_extension!: 1, compile_resource: 2, unload: 1, receipted_body: 0]

  alias GgenIgniter.Test.PackCompile

  @ext SchemaFixture.Receipted
  @t SchemaFixture.Receipted.Transformers

  test "re-wiring ONE ordering triple changes generated order and observed run order" do
    # seal: `after stamp`  ->  `after first` + `before stamp`  (first < seal < stamp)
    mutate =
      &String.replace(
        &1,
        ~s|rx:after ex:TStamp ;\n    rx:persistKey|,
        ~s|rx:after ex:TFirst ;\n    rx:before ex:TStamp ;\n    rx:persistKey|
      )

    ttl = File.read!(Path.expand("fixtures/receipted-extension/schema.ttl", __DIR__))
    refute mutate.(ttl) == ttl, "mutation did not apply"

    mods = compile_extension!(graph!(mutate))

    try do
      assert @ext.transformers() == [@t.First, @t.Seal, @t.Stamp]
      assert @t.Seal.before?(@t.Stamp)
      refute @t.Seal.after?(@t.Stamp)
      assert @t.Stamp.after?(@t.First)

      on_exit(fn -> unload([SchemaFixture.Reordered]) end)
      assert {:ok, _, _} = compile_resource("SchemaFixture.Reordered", receipted_body())

      assert Spark.Dsl.Extension.get_persisted(SchemaFixture.Reordered, :rx_trace) ==
               [:first, :seal, :stamp]
    after
      unload(mods)
    end
  end

  defp refuse!(mutate, stem, expected_code) do
    ontology = graph!(mutate)

    dir = PackCompile.tmp_project!(%{})

    out =
      case stem do
        "transformer" -> "lib/schema_fixture/transformers/<%= transformer_name %>.ex"
        _ -> "lib/schema_fixture/refused.ex"
      end

    {output, status} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "receipted-extension-pack:#{stem}",
          "--engine",
          "sparql",
          "--ontology",
          ontology,
          "--out",
          Path.join(dir, out),
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert status != 0, "expected refusal, got exit 0: #{output}"
    assert output =~ "REFUSED_EXTENSION_SCHEMA"
    assert output =~ expected_code, "expected #{expected_code} in: #{output}"
    assert Path.wildcard(Path.join(dir, "**/*.ex")) == [], "refused run wrote a file"
    PackCompile.cleanup(dir)
  end

  test "REFUSED: rx:before names an unknown transformer (transformer stem)" do
    refuse!(
      &(&1 <> "\nex:TFirst rx:before ex:NoSuchTransformer .\n"),
      "transformer",
      "UNKNOWN_TRANSFORMER_BEFORE"
    )
  end

  test "REFUSED: rx:after names an unknown transformer (extension stem)" do
    refuse!(
      &(&1 <> "\nex:TSeal rx:after ex:NoSuchTransformer .\n"),
      "extension",
      "UNKNOWN_TRANSFORMER_AFTER"
    )
  end

  test "REFUSED: unknown attribute type" do
    refuse!(
      &String.replace(&1, ~s|rx:attributeType "atom"|, ~s|rx:attributeType "uuid"|),
      "transformer",
      "UNKNOWN_ATTRIBUTE_TYPE"
    )
  end

  test "REFUSED: transformer ordered before itself" do
    refuse!(
      &(&1 <> "\nex:TSeal rx:before ex:TSeal .\n"),
      "extension",
      "TRANSFORMER_ORDER_SELF_LOOP"
    )
  end

  test "REFUSED: ordering cycle (first after seal, seal after stamp, stamp after first)" do
    refuse!(&(&1 <> "\nex:TFirst rx:after ex:TSeal .\n"), "extension", "TRANSFORMER_ORDER_CYCLE")
  end

  test "REFUSED: duplicate transformer name is a typed refusal, not an output-path crash" do
    dup =
      "\nex:TSeal2 a rx:Transformer ; rx:ofExtension ex:Target ; rx:transformerName \"seal\" .\n"

    refuse!(&(&1 <> dup), "transformer", "DUPLICATE_TRANSFORMER_NAME")
    refuse!(&(&1 <> dup), "extension", "DUPLICATE_TRANSFORMER_NAME")
  end
end
