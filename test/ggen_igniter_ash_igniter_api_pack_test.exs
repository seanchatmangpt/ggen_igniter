defmodule GgenIgniter.AshIgniterApiPackTest do
  @moduledoc """
  Chicago-style: renders `priv/ggen/ash-igniter-api-pack` with a real
  `mix ggen_igniter.sync` subprocess (real oxigraph engine, real file on disk),
  compiles the rendered `Igniter.Mix.Task` with `Code.compile_string/2`, and
  composes it against a real in-memory `Igniter.Test.test_project/1` running the
  real upstream `ash.gen.domain`, `ash.gen.resource`, `Ash.Resource.Igniter.add_new_*`
  and `Ash.Domain.Igniter.add_resource_reference` code. Assertions are on the
  resulting resource/domain source state. No doubles.

  Falsifiers: (1) running the rendered task twice must leave the applied project
  unchanged (idempotence); (2) removing an ontology fact and re-rendering must
  make the regenerated task stop adding that attribute; (3) the rendered task
  must actually call the structural APIs and compose `ash.gen.resource` once.
  """
  use ExUnit.Case, async: false
  # async: false -- compiles a module with a fixed name into the shared VM and
  # shells `mix` subprocesses.

  import ExUnit.CaptureIO
  import Igniter.Test

  @moduletag :integration
  # Each render is a real `mix` subprocess (cold compile on first use).
  @moduletag timeout: 1_200_000

  @pack "priv/ggen/ash-igniter-api-pack"
  @task Mix.Tasks.Shop.Manufacture.Book
  @resource Shop.Catalog.Book
  @domain Shop.Catalog

  setup do
    dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_aia_#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      :code.purge(@task)
      :code.delete(@task)
    end)

    %{dir: dir}
  end

  describe "render" do
    test "renders one Igniter.Mix.Task that calls the structural APIs", %{dir: dir} do
      source = render!(@pack, dir)

      assert source =~ "use Igniter.Mix.Task"
      for fun <- ~w(add_new_attribute add_new_action add_new_relationship
                    add_new_identity add_new_calculation),
          do: assert(source =~ "Ash.Resource.Igniter.#{fun}/4")

      assert source =~ "Ash.Domain.Igniter.add_resource_reference"
      # ash.gen.resource composed exactly once
      assert length(Regex.scan(~r/Igniter\.compose_task\("ash\.gen\.resource"/, source)) == 1
      refute source =~ "System.cmd"
      refute source =~ "use Ash.Resource"
    end

    test "facts/0 reflects the ontology", %{dir: dir} do
      compile!(render!(@pack, dir), dir)
      facts = apply(@task, :facts, [])
      assert facts.attributes == [:title, :isbn, :pages]
      assert facts.actions == [:register, :revise, :by_isbn]
      assert facts.relationships == [:author]
      assert facts.identities == [:unique_isbn]
      assert facts.calculations == [:title_length]
      assert length(facts.policies) == 1
    end
  end

  describe "run against a real Igniter project" do
    test "creates the resource with every ontology fact and references it in the domain",
         %{dir: dir} do
      compile!(render!(@pack, dir), dir)
      first = run(test_project(app_name: :shop))
      path = Igniter.Project.Module.proper_location(first, @resource)

      assert_creates(first, path, fn content ->
        assert content =~ "defmodule Shop.Catalog.Book do"
      end)

      content = content(first, path)
      assert content =~ "attribute(:title, :string"
      assert content =~ "allow_nil?: false"
      assert content =~ "attribute(:isbn, :string"
      assert content =~ "attribute(:pages, :integer"
      assert content =~ "create :register"
      assert content =~ "accept([:title, :isbn, :pages])"
      assert content =~ "update :revise"
      assert content =~ "read :by_isbn do"
      assert content =~ "belongs_to(:author, Shop.Catalog.Author"
      assert content =~ "identity(:unique_isbn, [:isbn])"
      assert content =~ "calculate(:title_length, :integer, expr(string_length(title)))"
      assert content =~ "policy(action_type(:read))"
      assert content =~ "authorize_if(always())"

      domain_path = Igniter.Project.Module.proper_location(first, @domain)
      assert content(first, domain_path) =~ "resource(Shop.Catalog.Book)"
    end

    test "second run is inert (idempotence)", %{dir: dir} do
      compile!(render!(@pack, dir), dir)
      applied = test_project(app_name: :shop) |> run() |> apply_igniter!()
      second = run(applied)

      assert_unchanged(second)
      assert second.tasks == []
      assert second.issues == [], "issues: #{inspect(second.issues)}"
      assert second.warnings == [], "warnings: #{inspect(second.warnings)}"
    end

    test "removing an ontology fact stops the regenerated task adding that attribute",
         %{dir: dir} do
      full = Path.join(dir, "full")
      variant = Path.join(dir, "variant")
      File.mkdir_p!(full)
      File.mkdir_p!(variant)

      File.cp_r!(@pack, variant)
      ttl = Path.join(variant, "ontology.ttl")

      stripped =
        ttl
        |> File.read!()
        |> String.replace(~r/aia:attrPages a aia:Attribute ;.*?aia:order 3 \.\n/s, "")
        |> String.replace("\"title,isbn,pages\"", "\"title,isbn\"")
        |> String.replace("\"title,pages\"", "\"title\"")

      refute stripped =~ "aia:attrPages"
      File.write!(ttl, stripped)

      compile!(render!(@pack, full), full)
      with_fact = test_project(app_name: :shop) |> run()
      path = Igniter.Project.Module.proper_location(with_fact, @resource)
      assert content(with_fact, path) =~ "attribute(:pages, :integer"

      compile!(render!(variant, variant <> "_out"), variant <> "_out")
      assert apply(@task, :facts, []).attributes == [:title, :isbn]

      without_fact = test_project(app_name: :shop) |> run()
      refute content(without_fact, path) =~ ":pages"
      assert content(without_fact, path) =~ "attribute(:isbn, :string"
    end

    test "run adds only missing members to an existing resource", %{dir: dir} do
      compile!(render!(@pack, dir), dir)
      applied = test_project(app_name: :shop) |> run() |> apply_igniter!()
      path = Igniter.Project.Module.proper_location(applied, @resource)
      before = content(applied, path)

      again = run(applied)
      assert_unchanged(again, path)
      assert content(again, path) == before
      assert length(Regex.scan(~r/attribute\(:title/, before)) == 1
      assert length(Regex.scan(~r/policy\(action_type/, before)) == 1
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp render!(pack, dir) do
    File.mkdir_p!(dir)
    out = Path.join(dir, "task.ex")

    {output, code} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack-dir",
          pack,
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

    assert code == 0, "sync failed:\n#{output}"
    assert File.exists?(out), "sync wrote nothing:\n#{output}"
    File.read!(out)
  end

  defp compile!(source, dir) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      compiled = Code.compile_string(source, Path.join(dir, "task.ex"))
      assert Enum.any?(compiled, fn {m, _} -> m == @task end)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  defp run(igniter) do
    parent = self()

    capture_io(:stderr, fn ->
      capture_io(fn -> send(parent, {:igniter, Igniter.compose_task(igniter, @task, [])}) end)
    end)

    receive do
      {:igniter, result} -> result
    after
      5_000 -> raise "timed out waiting for compose_task"
    end
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end
end
