defmodule GgenIgniter.ExtensionSchemaTest do
  @moduledoc """
  Chicago-style: the receipted-extension-pack's SCHEMA is data. Real
  `mix ggen_igniter.sync` subprocesses (via `GgenIgniter.Test.PackCompile`) render the pack
  from `test/fixtures/receipted-extension/schema.ttl` (2 sections, 3 entities, typed fields,
  positional/keyword args); the real compiler builds the extension against real spark + ash;
  real Ash resources using the generated DSL are compiled in-test.

  State assertions only: `Spark.Dsl.Extension.get_entities/2` on a compiled resource, the
  `%Spark.Dsl.Entity{}` args/schema the generated module exposes via `sections/0`, and the real
  `Spark.Error.DslError` compiler diagnostic for a resource omitting a required field.

  Falsifiers (second module): flip one `rx:required` triple -> the resource that was refused now
  compiles and the generated schema says `required: false`; mutate the graph into a malformed one
  (duplicate entity, unknown type, bad default, missing primary entity) -> the sync subprocess
  exits non-zero with a typed `REFUSED_EXTENSION_SCHEMA` code and NO `.ex` file is written.
  No doubles, no mocks.
  """

  use ExUnit.Case, async: false
  # async: false -- compiled modules live in the one global code server.

  @moduletag :integration
  @moduletag timeout: 900_000

  alias GgenIgniter.Test.PackCompile

  @pack_dir Path.expand("../priv/ggen/receipted-extension-pack", __DIR__)
  @fixture Path.expand("fixtures/receipted-extension/schema.ttl", __DIR__)
  @ext SchemaFixture.Receipted

  @stems [
    {"extension", "lib/schema_fixture/receipted.ex"},
    {"verifier", "lib/schema_fixture/receipted_verifier.ex"},
    {"transformer", "lib/schema_fixture/transformers/<%= transformer_name %>.ex"}
  ]

  # ------------------------------------------------------------------ helpers (shared shape)

  def graph!(mutate \\ & &1) do
    ttl =
      File.read!(Path.join(@pack_dir, "ontology.ttl")) <>
        "\n" <> mutate.(File.read!(@fixture))

    dir = PackCompile.tmp_project!(%{"consumer.ttl" => ttl})
    Path.join(dir, "consumer.ttl")
  end

  def render_all!(ontology) do
    for {stem, out} <- @stems do
      PackCompile.render!("receipted-extension-pack:#{stem}",
        ontology: ontology,
        out: out,
        timeout: 900_000
      )
    end
  end

  def compile_extension!(ontology) do
    rendered = render_all!(ontology)
    files = rendered |> Enum.flat_map(& &1.files) |> Enum.filter(&String.ends_with?(&1, ".ex"))
    {PackCompile.compile!(files), rendered}
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
    path = Path.join(dir, "resource.ex")

    try do
      Application.put_env(:ash, :validate_domain_config_inclusion?, false)
      PackCompile.compile([path])
    after
      Application.delete_env(:ash, :validate_domain_config_inclusion?)
      PackCompile.cleanup(dir)
    end
  end

  def messages(diags), do: Enum.map(diags, & &1.message)

  @valid_body """
    receipted do
      receipt :order_receipt, retries: 5
      attestation "alice", 2, role: :approver
      attestation "bob", role: :reviewer
    end

    audit do
      witness :w1, weight: 4
    end
  """

  @missing_role_body """
    receipted do
      receipt :order_receipt
      attestation "alice"
    end
  """

  def valid_body, do: @valid_body
  def missing_role_body, do: @missing_role_body

  # ------------------------------------------------------------------------------- baseline

  setup_all do
    ontology = graph!()
    {mods, rendered} = compile_extension!(ontology)
    on_exit(fn -> unload(mods) end)
    %{mods: mods, rendered: rendered}
  end

  test "extension module is generated with every declared entity struct", %{mods: mods} do
    for m <- [@ext, @ext.Receipt, @ext.Attestation, @ext.Witness, @ext.Verifier] do
      assert m in mods, "#{inspect(m)} missing from #{inspect(mods)}"
    end

    assert Enum.map(@ext.sections(), & &1.name) == [:receipted, :audit]
  end

  test "a resource declaring 2 sections / 3 entities exposes their values via get_entities/2" do
    on_exit(fn -> unload([SchemaFixture.Full]) end)
    assert {:ok, mods, []} = compile_resource("SchemaFixture.Full", @valid_body)
    assert SchemaFixture.Full in mods

    strip = fn s -> Map.drop(Map.from_struct(s), [:__spark_metadata__]) end
    entities = Spark.Dsl.Extension.get_entities(SchemaFixture.Full, [:receipted])

    assert [receipt, alice, bob] = entities

    assert Enum.map(entities, & &1.__struct__) == [
             @ext.Receipt,
             @ext.Attestation,
             @ext.Attestation
           ]

    assert strip.(receipt) == %{kind: :order_receipt, retries: 5, sealed: false, tags: [:a, :b]}
    assert strip.(alice) == %{signer: "alice", level: 2, role: :approver}
    assert strip.(bob) == %{signer: "bob", level: 1, role: :reviewer}

    assert [witness] = Spark.Dsl.Extension.get_entities(SchemaFixture.Full, [:audit])
    assert witness.__struct__ == @ext.Witness
    assert strip.(witness) == %{name: :w1, weight: 4}

    assert @ext.receipts(SchemaFixture.Full) == [:order_receipt]
  end

  test "generated Spark.Dsl.Entity args/schema equal the ontology triples" do
    [receipted, audit] = @ext.sections()
    assert Enum.map(receipted.entities, & &1.name) == [:receipt, :attestation]
    assert Enum.map(audit.entities, & &1.name) == [:witness]
    assert receipted.describe == "Receipt declarations."

    [receipt, attestation] = receipted.entities
    [witness] = audit.entities

    # rx:argPosition + rx:required drive args: required -> :name, optional -> {:optional, :name}.
    assert receipt.args == [:kind]
    assert attestation.args == [:signer, {:optional, :level}]
    assert witness.args == [:name]

    assert Enum.sort(receipt.schema) ==
             Enum.sort(
               kind: [type: :atom, required: true, doc: "Receipt kind."],
               retries: [type: :integer, required: false, default: 3, doc: "Retry budget."],
               tags: [type: {:list, :atom}, required: false, default: [:a, :b], doc: "Tags."],
               sealed: [type: :boolean, required: false, default: false, doc: "Sealed flag."]
             )

    assert Enum.sort(attestation.schema) ==
             Enum.sort(
               signer: [type: :string, required: true, doc: "Signer name."],
               level: [type: :integer, required: false, default: 1, doc: "Attestation level."],
               role: [type: :atom, required: true, doc: "Signer role."]
             )

    assert Enum.sort(witness.schema) ==
             Enum.sort(
               name: [type: :atom, required: true, doc: "Witness name."],
               weight: [type: :integer, required: false, default: 1, doc: "Witness weight."]
             )
  end

  test "a resource omitting a required field fails compilation with Spark.Error.DslError" do
    on_exit(fn -> unload([SchemaFixture.MissingRole]) end)

    result = compile_resource("SchemaFixture.MissingRole", @missing_role_body)

    diags =
      case result do
        {:error, d} -> d
        {:ok, _mods, d} -> d
      end

    text = Enum.join(messages(diags), "\n")

    assert text =~ "Spark.Error.DslError",
           "required field omitted but no DslError diagnostic: #{inspect(result)}"

    assert text =~ "role"
    assert match?({:error, _}, result)
  end

  test "a resource with NO declaration still hits the receipt verifier (existing law intact)" do
    on_exit(fn -> unload([SchemaFixture.NoReceipt]) end)
    result = compile_resource("SchemaFixture.NoReceipt", "")

    diags =
      case result do
        {:error, d} -> d
        {:ok, _mods, d} -> d
      end

    assert diags |> messages() |> Enum.join("\n") =~ "REFUSED_NO_RECEIPT"
  end
end

defmodule GgenIgniter.ExtensionSchemaFalsifierTest do
  @moduledoc """
  Falsifiers for `GgenIgniter.ExtensionSchemaTest`, Chicago-style: each mutates ONE fact of the
  real fixture graph, re-renders with a real sync subprocess, and asserts the observable STATE
  flips (a refused resource now compiles; a malformed graph is refused with a typed code and no
  file on disk). No doubles.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 900_000

  import GgenIgniter.ExtensionSchemaTest,
    only: [
      graph!: 0,
      graph!: 1,
      compile_extension!: 1,
      compile_resource: 2,
      unload: 1,
      messages: 1
    ]

  alias GgenIgniter.Test.PackCompile

  @ext SchemaFixture.Receipted
  @role_required ~s|rx:fieldName "role" ; rx:fieldType "atom" ; rx:required true|
  @role_optional ~s|rx:fieldName "role" ; rx:fieldType "atom" ; rx:required false|

  test "flipping ONE rx:required triple flips compile refusal and the generated schema" do
    ttl = File.read!(Path.expand("fixtures/receipted-extension/schema.ttl", __DIR__))
    assert ttl =~ @role_required, "fixture no longer carries the triple under test"

    # Baseline (required true): resource omitting role is refused.
    {mods, _} = compile_extension!(graph!())

    try do
      assert {:error, diags} = compile_resource("SchemaFixture.FlipA", omit_role())
      assert diags |> messages() |> Enum.join("\n") =~ "Spark.Error.DslError"
      attestation = @ext.sections() |> hd() |> Map.fetch!(:entities) |> Enum.at(1)
      assert attestation.schema[:role][:required] == true
    after
      unload(mods)
      unload([SchemaFixture.FlipA])
    end

    # Mutated (required false): the SAME resource now compiles; schema says required: false.
    {mods2, _} = compile_extension!(graph!(&String.replace(&1, @role_required, @role_optional)))

    try do
      assert {:ok, compiled, _} = compile_resource("SchemaFixture.FlipB", omit_role())
      assert SchemaFixture.FlipB in compiled
      attestation = @ext.sections() |> hd() |> Map.fetch!(:entities) |> Enum.at(1)
      assert attestation.schema[:role][:required] == false
    after
      unload(mods2)
      unload([SchemaFixture.FlipB])
    end
  end

  defp omit_role, do: GgenIgniter.ExtensionSchemaTest.missing_role_body()

  # ---------------------------------------------------------------- refusal gates (negative)

  defp refuse!(mutate, stem \\ "extension", expected_code) do
    ontology = graph!(mutate)

    assert {:error, %{exit_status: status, output: output}} =
             PackCompile.render("receipted-extension-pack:#{stem}",
               ontology: ontology,
               out: "lib/schema_fixture/refused.ex",
               timeout: 900_000
             )

    assert status != 0
    assert output =~ "REFUSED_EXTENSION_SCHEMA"
    assert output =~ expected_code, "expected #{expected_code} in: #{output}"
    :ok
  end

  test "REFUSED: duplicate entity name across the extension" do
    refuse!(
      &(&1 <>
          """

          ex:EntDup a rx:Entity ; rx:inSection ex:SecAudit ; rx:entityName "receipt" .
          """),
      "DUPLICATE_ENTITY_NAME"
    )
  end

  test "REFUSED: unknown field type" do
    refuse!(
      &String.replace(
        &1,
        ~s|rx:fieldType "integer" ; rx:default "3"|,
        ~s|rx:fieldType "float" ; rx:default "3"|
      ),
      "UNKNOWN_FIELD_TYPE"
    )
  end

  test "REFUSED: default on a required field" do
    refuse!(
      &String.replace(
        &1,
        ~s|rx:fieldName "role" ; rx:fieldType "atom" ; rx:required true|,
        ~s|rx:fieldName "role" ; rx:fieldType "atom" ; rx:required true ; rx:default "x"|
      ),
      "DEFAULT_ON_REQUIRED_FIELD"
    )
  end

  test "REFUSED: default on a field whose rx:required is the string \"true\" (fail-open form)" do
    refuse!(
      &(&1 <>
          """

          ex:FBadStr a rx:Field ; rx:ofEntity ex:EntWitness ;
              rx:fieldName "bad" ; rx:fieldType "atom" ; rx:required "true" ; rx:default "x" .
          """),
      "DEFAULT_ON_REQUIRED_FIELD"
    )
  end

  test "REFUSED: field name that is not a valid Elixir identifier" do
    refuse!(
      &(&1 <>
          """

          ex:FBadName a rx:Field ; rx:ofEntity ex:EntWitness ;
              rx:fieldName "bad name" ; rx:fieldType "atom" .
          """),
      "INVALID_IDENTIFIER"
    )
  end

  test "REFUSED: entity, section, transformer and attribute names are identifier-checked" do
    refuse!(
      &String.replace(&1, ~s|rx:entityName "witness"|, ~s|rx:entityName "Wit Ness"|),
      "INVALID_IDENTIFIER"
    )

    refuse!(
      &String.replace(&1, ~s|rx:sectionName "audit"|, ~s|rx:sectionName "au-dit"|),
      "INVALID_IDENTIFIER"
    )

    refuse!(
      &String.replace(&1, ~s|rx:transformerName "first"|, ~s|rx:transformerName "fi rst"|),
      "transformer",
      "INVALID_IDENTIFIER"
    )

    refuse!(
      &String.replace(&1, ~s|rx:addsAttribute "stamped_by"|, ~s|rx:addsAttribute "stamped by"|),
      "INVALID_IDENTIFIER"
    )
  end

  test "REFUSED: module name that is not an Elixir alias" do
    refuse!(
      &String.replace(
        &1,
        ~s|rx:moduleName "SchemaFixture.Receipted"|,
        ~s|rx:moduleName "schema fixture"|
      ),
      "INVALID_MODULE_NAME"
    )
  end

  test "REFUSED: duplicate field name in one entity" do
    refuse!(
      &(&1 <>
          """

          ex:FDupName a rx:Field ; rx:ofEntity ex:EntWitness ;
              rx:fieldName "weight" ; rx:fieldType "integer" .
          """),
      "DUPLICATE_FIELD_NAME"
    )
  end

  test "REFUSED: duplicate section name in one extension" do
    refuse!(
      &(&1 <>
          """

          ex:SecDup a rx:Section ; rx:inExtension ex:Target ; rx:sectionName "audit" .
          """),
      "DUPLICATE_SECTION_NAME"
    )
  end

  test "REFUSED: duplicate transformer name (typed, on the extension stem alone)" do
    refuse!(
      &(&1 <>
          """

          ex:TSeal2 a rx:Transformer ; rx:ofExtension ex:Target ; rx:transformerName "seal" .
          """),
      "DUPLICATE_TRANSFORMER_NAME"
    )

    refuse!(
      &(&1 <>
          """

          ex:TSeal2 a rx:Transformer ; rx:ofExtension ex:Target ; rx:transformerName "seal" .
          """),
      "transformer",
      "DUPLICATE_TRANSFORMER_NAME"
    )
  end

  test "REFUSED: duplicate arg position in one entity" do
    refuse!(
      &(&1 <>
          """

          ex:FDupPos a rx:Field ; rx:ofEntity ex:EntWitness ;
              rx:fieldName "other" ; rx:fieldType "atom" ; rx:argPosition 0 .
          """),
      "DUPLICATE_ARG_POSITION"
    )
  end

  test "REFUSED: primary entity not declared in data-driven mode (verifier stem too)" do
    refuse!(
      &String.replace(
        &1,
        ~s|rx:entityName "receipt" ;\n    rx:entityArg|,
        ~s|rx:entityName "nothing" ;\n    rx:entityArg|
      ),
      "extension",
      "PRIMARY_ENTITY_MISSING"
    )
  end

  test "a refused graph writes no .ex file (sync exits non-zero before actuation)" do
    ontology =
      graph!(
        &String.replace(
          &1,
          ~s|rx:fieldType "integer" ; rx:default "3"|,
          ~s|rx:fieldType "float" ; rx:default "3"|
        )
      )

    dir = PackCompile.tmp_project!(%{})

    {output, status} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "receipted-extension-pack:extension",
          "--engine",
          "sparql",
          "--ontology",
          ontology,
          "--out",
          Path.join(dir, "lib/schema_fixture/receipted.ex"),
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert status != 0, output
    assert output =~ "UNKNOWN_FIELD_TYPE"
    assert Path.wildcard(Path.join(dir, "**/*.ex")) == []
    PackCompile.cleanup(dir)
  end
end
