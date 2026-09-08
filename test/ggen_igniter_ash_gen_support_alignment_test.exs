defmodule GgenIgniter.AshGenSupportAlignmentTest do
  @moduledoc """
  Chicago-style: drives the REAL upstream Ash support-module generators
  (`Mix.Tasks.Ash.Gen.Change`, `.Validation`, `.Preparation`,
  `.CustomExpression` from `deps/ash`) through `Igniter.Test`'s in-memory
  project. No mocks, no scaffolded app, no subprocess — `Igniter.compose_task/3`
  invokes the same task modules a consumer's `mix ash.gen.change` invokes, and
  every assertion here reads real resulting state: created-file content, the
  real `igniter.issues` list, the real return of
  `Igniter.Project.Module.module_exists/2`, and the real result of compiling the
  emitted source with `Code.compile_string/1`.

  ## The property under test, and why it is the right one

  ggen_igniter renders ONE composed `Igniter.Mix.Task` from an ontology and that
  task calls these upstream generators. So ggen_igniter inherits their
  re-run semantics wholesale. Three of these four generators
  (`ash.gen.change`, `ash.gen.validation`, `ash.gen.preparation`) declare
  `schema: []` and call `Igniter.Project.Module.create_module/3` unconditionally
  — `create_module/3` delegates to `Igniter.create_new_file/3`, whose
  `on_exists:` default is `:error`. There is no existence guard and no
  `--ignore-if-exists` escape hatch (unlike `ash.gen.enum` and
  `ash.gen.resource`, which declare `ignore_if_exists: :boolean`). Composing one
  of them a second time therefore produces a hard
  `"<path>: File already exists"` issue and zero changes.

  That is precisely what justifies an admission guard in ggen_igniter keyed on
  `Igniter.Project.Module.module_exists/2`: a re-`sync` of an unchanged ontology
  must not turn into an issue-laden no-op run. So the guard is only sound if the
  signal it reads is real, and that is asserted here too — `module_exists/2` on
  the applied project returns `{true, igniter}` for a module the generator just
  created and `{false, igniter}` for one it did not. Without the negative
  control, `true` would carry no information and a guard built on it would
  refuse everything.

  `ash.gen.custom_expression` is a different, sharper failure: it *emits*
  source that cannot compile. Its template writes `args:` into
  `use Ash.CustomExpression`, but `Ash.CustomExpression.__using__/1`
  (`deps/ash/lib/ash/custom_expression.ex:113-115`) raises unless `opts[:arguments]`
  is set. This file converts that refusal from a claim into an executed test:
  the generated source is really compiled and really raises, and the same source
  with the single key swapped really compiles and really answers `arguments/0`.
  """
  # `async: true` is safe despite the real `Code.compile_string/1` calls below:
  # every module name is uniquified (see `unique_module/1`), so no two
  # concurrently-running tests can define or redefine the same module.
  use ExUnit.Case, async: true

  import Igniter.Test

  # The three structurally identical support generators. `use_line` and the
  # `callbacks` are upstream CONTRACT strings (the exact behaviour a consumer
  # gets and the exact callback heads the template emits) — Faker-generating
  # them would make the assertion vacuous. Only the module NAMES are generated.
  @support_generators [
    %{
      task: "ash.gen.change",
      use_line: "use Ash.Resource.Change",
      callbacks: ["def init(opts) do", "def change(changeset, _opts, _context) do"]
    },
    %{
      task: "ash.gen.validation",
      use_line: "use Ash.Resource.Validation",
      callbacks: ["def init(opts) do", "def validate(_changeset, _opts, _context) do"]
    },
    %{
      task: "ash.gen.preparation",
      use_line: "use Ash.Resource.Preparation",
      callbacks: ["def init(opts) do", "def prepare(query, _opts, _context) do"]
    }
  ]

  # Upstream's own raise text, read from deps/ash/lib/ash/custom_expression.ex.
  # A literal because the point of the assertion is that THIS refusal (missing
  # `arguments`) is the one that fires, not merely that something raised.
  @custom_expression_raise "You must provide arguments for the custom expression"

  for generator <- @support_generators do
    describe "#{generator.task} (support-module generator, no existence guard)" do
      @generator generator

      test "creates a real module carrying the use line and both behaviour callbacks" do
        igniter = test_project()
        module = unique_module(igniter)
        path = Igniter.Project.Module.proper_location(igniter, module)

        igniter
        |> Igniter.compose_task(@generator.task, [inspect(module)])
        |> assert_creates(path, fn content ->
          assert content =~ "defmodule #{inspect(module)} do"
          assert content =~ @generator.use_line

          for callback <- @generator.callbacks do
            assert content =~ callback
          end
        end)
      end

      test "re-composing over the applied project adds a real File already exists issue" do
        base = test_project()
        module = unique_module(base)
        path = Igniter.Project.Module.proper_location(base, module)
        argv = [inspect(module)]

        rerun =
          base
          |> Igniter.compose_task(@generator.task, argv)
          |> apply_igniter!()
          |> Igniter.compose_task(@generator.task, argv)

        # The issue string embeds the path, so an exact-binary match pins both
        # WHICH file collided and WHAT the generator did about it.
        assert_has_issue(rerun, "#{path}: File already exists")

        # Pinning the count keeps this from passing on some unrelated future
        # issue, and `changed?` pins that the second run is inert rather than
        # partially applied.
        assert length(rerun.issues) == 1
        refute Igniter.changed?(rerun)
      end

      test "module_exists/2 gives an admission guard a real, discriminating signal" do
        base = test_project()
        generated = unique_module(base)
        never_generated = unique_module(base)

        applied =
          base
          |> Igniter.compose_task(@generator.task, [inspect(generated)])
          |> apply_igniter!()

        assert {true, %Igniter{}} = Igniter.Project.Module.module_exists(applied, generated)

        # Negative control: without this, a `module_exists/2` that answered
        # `true` unconditionally would satisfy the assertion above, and a guard
        # built on it would refuse every generation instead of just the
        # colliding one.
        assert {false, %Igniter{}} =
                 Igniter.Project.Module.module_exists(applied, never_generated)
      end
    end
  end

  describe "ash.gen.custom_expression (emits source that cannot compile)" do
    test "creates a real module wired to Ash.CustomExpression with the derived name" do
      igniter = test_project()
      module = unique_module(igniter)
      path = Igniter.Project.Module.proper_location(igniter, module)
      name = expression_name(module)

      igniter
      |> Igniter.compose_task("ash.gen.custom_expression", custom_expression_argv(module))
      |> assert_creates(path, fn content ->
        assert content =~ "defmodule #{inspect(module)} do"
        assert content =~ "use Ash.CustomExpression"
        assert content =~ "name: :#{name}"
        assert content =~ "def expression(_data_layer, args) do"
      end)
    end

    test "re-composing over the applied project adds a real File already exists issue" do
      base = test_project()
      module = unique_module(base)
      path = Igniter.Project.Module.proper_location(base, module)
      argv = custom_expression_argv(module)

      rerun =
        base
        |> Igniter.compose_task("ash.gen.custom_expression", argv)
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.custom_expression", argv)

      assert_has_issue(rerun, "#{path}: File already exists")
      assert length(rerun.issues) == 1
      refute Igniter.changed?(rerun)
    end

    test "module_exists/2 gives an admission guard a real, discriminating signal" do
      base = test_project()
      generated = unique_module(base)
      never_generated = unique_module(base)

      applied =
        base
        |> Igniter.compose_task("ash.gen.custom_expression", custom_expression_argv(generated))
        |> apply_igniter!()

      assert {true, %Igniter{}} = Igniter.Project.Module.module_exists(applied, generated)
      assert {false, %Igniter{}} = Igniter.Project.Module.module_exists(applied, never_generated)
    end

    test "emitted source uses args:, never arguments:, and really fails to compile" do
      {module, content} = generate_custom_expression()

      # `args:` and `arguments:` are the two upstream CONTRACT keys whose
      # mismatch IS the defect, so both stay literal. Neither is a substring of
      # the other, so `refute` here is a real discriminator.
      assert content =~ "args:"
      refute content =~ "arguments:"

      # Compiling the emitted source is the whole point: a substring assertion
      # alone would only show the template disagrees with the docs, not that a
      # consumer's build actually breaks.
      assert_raise ArgumentError, @custom_expression_raise, fn ->
        Code.compile_string(content)
      end

      # The raise happens inside `__using__`, so the module is never defined —
      # which is why the failure surfaces as a build break in the consuming
      # project rather than as an igniter issue this task could report.
      refute Code.ensure_loaded?(module)
    end

    test "swapping the single key args: -> arguments: makes the same source compile" do
      {module, content} = generate_custom_expression()
      corrected = String.replace(content, "args:", "arguments:")

      # `Code.compile_string/1` emits an "unused variable args" warning here.
      # That comes from the template's own `def expression(_data_layer, args)`
      # body and is orthogonal to the key defect under test; capturing stderr
      # would force this file to `async: false`, which is a worse trade.
      assert [{^module, bytecode}] = Code.compile_string(corrected)
      assert is_binary(bytecode)

      # State-based proof that the one-key fix is complete and not merely
      # silent: the compiled module really answers the behaviour's callbacks
      # with the values the generator was asked for.
      assert module.arguments() == [:string, :string]
      assert module.name() == String.to_atom(expression_name(module))
    end
  end

  # Faker supplies the semantic content of every module name so no assertion in
  # this file can pass on a hardcoded coincidence; the unique integer supplies a
  # collision guarantee Faker cannot make (two `Faker.Lorem.word/0` calls do
  # repeat within one run, and a repeat would make two independent tests fight
  # over one module name in the shared VM).
  defp unique_module(igniter) do
    Module.concat([
      Igniter.Project.Module.module_name_prefix(igniter),
      unique_segment(),
      unique_segment()
    ])
  end

  defp unique_segment do
    Macro.camelize(Faker.Lorem.word()) <> to_string(System.unique_integer([:positive]))
  end

  # `--args` is the upstream CLI flag name and `string` an Ash type name: both
  # are contract, not test data, so Faker would make the argv meaningless.
  defp custom_expression_argv(module), do: [inspect(module), "--args", "string,string"]

  # Mirrors `Mix.Tasks.Ash.Gen.CustomExpression.fetch_name/2`: with no `--name`,
  # the expression name is the underscored last segment of the module.
  defp expression_name(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp generate_custom_expression do
    base = test_project()
    module = unique_module(base)
    path = Igniter.Project.Module.proper_location(base, module)

    content =
      base
      |> Igniter.compose_task("ash.gen.custom_expression", custom_expression_argv(module))
      |> Map.fetch!(:rewrite)
      |> Rewrite.source!(path)
      |> Rewrite.Source.get(:content)

    {module, content}
  end
end
