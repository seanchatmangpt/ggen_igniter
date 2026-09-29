defmodule GgenIgniter.DryRunYesTest do
  @moduledoc """
  Chicago-style contract test for the Igniter installer write discipline: WITHOUT `--yes`
  (dry run, or a prompt that is never confirmed because stdin is `/dev/null`) an installer
  writes NOTHING; WITH `--yes` it writes, and a second `--yes` run changes nothing more.

  (`.formatter.exs` is hashed too; the consumer does not list `:ggen_igniter` in deps, so the
  thin default path leaves it untouched and emits a notice instead.)

  Real collaborators: a real OS subprocess (`elixir -pa <this build's ebin dirs>`, cwd = a
  real tmp Mix project, stdin `/dev/null`) runs the real `Mix.Tasks.GgenIgniter.Install`;
  assertions are `sha256` of the real `mix.exs` / `.formatter.exs` bytes. No doubles.

  Falsifier (a deliberately non-conforming installer): the `igniter-installer-pack` renders a
  real installer from `test/fixtures/installer-pack/badlib.ttl`; the test then mutates its
  rendered `igniter/1` to perform a raw `File.write!` (bypassing Igniter's rewrite/diff
  machinery), compiles it with the real compiler, and proves the SAME contract assertion
  fails for it (`ExUnit.AssertionError`) while passing for the unmutated render.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 600_000

  alias GgenIgniter.Test.PackCompile

  @mix_exs """
  defmodule Consumer.MixProject do
    use Mix.Project

    def project, do: [app: :consumer, version: "0.1.0", deps: deps()]
    def application, do: [mod: {Consumer.Application, []}]

    defp deps, do: []
  end
  """

  @app """
  defmodule Consumer.Application do
    use Application

    def start(_type, _args) do
      children = []
      Supervisor.start_link(children, strategy: :one_for_one, name: Consumer.Supervisor)
    end
  end
  """

  defp consumer! do
    dir =
      PackCompile.tmp_project!(%{
        "mix.exs" => @mix_exs,
        ".formatter.exs" =>
          "[inputs: [\"{mix,.formatter}.exs\", \"{config,lib,test}/**/*.{ex,exs}\"]]\n",
        "lib/consumer/application.ex" => @app
      })

    on_exit(fn -> PackCompile.cleanup(dir) end)
    dir
  end

  defp ebins do
    Path.wildcard(Path.join(Path.expand(Mix.Project.build_path()), "lib/*/ebin"))
  end

  # Runs `Mix.Task.run(task, argv)` in a real subprocess with cwd = dir, stdin = /dev/null.
  defp run_task(dir, task, argv, extra_ebins \\ []) do
    pa = Enum.flat_map(ebins() ++ extra_ebins, &["-pa", &1])
    # `Mix.Task.run("compile")` (which Igniter's run/1 also triggers) resets the code path
    # to the consumer's build; the script re-prepends the ebins after compiling.

    script =
      "Mix.start(); " <>
        "defmodule ConsumerProject do use Mix.Project; def project, do: [app: :consumer, version: \"0.1.0\"] end; " <>
        "paths = :code.get_path(); Mix.Task.run(\"compile\"); " <>
        "Enum.each(Enum.reverse(paths), &Code.prepend_path/1); " <>
        "{:ok, _} = Application.ensure_all_started(:igniter); " <>
        "Mix.Task.run(#{inspect(task)}, #{inspect(argv)})"

    cmd = Enum.map_join(["elixir"] ++ pa ++ ["-e", script], " ", &shell_quote/1) <> " </dev/null"

    System.cmd("sh", ["-c", cmd],
      cd: dir,
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}, {"MIX_BUILD_ROOT", nil}, {"MIX_BUILD_PATH", nil}]
    )
  end

  defp shell_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  defp sha(dir, file),
    do: :crypto.hash(:sha256, File.read!(Path.join(dir, file))) |> Base.encode16(case: :lower)

  defp hashes(dir), do: Map.new(["mix.exs", ".formatter.exs"], &{&1, sha(dir, &1)})

  # The contract. Returns :ok or raises ExUnit.AssertionError.
  defp assert_dry_run_writes_nothing(dir, task, argv, extra \\ []) do
    before = hashes(dir)
    {_out, _status} = run_task(dir, task, argv ++ ["--dry-run"], extra)
    assert hashes(dir) == before, "dry run (--dry-run) modified the project"
    {_out, _status} = run_task(dir, task, argv, extra)
    assert hashes(dir) == before, "run without --yes modified the project"
    :ok
  end

  test "ggen_igniter.install: no write without --yes; --yes writes; second --yes is stable" do
    dir = consumer!()
    argv = ["--with-ash-domain", "--domain", "Consumer.Ash.Domain"]

    before = hashes(dir)
    assert_dry_run_writes_nothing(dir, "ggen_igniter.install", argv)

    {out, status} = run_task(dir, "ggen_igniter.install", argv ++ ["--yes"])
    assert status == 0, out

    after_yes = hashes(dir)
    assert after_yes["mix.exs"] != before["mix.exs"], out
    assert File.read!(Path.join(dir, "mix.exs")) =~ ":ash"
    assert File.read!(Path.join(dir, "config/config.exs")) =~ "Consumer.Ash.Domain"

    {out, status} = run_task(dir, "ggen_igniter.install", argv ++ ["--yes"])
    assert status == 0, out
    assert hashes(dir) == after_yes, "second --yes run changed the project again"
  end

  describe "falsifier: a non-conforming generated installer" do
    setup do
      rendered =
        PackCompile.render!("igniter-installer-pack:installer",
          ontology: "test/fixtures/installer-pack/badlib.ttl",
          out: "lib/<%= installer_id %>.ex"
        )

      [file] = Enum.filter(rendered.files, &String.ends_with?(&1, ".ex"))
      on_exit(fn -> PackCompile.cleanup(rendered.out_dir) end)
      %{source: File.read!(file)}
    end

    defp compile_variant(source, rename_to) do
      path = Path.join(System.tmp_dir!(), "#{rename_to}_#{System.unique_integer([:positive])}.ex")

      File.write!(
        path,
        String.replace(source, "Mix.Tasks.Badlib.Install", "Mix.Tasks.#{rename_to}")
      )

      modules = PackCompile.compile!([path])
      File.rm!(path)
      on_exit(fn -> PackCompile.purge(modules) end)
      [m | _] = modules
      Path.dirname(:code.which(m) |> List.to_string())
    end

    test "conforming render passes the contract", %{source: source} do
      ebin = compile_variant(source, "Badlib.Conforming")
      dir = consumer!()
      assert :ok = assert_dry_run_writes_nothing(dir, "badlib.conforming", [], [ebin])

      {out, 0} = run_task(dir, "badlib.conforming", ["--yes"], [ebin])
      refute hashes(dir)["mix.exs"] == sha_of(@mix_exs), out
    end

    test "raw File.write! in igniter/1 violates the contract", %{source: source} do
      mutated =
        String.replace(
          source,
          "def igniter(igniter) do\n",
          "def igniter(igniter) do\n    File.write!(\"mix.exs\", File.read!(\"mix.exs\") <> \"\\n# raw\\n\")\n"
        )

      refute mutated == source
      ebin = compile_variant(mutated, "Badlib.Raw")
      dir = consumer!()

      assert_raise ExUnit.AssertionError, ~r/modified the project/, fn ->
        assert_dry_run_writes_nothing(dir, "badlib.raw", [], [ebin])
      end
    end
  end

  defp sha_of(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
end
