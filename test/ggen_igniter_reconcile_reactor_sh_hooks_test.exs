defmodule GgenIgniter.ReconcileReactorShHooksTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `sh_before:`/`sh_after:` frontmatter
  fields are real against `GgenIgniter.Reactors.ReconcileReactor.run/1` --
  the SEPARATE call path from `Mix.Tasks.GgenIgniter.Sync`'s own inline
  `run_pipeline!/3` (covered in `test/ggen_igniter_sync_sh_hooks_test.exs`).
  Every collaborator is real: a real minimal scratch Mix project, a real
  `mix compile --warnings-as-errors` subprocess for `:verify`, a real
  `GgenIgniter.ShellHook.run/3` subprocess for the hook itself, and a real,
  persisted `GgenIgniter.Receipt` read back off disk.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_sh_hooks_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "reactor_sh_hooks_fixture_#{System.unique_integer([:positive])}"

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
    @prefix ex: <http://example.org/rri#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterReactorShHooksFixture.Alpha" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rri#>
    SELECT ?module_name WHERE {
      ex:Alpha ex:moduleName ?module_name .
    }
    """)

    path
  end

  defp write_template!(dir, sh_field, cmd) do
    path = Path.join(dir, "sh_template.ex.eex")

    File.write!(path, """
    ---
    to: "unused_-_out_is_always_explicit.ex"
    #{sh_field}: "#{cmd}"
    ---
    defmodule <%= module_name %> do
      def ok, do: true
    end
    """)

    path
  end

  describe "sh_after: without allow_sh" do
    test "refuses the whole reconciliation before any actuation -- real :refused standing" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_template!(fixtures, "sh_after", "touch sh_after_reactor.marker")

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "out.ex"])
      marker = Path.join(project_dir, "sh_after_reactor.marker")

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :refused
      assert receipt.reason =~ "allow_sh"

      refute File.exists?(out_path)
      refute File.exists?(marker)
    end
  end

  describe "sh_after: with allow_sh: true (real success)" do
    test "runs the real command after a real write, populates real Receipt.commands, real :alive standing" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_template!(fixtures, "sh_after", "touch sh_after_reactor.marker")

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "out.ex"])
      marker = Path.join(project_dir, "sh_after_reactor.marker")

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        allow_sh: true
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive

      assert File.exists?(out_path)
      assert File.read!(out_path) =~ "defmodule GgenIgniterReactorShHooksFixture.Alpha"
      # The real `touch` command genuinely ran, cd:'d into --manifest-dir
      # (`project_dir` here).
      assert File.exists?(marker)

      assert [command] = receipt.commands
      assert command["kind"] == "sh_after"
      assert command["cmd"] == "touch sh_after_reactor.marker"
      assert command["status"] == "ok"
      assert command["exit_code"] == 0

      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "alive"
      assert [persisted_command] = persisted["commands"]
      assert persisted_command["kind"] == "sh_after"
    end
  end

  describe "sh_after: real nonzero exit is treated as an ordinary actuation failure" do
    test "the whole run self-heals (compensated), the write is reverted, real :compensated standing" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_template!(fixtures, "sh_after", "exit 9")

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "out.ex"])
      refute File.exists?(out_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        allow_sh: true
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :compensated
      assert receipt.reason =~ "sh_after"

      # Self-healed: the real write that happened before the failing
      # sh_after ran is reverted -- this pipeline's atomic all-or-nothing
      # `:actuate` step, unchanged from before this feature existed.
      refute File.exists?(out_path)
    end
  end
end
