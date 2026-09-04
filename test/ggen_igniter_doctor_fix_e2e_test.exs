defmodule GgenIgniter.DoctorFixE2eTest do
  @moduledoc """
  Real, no-mocks end-to-end proof that `mix ggen_igniter.doctor --fix` runs
  as a real subprocess against a real, freshly-scaffolded consumer project
  and applies a real fix to that project's own `config/config.exs` --
  complementing `test/ggen_igniter_doctor_fixes_test.exs`'s direct,
  fast, in-process tests of the same underlying `GgenIgniter.DoctorFixes`
  functions.

  ## Why this covers fix 3 (`config :dcatr, env: ...`) specifically

  A real, investigated constraint (confirmed directly against this Mix
  version, 2026-08-27) rules out an *equivalent* live subprocess test for
  fixes 1/2 (the `igniter`/`sourceror` `:only` relaxation): once a real
  `:only` mismatch is actually present in a project's `mix.exs` (the
  consumer's own direct dep restricted, `ggen_igniter`'s own transitive
  requirement unrestricted), Mix's dependency-graph loader refuses to run
  **any** task at all -- including `mix ggen_igniter.doctor` itself --
  with its own native "Dependencies have diverged ... Remove the :only
  restriction from your dep" error, before `Mix.Tasks.GgenIgniter.Doctor`
  ever gets a chance to run. Verified directly: a real fixture project with
  `{:igniter, "~> 0.8", only: [:dev, :test]}` alongside a real
  `{:ggen_igniter, path: ...}` dependency fails `mix ggen_igniter.doctor`
  (no `--fix` even reached) with exactly that Mix-native error, in both
  `MIX_ENV=dev` and `MIX_ENV=prod`. That fix's real logic is instead
  covered exhaustively (7 cases, including the exact restricted line this
  session hit and the "preserve other options"/"idempotent"/"raises on an
  unrecognized shape" cases) by direct function calls in
  `ggen_igniter_doctor_fixes_test.exs` -- the only way to exercise it
  without needing Mix to have already tolerated the very state under test.

  Fix 3 (this file) has no such blocker: a *missing* `config :dcatr, env:
  ...` only raises inside `:gno`'s own compile step (`Gno.Store.Adapters
  .Fuseki`, which reads `DCATR.Manifest.env/1`), not in Mix's dependency
  *graph* loading -- and that raise itself is worked around for this real
  fixture by exporting `MIX_ENV` as an OS env var (`DCATR.Manifest.env/1`'s
  own documented fallback), letting the fixture compile once, cleanly, so
  `mix ggen_igniter.doctor --fix` (a real subsequent invocation) can run for
  real and add the missing config for real.
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  # Real `mix deps.get` (network) + a real path-dependency compile of
  # ggen_igniter itself -- genuinely slower than the rest of the suite.
  @moduletag timeout: 300_000

  @ggen_igniter_path Path.expand("..", __DIR__)

  defp cmd!(command, args, opts) do
    case System.cmd(command, args, Keyword.merge([stderr_to_stdout: true], opts)) do
      {output, 0} ->
        output

      {output, exit_status} ->
        raise RuntimeError, """
        command failed: #{command} #{Enum.join(args, " ")} (exit #{exit_status})

        #{output}
        """
    end
  end

  defp scaffold_fixture!() do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_doctor_fix_e2e_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "config"))

    # A real, minimal Mix project: `:igniter`/`:sourceror` declared
    # UNRESTRICTED (matching ggen_igniter's own unconditional requirement --
    # deliberately NOT the `:only`-restricted shape, so this fixture can
    # actually get past `mix deps.get`/Mix's dependency-graph loading; see
    # this module's moduledoc for why that combination is untestable via a
    # live subprocess at all). `:gno` is a real, direct dependency, which is
    # exactly what makes `config :dcatr, env: ...` become necessary (`:gno`'s
    # own `Gno.Store.Adapters.Fuseki` reads `DCATR.Manifest.env/1` at
    # compile time).
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule DoctorFixE2eFixture.MixProject do
      use Mix.Project

      def project do
        [
          app: :doctor_fix_e2e_fixture,
          version: "0.1.0",
          elixir: "~> 1.17",
          deps: deps()
        ]
      end

      def application, do: [extra_applications: [:logger]]

      defp deps do
        [
          {:ggen_igniter, path: #{inspect(@ggen_igniter_path)}},
          {:igniter, "~> 0.8"},
          {:sourceror, "~> 1.7"},
          {:gno, "~> 0.1"}
        ]
      end
    end
    """)

    File.write!(Path.join(dir, "lib/doctor_fix_e2e_fixture.ex"), """
    defmodule DoctorFixE2eFixture do
    end
    """)

    # A real config/config.exs ending in the standard `import_config`
    # marker, WITHOUT `config :dcatr, env: ...` -- the real problem fix 3
    # detects and repairs.
    File.write!(Path.join(dir, "config/config.exs"), ~S"""
    import Config

    import_config "#{config_env()}.exs"
    """)

    for env <- ["dev", "test", "prod"] do
      File.write!(Path.join(dir, "config/#{env}.exs"), "import Config\n")
    end

    dir
  end

  setup do
    dir = scaffold_fixture!()
    on_exit(fn -> File.rm_rf!(dir) end)

    # Real `mix deps.get` -- network-based but bounded (small, already
    # widely-cached hex packages: rdf/sparql/igniter/gno/dcatr/etc, the same
    # tree ggen_igniter's own test suite already depends on).
    cmd!("mix", ["deps.get"], cd: dir)

    # `:gno`'s `Gno.Store.Adapters.Fuseki` raises at compile time without
    # `config :dcatr, env: ...` (the exact problem this fixture is missing,
    # by design) unless `MIX_ENV`/`DCATR_ENV` is set as a real OS env var
    # (`DCATR.Manifest.env/1`'s own documented fallback) -- exporting it for
    # this first real compile is what makes the fixture buildable at all
    # while still missing the *persistent* config fix 3 adds.
    cmd!("mix", ["compile"], cd: dir, env: [{"MIX_ENV", "dev"}])

    %{dir: dir}
  end

  test "mix ggen_igniter.doctor --fix adds the real missing config :dcatr, env: ... entry",
       %{dir: dir} do
    config_path = Path.join(dir, "config/config.exs")
    before_content = File.read!(config_path)
    refute before_content =~ "dcatr", "fixture should start without config :dcatr"

    {output, exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--fix"],
        cd: dir,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    assert output =~ "FIXED: added `config :dcatr, env: Mix.env()`",
           "expected a real FIXED line for the dcatr config in doctor's output:\n#{output}"

    # Real regression coverage for the `check_nif_compiles/0` bug found by
    # Agent 8's real consumer-scenario audit (2026-08-27): this fixture is a
    # real *consumer* of `ggen_igniter` (its own `Mix.Project.config()[:app]`
    # is `:doctor_fix_e2e_fixture`, not `:ggen_igniter`), so it has no
    # `native/ggen_graph_nif` directory of its own -- that crate only exists
    # inside `ggen_igniter`'s own package tree. Before the fix, check 14
    # (`check_nif_compiles/0`) resolved the crate path via `File.cwd!()`
    # unconditionally, which is this fixture's own project root, so it
    # ALWAYS reported "native/ggen_graph_nif directory not found" (✘) and
    # the whole `mix ggen_igniter.doctor` run exited 1 for every real
    # consumer -- this exact fixture, confirmed directly, before the fix.
    # `ggen_igniter_root/0` now resolves the crate via
    # `Mix.Project.deps_paths()[:ggen_igniter]` when the current app isn't
    # `:ggen_igniter` itself, so the real crate inside the path dependency
    # is found and this check passes for a real consumer too.
    assert output =~ ~r/✔ (native\/ggen_graph_nif|priv\/native\/ggen_graph_nif\.so)/,
           "expected the nif check to pass by resolving ggen_igniter's real on-disk path, not cwd:\n#{output}"

    assert exit_code == 0,
           "expected mix ggen_igniter.doctor --fix to exit 0 for this real consumer fixture, got #{exit_code}:\n#{output}"

    after_content = File.read!(config_path)
    assert after_content =~ "config :dcatr, env: Mix.env()"
    # inserted before the import_config marker, matching this project's own
    # config/config.exs convention
    [_, tail] = String.split(after_content, "config :dcatr, env: Mix.env()", parts: 2)
    assert tail =~ "import_config"

    # Re-running doctor (still --fix) now reports :ok / no-op for this check
    # -- the fix is idempotent against the real file it just wrote.
    {second_output, second_exit_code} =
      System.cmd("mix", ["ggen_igniter.doctor", "--fix"],
        cd: dir,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    assert second_output =~ "config :dcatr, env: ... already present"
    refute second_output =~ "FIXED: added `config :dcatr"

    # The "broken consumer -> doctor detects -> doctor fixes -> second run =
    # clean" requirement: a second `--fix` run is a genuine no-op (nothing
    # left to fix, real exit 0), not just a different message.
    assert second_exit_code == 0,
           "expected the second doctor --fix run to be a genuine no-op (exit 0), got #{second_exit_code}:\n#{second_output}"
  end
end
