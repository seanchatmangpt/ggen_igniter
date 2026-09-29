defmodule GgenIgniter.DoctorFixesIdempotenceTest do
  @moduledoc """
  Chicago-style, no-mocks idempotence harness for `GgenIgniter.DoctorFixes`.

  Every fix in `doctor_fixes.ex` takes a `project_dir` and reads/writes real
  files, so the `Igniter`-struct idempotence harness
  (`ggen_igniter_igniter_idempotence_test.exs`) cannot reach it. Here each
  test builds a real, unique tmp Mix-project directory on disk exhibiting the
  defect, runs the real fix, asserts the real bytes changed as intended, runs
  the fix a second time and asserts the bytes are byte-identical, and each
  rule also has a negative case (an already-correct project is left
  byte-untouched).

  Rules covered (line refs are `lib/ggen_igniter/doctor_fixes.ex`):

    1. `dep_only_rule(:igniter)`   -- `igniter_only_relaxation` (~L262)
    2. `dep_only_rule(:sourceror)` -- `sourceror_only_relaxation` (~L262)
    3. `dcatr_env_rule/0`          -- `dcatr_env_config` (~L493); `:gno`/`:dcatr`
       are real deps of this project so they are genuinely loaded here
    4. `ash_domains_rule/0`        -- `ash_domains_registration` (~L574)
    5. `package_description_rule/0` -- `package_description` (~L791)
    6. `package_licenses_rule/0`   -- `package_licenses` (~L895)
    7. `fix_version_policy!/1`     -- CHANGELOG-derived version (~L1134)

  `async: true` is safe: every function takes an explicit `project_dir` and
  no test changes the process cwd. No mock/stub library is used anywhere.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.DoctorFixes

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_doctor_fixes_idem_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "config"))
    File.mkdir_p!(Path.join(dir, "lib"))
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp mix_exs(dir, opts) do
    deps = Keyword.get(opts, :deps, [])
    version = Keyword.get(opts, :version, "0.1.0")
    package = Keyword.get(opts, :package, "[\n      maintainers: [\"x\"]\n    ]")
    extra = Keyword.get(opts, :extra, "")

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Fixture.MixProject do
      use Mix.Project

      def project do
        [
          app: :fixture,
          version: "#{version}",
          deps: deps()
        ]
      end

      defp deps do
        [
    #{Enum.map_join(deps, ",\n", &("      " <> &1))}
        ]
      end

      defp package do
        #{package}
      end
    #{extra}
    end
    """)
  end

  defp read(dir, rel), do: File.read!(Path.join(dir, rel))

  # Runs `fun` twice; asserts run 1 changes `rel`, run 2 is byte-identical to run 1.
  defp assert_fix_idempotent(dir, rel, fun) do
    before = read(dir, rel)
    assert {:fixed, _} = fun.()
    once = read(dir, rel)
    refute once == before
    assert {:ok, _} = fun.()
    assert read(dir, rel) == once
    {before, once}
  end

  defp assert_untouched(dir, rel, fun) do
    before = read(dir, rel)
    assert {:ok, _} = fun.()
    assert read(dir, rel) == before
  end

  # -- Rules 1 & 2: dep :only relaxation -----------------------------------

  for dep <- [:igniter, :sourceror] do
    test "#{dep}_only_relaxation: fixes, is idempotent, removes only `only:`", %{dir: dir} do
      dep = unquote(dep)

      mix_exs(dir,
        deps: ["{:#{dep}, \"~> 0.8\", only: :dev, runtime: false}", "{:jason, \"~> 1.4\"}"]
      )

      {_before, once} =
        assert_fix_idempotent(dir, "mix.exs", fn -> DoctorFixes.fix_dep_only!(dir, dep) end)

      refute once =~ "only:"
      assert once =~ "runtime: false"
      assert once =~ "{:jason, \"~> 1.4\"}"
    end

    test "#{dep}_only_relaxation: unrestricted dep and absent dep stay untouched", %{dir: dir} do
      dep = unquote(dep)
      mix_exs(dir, deps: ["{:#{dep}, \"~> 0.8\"}"])
      assert_untouched(dir, "mix.exs", fn -> DoctorFixes.fix_dep_only!(dir, dep) end)

      mix_exs(dir, deps: ["{:jason, \"~> 1.4\"}"])
      assert_untouched(dir, "mix.exs", fn -> DoctorFixes.fix_dep_only!(dir, dep) end)
    end
  end

  test "igniter_only_relaxation: emptied opts collapse to a 2-tuple", %{dir: dir} do
    mix_exs(dir, deps: ["{:igniter, \"~> 0.8\", only: :dev}"])

    {_b, once} =
      assert_fix_idempotent(dir, "mix.exs", fn -> DoctorFixes.fix_dep_only!(dir, :igniter) end)

    # a lone 2-tuple with an atom key is rendered as keyword shorthand by the formatter
    assert once =~ ~s({:igniter, "~> 0.8"}) or once =~ ~s(igniter: "~> 0.8")
    refute once =~ "[]"
  end

  # -- Rule 3: dcatr env config ---------------------------------------------

  test "dcatr_env_config: adds config before import_config marker, idempotent", %{dir: dir} do
    File.write!(Path.join(dir, "config/config.exs"), """
    import Config

    config :fixture, foo: 1

    import_config "\#{config_env()}.exs"
    """)

    {_b, once} =
      assert_fix_idempotent(dir, "config/config.exs", fn ->
        DoctorFixes.fix_dcatr_env_config!(dir)
      end)

    assert once =~ "config :dcatr, env: Mix.env()"
    {pos_dcatr, _} = :binary.match(once, "config :dcatr")
    {pos_marker, _} = :binary.match(once, "import_config")
    assert pos_dcatr < pos_marker
  end

  test "dcatr_env_config: creates a minimal config when none exists, idempotent", %{dir: dir} do
    refute File.exists?(Path.join(dir, "config/config.exs"))

    {_b, once} = create_then_fix_dcatr(dir)
    assert once =~ "import Config"
    assert once =~ "config :dcatr, env: Mix.env()"
  end

  test "dcatr_env_config: already-configured project stays untouched", %{dir: dir} do
    File.write!(
      Path.join(dir, "config/config.exs"),
      "import Config\n\nconfig :dcatr, env: :test\n"
    )

    assert_untouched(dir, "config/config.exs", fn -> DoctorFixes.fix_dcatr_env_config!(dir) end)
  end

  defp create_then_fix_dcatr(dir) do
    rel = "config/config.exs"
    assert {:fixed, _} = DoctorFixes.fix_dcatr_env_config!(dir)
    once = read(dir, rel)
    assert {:ok, _} = DoctorFixes.fix_dcatr_env_config!(dir)
    assert read(dir, rel) == once
    {nil, once}
  end

  # -- Rule 4: ash_domains registration -------------------------------------

  defp write_domain!(dir, name) do
    File.write!(Path.join(dir, "lib/#{String.downcase(name)}.ex"), """
    defmodule Fixture.#{name} do
      use Ash.Domain
    end
    """)
  end

  test "ash_domains_registration: inserts new block, idempotent", %{dir: dir} do
    mix_exs(dir, [])
    write_domain!(dir, "Blog")
    File.write!(Path.join(dir, "config/config.exs"), "import Config\n")

    {_b, once} =
      assert_fix_idempotent(dir, "config/config.exs", fn -> DoctorFixes.fix_ash_domains!(dir) end)

    assert once =~ "ash_domains"
    assert once =~ "Fixture.Blog"
  end

  test "ash_domains_registration: merges into existing list, idempotent", %{dir: dir} do
    mix_exs(dir, [])
    write_domain!(dir, "Blog")
    write_domain!(dir, "Shop")

    File.write!(Path.join(dir, "config/config.exs"), """
    import Config

    config :fixture, ash_domains: [Fixture.Blog]
    """)

    {_b, once} =
      assert_fix_idempotent(dir, "config/config.exs", fn -> DoctorFixes.fix_ash_domains!(dir) end)

    assert once =~ "Fixture.Blog"
    assert once =~ "Fixture.Shop"
  end

  test "ash_domains_registration: fully registered and no-domain projects stay untouched", %{
    dir: dir
  } do
    mix_exs(dir, [])
    File.write!(Path.join(dir, "config/config.exs"), "import Config\n")
    assert_untouched(dir, "config/config.exs", fn -> DoctorFixes.fix_ash_domains!(dir) end)

    write_domain!(dir, "Blog")

    File.write!(
      Path.join(dir, "config/config.exs"),
      "import Config\n\nconfig :fixture, ash_domains: [Fixture.Blog]\n"
    )

    assert_untouched(dir, "config/config.exs", fn -> DoctorFixes.fix_ash_domains!(dir) end)
  end

  # -- Rule 5: package description ------------------------------------------

  test "package_description: wires description(), idempotent", %{dir: dir} do
    mix_exs(dir, extra: "  defp description do\n    \"desc\"\n  end")

    {_b, once} =
      assert_fix_idempotent(dir, "mix.exs", fn ->
        DoctorFixes.run_rule(DoctorFixes.package_description_rule(), dir, true)
      end)

    assert once =~ "description: description()"
    assert once =~ "maintainers:"
  end

  test "package_description: already-present stays untouched; no description/0 refuses", %{
    dir: dir
  } do
    mix_exs(dir,
      package: "[\n      description: \"x\"\n    ]"
    )

    assert_untouched(dir, "mix.exs", fn ->
      DoctorFixes.run_rule(DoctorFixes.package_description_rule(), dir, true)
    end)

    mix_exs(dir, [])
    before = read(dir, "mix.exs")

    assert_raise RuntimeError, ~r/refusing to invent text/, fn ->
      DoctorFixes.run_rule(DoctorFixes.package_description_rule(), dir, true)
    end

    assert read(dir, "mix.exs") == before
  end

  # -- Rule 6: package licenses ---------------------------------------------

  test "package_licenses: wires MIT from LICENSE, idempotent", %{dir: dir} do
    mix_exs(dir, [])
    File.write!(Path.join(dir, "LICENSE"), "MIT License\n\nCopyright\n")

    {_b, once} =
      assert_fix_idempotent(dir, "mix.exs", fn ->
        DoctorFixes.run_rule(DoctorFixes.package_licenses_rule(), dir, true)
      end)

    assert once =~ "licenses: [\"MIT\"]"
  end

  test "package_licenses: already-present untouched; unrecognized LICENSE refuses", %{dir: dir} do
    mix_exs(dir, package: "[\n      licenses: [\"Apache-2.0\"]\n    ]")

    assert_untouched(dir, "mix.exs", fn ->
      DoctorFixes.run_rule(DoctorFixes.package_licenses_rule(), dir, true)
    end)

    mix_exs(dir, [])
    File.write!(Path.join(dir, "LICENSE"), "Some Custom License\n")
    before = read(dir, "mix.exs")

    assert_raise RuntimeError, ~r/refusing to guess a license/, fn ->
      DoctorFixes.run_rule(DoctorFixes.package_licenses_rule(), dir, true)
    end

    assert read(dir, "mix.exs") == before
  end

  # -- Rule 7: version policy -----------------------------------------------

  test "version_policy: rewrites version to CHANGELOG top entry, idempotent", %{dir: dir} do
    mix_exs(dir, version: "26.9.1")

    File.write!(
      Path.join(dir, "CHANGELOG.md"),
      "# Changelog\n\n## v26.9.28\n\n- x\n\n## v26.9.1\n"
    )

    {_b, once} =
      assert_fix_idempotent(dir, "mix.exs", fn -> DoctorFixes.fix_version_policy!(dir) end)

    assert once =~ ~s(version: "26.9.28")
    refute once =~ "26.9.1\""
  end

  test "version_policy: matching version and absent CHANGELOG stay untouched", %{dir: dir} do
    mix_exs(dir, version: "26.9.28")
    assert_untouched(dir, "mix.exs", fn -> DoctorFixes.fix_version_policy!(dir) end)

    File.write!(Path.join(dir, "CHANGELOG.md"), "## v26.9.28\n")
    assert_untouched(dir, "mix.exs", fn -> DoctorFixes.fix_version_policy!(dir) end)
  end
end
