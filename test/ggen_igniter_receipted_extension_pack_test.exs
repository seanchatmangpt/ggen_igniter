defmodule GgenIgniter.ReceiptedExtensionPackTest do
  @moduledoc """
  Chicago-style: real `mix ggen_igniter.sync` subprocesses render
  `priv/ggen/receipted-extension-pack` into a real tmp dir; the real compiler
  builds the rendered Spark extension against the real ash + spark deps; and
  real Ash resources are compiled with and without a declared receipt.

  Consumer wiring: the pack also renders an `Igniter.Mix.Task` (`wire`) that calls
  `Spark.Igniter.has_extension/5` + `add_extension/6`; it is run through a real
  in-memory `Igniter.Test.test_project/1` against a fixture resource (test INPUT
  only), asserting `assert_has_patch` on the first run and `assert_unchanged` on the
  second. Falsifier for the guard: the rendered task with its `has_extension` guard
  stripped is run twice and the observed outcome is asserted.

  Falsifier: a resource using the extension with NO `receipted do receipt ... end`
  must fail compilation with a real `Spark.Error.DslError` (REFUSED_NO_RECEIPT).
  """

  use ExUnit.Case, async: false
  # async: false -- compiles modules into the global code server and shares Ash config.

  @pack "receipted-extension-pack"
  @pack_dir Path.expand("../priv/ggen/#{@pack}", __DIR__)
  @fixture Path.expand("fixtures/receipted-extension/consumer.ttl", __DIR__)
  @ext ReceiptedFixture.Receipted

  setup_all do
    dir = Path.join(System.tmp_dir!(), "receipted_ext_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    ontology = Path.join(dir, "consumer.ttl")

    File.write!(
      ontology,
      File.read!(Path.join(@pack_dir, "ontology.ttl")) <> "\n" <> File.read!(@fixture)
    )

    results =
      for {stem, out} <- [
            {"extension", "lib/receipted_fixture/receipted.ex"},
            {"verifier", "lib/receipted_fixture/receipted_verifier.ex"}
          ] do
        {output, exit} =
          System.cmd(
            "mix",
            [
              "ggen_igniter.sync",
              "--pack",
              "#{@pack}:#{stem}",
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

        {stem, exit, output, Path.join(dir, out)}
      end

    %{dir: dir, results: results}
  end

  defp compile_generated!(results) do
    paths = for {_, 0, _, path} <- results, do: path
    ebin = Path.join(System.tmp_dir!(), "receipted_ebin_#{System.unique_integer([:positive])}")
    File.mkdir_p!(ebin)
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      {:ok, _mods, %{compile_warnings: [], runtime_warnings: []}} =
        Kernel.ParallelCompiler.compile_to_path(paths, ebin, return_diagnostics: true)

      true = :code.add_patha(String.to_charlist(ebin))
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  # Spark verifiers run in the compiler's after-compile parallel checker, so a
  # refusal surfaces as a compile diagnostic (a hard failure under the
  # `--warnings-as-errors` bar every consumer build carries), not as a raise
  # from `Code.compile_string/2`. Returns `{modules, diagnostics}` from a real
  # `Kernel.ParallelCompiler` run over a real file.
  defp compile_resource(name, body) do
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

    dir = Path.join(System.tmp_dir!(), "receipted_res_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    # Elixir 1.18 (.tool-versions pin) does not create the output dir for compile_to_path/3.
    File.mkdir_p!(Path.join(dir, "ebin"))
    path = Path.join(dir, "resource.ex")
    File.write!(path, source)

    try do
      case Kernel.ParallelCompiler.compile_to_path([path], Path.join(dir, "ebin"),
             return_diagnostics: true
           ) do
        {:ok, modules, %{compile_warnings: cw, runtime_warnings: rw}} ->
          {:ok, modules,
           (cw ++ rw)
           |> Enum.map(&diagnostic_text/1)
           |> Enum.reject(&(&1 =~ "already been consolidated"))}

        {:error, errors, %{compile_warnings: cw, runtime_warnings: rw}} ->
          {:error, Enum.map(errors, &diagnostic_text/1),
           (cw ++ rw)
           |> Enum.map(&diagnostic_text/1)
           |> Enum.reject(&(&1 =~ "already been consolidated"))}
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp diagnostic_text(%{message: m}), do: to_string(m)
  defp diagnostic_text(other), do: inspect(other)

  test "rendering exits 0 and the extension appears only in rendered output", %{results: results} do
    for {stem, exit, output, path} <- results do
      assert exit == 0, "#{stem} render failed: #{output}"
      assert File.read!(path) =~ "GENERATED by receipted-extension-pack"
    end

    ext = results |> Enum.find(&(elem(&1, 0) == "extension")) |> elem(3) |> File.read!()
    assert ext =~ "use Spark.Dsl.Extension"

    # No hand-written `use Spark.Dsl.Extension` under lib/.
    hits =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ "use Spark.Dsl.Extension"))

    assert hits == []
  end

  test "resource WITH a receipt compiles; resource WITHOUT is refused", %{results: results} do
    compile_generated!(results)

    Application.put_env(:ash, :validate_domain_config_inclusion?, false)
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      assert {:ok, modules, []} =
               compile_resource("ReceiptedFixture.WithReceipt", """
                 receipted do
                   receipt :order_receipt
                 end
               """)

      assert ReceiptedFixture.WithReceipt in modules
      assert @ext.receipts(ReceiptedFixture.WithReceipt) == [:order_receipt]

      # The falsifier: no receipt declared -> the verifier's DslError is reported.
      {_status, _mods_or_errors, diagnostics} =
        case compile_resource("ReceiptedFixture.NoReceipt", "") do
          {:ok, m, d} -> {:ok, m, d}
          {:error, e, d} -> {:error, e, d ++ e}
        end

      assert Enum.any?(diagnostics, &(&1 =~ "REFUSED_NO_RECEIPT")),
             "resource with no receipt compiled clean: verifier is vacuous: #{inspect(diagnostics)}"

      assert Enum.any?(diagnostics, &(&1 =~ "Spark.Error.DslError")) or
               Enum.any?(diagnostics, &(&1 =~ "receipted"))
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
      Application.delete_env(:ash, :validate_domain_config_inclusion?)
    end
  end

  describe "wire task (consumer wiring)" do
    import ExUnit.CaptureIO
    import Igniter.Test

    @wire Mix.Tasks.ReceiptedFixture.Receipted.Wire
    @widget "ReceiptedFixture.Widget"
    @widget_src Path.expand("fixtures/receipted-extension/widget_resource.ex.txt", __DIR__)

    setup %{dir: dir} do
      out = Path.join(dir, "lib/mix/tasks/receipted_fixture.receipted.wire.ex")

      {output, exit} =
        System.cmd(
          "mix",
          [
            "ggen_igniter.sync",
            "--pack",
            "#{@pack}:wire",
            "--ontology",
            Path.join(dir, "consumer.ttl"),
            "--out",
            out,
            "--manifest-dir",
            dir,
            "--verify-cwd",
            File.cwd!()
          ],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert exit == 0, "wire render failed: #{output}"

      on_exit(fn ->
        :code.purge(@wire)
        :code.delete(@wire)
      end)

      %{wire_source: File.read!(out), wire_path: out}
    end

    defp load_task!(source, path) do
      previous = Code.get_compiler_option(:ignore_module_conflict)
      Code.put_compiler_option(:ignore_module_conflict, true)

      try do
        compiled = Code.compile_string(source, path)
        assert Enum.any?(compiled, fn {m, _} -> m == @wire end)
      after
        Code.put_compiler_option(:ignore_module_conflict, previous)
      end
    end

    defp widget_project do
      Igniter.Test.test_project(
        app_name: :receipted_fixture,
        files: %{"lib/receipted_fixture/widget.ex" => File.read!(@widget_src)}
      )
    end

    defp compose(igniter, argv \\ []) do
      parent = self()

      capture_io(:stderr, fn ->
        capture_io(fn -> send(parent, {:ig, Igniter.compose_task(igniter, @wire, argv)}) end)
      end)

      receive do
        {:ig, result} -> result
      after
        5_000 -> flunk("timed out composing wire task")
      end
    end

    @path "lib/receipted_fixture/widget.ex"

    test "renders from facts and calls the Spark.Igniter APIs", %{wire_source: src} do
      assert src =~ "GENERATED by receipted-extension-pack"
      assert src =~ "use Igniter.Mix.Task"
      assert src =~ "Spark.Igniter.has_extension("
      assert src =~ "Spark.Igniter.add_extension("
      assert src =~ "@extension ReceiptedFixture.Receipted"
      assert src =~ "@default_resource ReceiptedFixture.Widget"
      assert src =~ "GgenIgniter.TaskShell.run_with_help("
      refute src =~ ~r/^\s*use Ash\.Resource/m
    end

    test "first run adds the extension; second run is inert", %{
      wire_source: src,
      wire_path: path
    } do
      load_task!(src, path)
      first = compose(widget_project())

      assert_has_patch(first, @path, """
      + |    extensions: [ReceiptedFixture.Receipted]
      """)

      applied = apply_igniter!(first)
      second = compose(applied)
      assert_unchanged(second)
      assert second.issues == [], "issues: #{inspect(second.issues)}"

      content = second.rewrite |> Rewrite.source!(@path) |> Rewrite.Source.get(:content)
      assert length(Regex.scan(~r/ReceiptedFixture\.Receipted/, content)) == 1
    end

    test "--resource overrides the fact-derived default", %{wire_source: src, wire_path: path} do
      load_task!(src, path)
      # The override is honored: the task targets the named module (which does not exist
      # in the project) instead of the fact-derived default (which does).
      assert_raise RuntimeError, ~r/Could not find module ReceiptedFixture.Nope/, fn ->
        compose(widget_project(), ["--resource", "ReceiptedFixture.Nope"])
      end

      assert @widget == "ReceiptedFixture.Widget"
    end

    test "falsifier: mutated fact -> different rendered constants", %{dir: dir} do
      mutated = Path.join(dir, "mutated.ttl")

      File.write!(
        mutated,
        File.read!(Path.join(dir, "consumer.ttl"))
        |> String.replace("ReceiptedFixture.Widget", "ReceiptedFixture.Gadget")
      )

      out = Path.join(dir, "m/lib/mix/tasks/mutated_wire.ex")

      {_o, 0} =
        System.cmd(
          "mix",
          [
            "ggen_igniter.sync",
            "--pack",
            "#{@pack}:wire",
            "--ontology",
            mutated,
            "--out",
            out,
            "--manifest-dir",
            Path.join(dir, "m"),
            "--verify-cwd",
            File.cwd!()
          ],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert File.read!(out) =~ "@default_resource ReceiptedFixture.Gadget"
    end

    test "falsifier: guard polarity is load-bearing; unguarded add_extension is itself idempotent",
         %{wire_source: src, wire_path: path} do
      # (a) Inverted guard (`unless present?`): the first run must NOT wire the extension,
      # so the guard is exercised by the real first-run assertion above (non-vacuous).
      inverted = String.replace(src, "if present? do", "if not present? do")
      refute inverted == src
      load_task!(inverted, path)
      first = compose(widget_project())
      content = first.rewrite |> Rewrite.source!(@path) |> Rewrite.Source.get(:content)
      refute content =~ "ReceiptedFixture.Receipted"

      # (b) Guard removed entirely: observed outcome after two runs. Spark's
      # add_extension prepends only when absent, so the count stays 1 -- the guard is a
      # defensive fast path, not the sole duplicate barrier (recorded, not assumed).
      unguarded =
        String.replace(
          src,
          ~r/    \{igniter, present\?\} =\n.*?\n\n    if present\? do\n      igniter\n    else\n(.*?)\n    end\n/s,
          "\\1\n"
        )

      refute unguarded =~ "has_extension("
      assert unguarded =~ "add_extension("
      load_task!(unguarded, path)
      again = widget_project() |> compose() |> apply_igniter!() |> compose()
      content2 = again.rewrite |> Rewrite.source!(@path) |> Rewrite.Source.get(:content)
      assert length(Regex.scan(~r/ReceiptedFixture\.Receipted/, content2)) == 1
    end
  end
end
