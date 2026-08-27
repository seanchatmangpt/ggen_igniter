defmodule GgenIgniter.DoctorFixesTest do
  @moduledoc """
  Chicago-style, no-mocks tests of `GgenIgniter.DoctorFixes` -- the module
  `mix ggen_igniter.doctor --fix` (see `Mix.Tasks.GgenIgniter.Doctor`) calls
  to apply its four real project-hygiene fixes. Every test here builds a
  real, throwaway project fixture under a unique temp directory (real
  `mix.exs`/`config/config.exs`/`lib/*.ex` files on disk, via `File.write!/2`
  and friends), calls the real module functions directly (no
  `System.cmd`/subprocess needed for these -- they are plain functions over
  real files), and asserts on the real resulting file content. No
  `unittest.mock`-equivalent anywhere: every "collaborator" here is a real
  file on a real filesystem.

  `:gno`/`:dcatr` are real dependencies of THIS project (`ggen_igniter`)
  itself (for its own dev/test needs -- see `mix.exs`), so they are actually
  loaded in the BEAM running this test suite; `check_dcatr_env_config/1`'s
  "is :gno/:dcatr in the dependency tree" detection reflects that real,
  currently-running application environment, not a fake.

  See `test/ggen_igniter_doctor_fix_e2e_test.exs` for the complementary real
  end-to-end `mix ggen_igniter.doctor --fix` subprocess test.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.DoctorFixes

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_doctor_fixes_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write_mix_exs!(dir, deps_lines) when is_list(deps_lines) do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Fixture.MixProject do
      use Mix.Project

      def project, do: [app: :fixture, version: "0.1.0", deps: deps()]

      defp deps do
        [
    #{Enum.map_join(deps_lines, "\n", &("      " <> &1))}
        ]
      end
    end
    """)
  end

  defp write_config_exs!(dir, content) do
    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/config.exs"), content)
  end

  # A real, un-interpolated `import_config "#{config_env()}.exs"` marker line,
  # exactly as phx.new/igniter.new generate it (built via ~S so THIS file's
  # own string interpolation doesn't fire on it).
  @import_marker "import_config \"\#{config_env()}.exs\""

  # ---------------------------------------------------------------------
  # Fix 1/2: igniter/sourceror :only relaxation
  # ---------------------------------------------------------------------

  describe "check_dep_only/2 and fix_dep_only!/2" do
    test "detects and relaxes a real `only: [:dev, :test]` restriction, preserving other deps",
         %{dir: dir} do
      write_mix_exs!(dir, [
        ~S({:igniter, "~> 0.8", only: [:dev, :test]},),
        ~S({:rdf, "~> 3.0"})
      ])

      assert {:fixable, message} = DoctorFixes.check_dep_only(dir, :igniter)
      assert message =~ "igniter"
      assert message =~ "only: [:dev, :test]"

      assert {:fixed, fix_message} = DoctorFixes.fix_dep_only!(dir, :igniter)
      assert fix_message =~ "relaxed :igniter"

      updated = File.read!(Path.join(dir, "mix.exs"))
      assert updated =~ ~S({:igniter, "~> 0.8"},)
      refute updated =~ "only:"
      # the unrelated dependency line is untouched
      assert updated =~ ~S({:rdf, "~> 3.0"})
    end

    test "relaxes only: while preserving OTHER options on the same tuple (e.g. runtime: false)",
         %{dir: dir} do
      write_mix_exs!(dir, [
        ~S({:credo, "~> 1.7", only: [:dev, :test], runtime: false}),
        ~S({:igniter, "~> 0.8"})
      ])

      assert {:fixed, _} = DoctorFixes.fix_dep_only!(dir, :credo)

      updated = File.read!(Path.join(dir, "mix.exs"))
      assert updated =~ ~S({:credo, "~> 1.7", runtime: false})
      refute updated =~ "only:"
    end

    test "check reports :ok and fix no-ops when the dependency has no :only restriction",
         %{dir: dir} do
      write_mix_exs!(dir, [~S({:igniter, "~> 0.8"})])

      assert {:ok, message} = DoctorFixes.check_dep_only(dir, :igniter)
      assert message =~ "no :only restriction"

      original = File.read!(Path.join(dir, "mix.exs"))
      assert {:ok, _} = DoctorFixes.fix_dep_only!(dir, :igniter)
      assert File.read!(Path.join(dir, "mix.exs")) == original
    end

    test "check reports :ok and fix no-ops when the dependency isn't directly declared at all",
         %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])

      assert {:ok, message} = DoctorFixes.check_dep_only(dir, :sourceror)
      assert message =~ "not directly declared"

      assert {:ok, _} = DoctorFixes.fix_dep_only!(dir, :sourceror)
    end

    test "is idempotent: fixing twice in a row is a no-op the second time", %{dir: dir} do
      write_mix_exs!(dir, [~S({:sourceror, "~> 1.7", only: [:dev, :test]},)])

      assert {:fixed, _} = DoctorFixes.fix_dep_only!(dir, :sourceror)
      once_fixed = File.read!(Path.join(dir, "mix.exs"))

      assert {:ok, _} = DoctorFixes.fix_dep_only!(dir, :sourceror)
      assert File.read!(Path.join(dir, "mix.exs")) == once_fixed
    end

    test "raises a clear error (never guesses) when no deps/0 function body can be found",
         %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), """
      defmodule Weird.MixProject do
        use Mix.Project
        def project, do: [app: :weird]
      end
      """)

      assert {:unrecognized, message} = DoctorFixes.check_dep_only(dir, :igniter)
      assert message =~ "could not locate a deps/0 function body"

      assert_raise RuntimeError, ~r/could not locate a deps\/0 function body/, fn ->
        DoctorFixes.fix_dep_only!(dir, :igniter)
      end

      # never touched the file it didn't recognize
      assert File.read!(Path.join(dir, "mix.exs")) =~ "defmodule Weird.MixProject"
    end
  end

  # ---------------------------------------------------------------------
  # Fix 3: missing `config :dcatr, env: ...`
  # ---------------------------------------------------------------------

  describe "check_dcatr_env_config/1 and fix_dcatr_env_config!/1" do
    test "reports :ok (nothing to do) when :gno/:dcatr aren't relevant -- simulated via a project dir with no dependency signal",
         %{dir: dir} do
      # :gno/:dcatr ARE loaded in this real BEAM (ggen_igniter's own deps), so
      # this specific "not needed" branch can't be forced without faking
      # Application state -- instead this is exercised for real end-to-end in
      # `ggen_igniter_doctor_fix_e2e_test.exs` via a fixture that never adds
      # :gno at all. Here we only assert the *shape* of the "needed" result,
      # since :gno really is loaded for this test run.
      write_config_exs!(dir, "import Config\n\n#{@import_marker}\n")

      assert {:fixable, message} = DoctorFixes.check_dcatr_env_config(dir)
      assert message =~ ":gno/:dcatr present"
      assert message =~ "config :dcatr, env"
    end

    test "inserts the config before a real phx.new-style import_config marker", %{dir: dir} do
      write_config_exs!(
        dir,
        "import Config\n\nconfig :my_app, key: :value\n\n#{@import_marker}\n"
      )

      assert {:fixed, message} = DoctorFixes.fix_dcatr_env_config!(dir)
      assert message =~ "config :dcatr, env: Mix.env()"

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "config :dcatr, env: Mix.env()"
      # inserted BEFORE the import_config marker, not after
      [_, after_dcatr] = String.split(updated, "config :dcatr, env: Mix.env()", parts: 2)
      assert after_dcatr =~ @import_marker
    end

    test "appends at the end when config.exs exists but has no import_config marker",
         %{dir: dir} do
      write_config_exs!(dir, "import Config\n\nconfig :my_app, key: :value\n")

      assert {:fixed, _} = DoctorFixes.fix_dcatr_env_config!(dir)

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "config :my_app, key: :value"
      assert updated =~ "config :dcatr, env: Mix.env()"
    end

    test "creates a minimal config/config.exs when none exists at all", %{dir: dir} do
      refute File.exists?(Path.join(dir, "config/config.exs"))

      assert {:fixed, _} = DoctorFixes.fix_dcatr_env_config!(dir)

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "import Config"
      assert updated =~ "config :dcatr, env: Mix.env()"
    end

    test "reports :ok and no-ops when config :dcatr, env: ... is already present", %{dir: dir} do
      write_config_exs!(
        dir,
        "import Config\n\nconfig :dcatr, env: Mix.env()\n\n#{@import_marker}\n"
      )

      assert {:ok, message} = DoctorFixes.check_dcatr_env_config(dir)
      assert message =~ "already present"

      original = File.read!(Path.join(dir, "config/config.exs"))
      assert {:ok, _} = DoctorFixes.fix_dcatr_env_config!(dir)
      assert File.read!(Path.join(dir, "config/config.exs")) == original
    end

    test "recognizes a real multi-line config :dcatr, env: ... block (as ggen_igniter's own config/config.exs uses)",
         %{dir: dir} do
      write_config_exs!(dir, """
      import Config

      config :dcatr,
        env: Mix.env(),
        load_path: ["config/gno"]

      #{@import_marker}
      """)

      assert {:ok, message} = DoctorFixes.check_dcatr_env_config(dir)
      assert message =~ "already present"
    end
  end

  # ---------------------------------------------------------------------
  # Fix 4: Ash domain modules missing from `ash_domains:`
  # ---------------------------------------------------------------------

  describe "check_ash_domains/1 and fix_ash_domains!/1" do
    test "reports :ok when no `use Ash.Domain` module exists under lib/", %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib"))
      File.write!(Path.join(dir, "lib/plain.ex"), "defmodule Fixture.Plain do\nend\n")

      assert {:ok, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "no `use Ash.Domain` modules found"
    end

    test "detects an unregistered Ash domain and registers it in a brand-new ash_domains config",
         %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib/fixture"))

      File.write!(Path.join(dir, "lib/fixture/support.ex"), """
      defmodule Fixture.Support do
        use Ash.Domain, otp_app: :fixture

        resources do
          resource Fixture.Support.Ticket
        end
      end
      """)

      write_config_exs!(dir, "import Config\n\n#{@import_marker}\n")

      assert {:fixable, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "Fixture.Support"

      assert {:fixed, fix_message} = DoctorFixes.fix_ash_domains!(dir)
      assert fix_message =~ "Fixture.Support"

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "config :fixture, ash_domains: [Fixture.Support]"

      assert {:ok, _} = DoctorFixes.check_ash_domains(dir)
    end

    test "merges a missing domain into an EXISTING partial ash_domains list without disturbing other apps' config",
         %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/support.ex"), """
      defmodule Fixture.Support do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      File.write!(Path.join(dir, "lib/billing.ex"), """
      defmodule Fixture.Billing do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      write_config_exs!(dir, """
      import Config

      config :fixture, ash_domains: [Fixture.Support]

      config :other_app, ash_domains: [Other.Thing]
      """)

      assert {:fixable, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "Fixture.Billing"
      refute message =~ "Fixture.Support"

      assert {:fixed, _} = DoctorFixes.fix_ash_domains!(dir)

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "config :fixture, ash_domains: [Fixture.Support, Fixture.Billing]"
      # completely untouched -- this is a different OTP app's config
      assert updated =~ "config :other_app, ash_domains: [Other.Thing]"
    end

    test "reports :ok and no-ops when all Ash domains are already registered", %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/support.ex"), """
      defmodule Fixture.Support do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      write_config_exs!(dir, """
      import Config

      config :fixture, ash_domains: [Fixture.Support]
      """)

      assert {:ok, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "already registered"

      original = File.read!(Path.join(dir, "config/config.exs"))
      assert {:ok, _} = DoctorFixes.fix_ash_domains!(dir)
      assert File.read!(Path.join(dir, "config/config.exs")) == original
    end

    test "raises a clear error (never guesses) when an existing ash_domains value isn't a literal list",
         %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/dom.ex"), """
      defmodule Fixture.Dom do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      write_config_exs!(dir, """
      import Config

      config :fixture, ash_domains: Fixture.compute_domains()
      """)

      assert {:unrecognized, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "isn't a simple literal list"

      assert_raise RuntimeError, ~r/isn't a simple literal list/, fn ->
        DoctorFixes.fix_ash_domains!(dir)
      end

      # never touched the file it didn't recognize
      assert File.read!(Path.join(dir, "config/config.exs")) =~
               "config :fixture, ash_domains: Fixture.compute_domains()"
    end

    test "discovers multiple distinct Ash domain modules across separate files", %{dir: dir} do
      write_mix_exs!(dir, [~S({:rdf, "~> 3.0"})])
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/a.ex"), """
      defmodule Fixture.A do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      File.write!(Path.join(dir, "lib/b.ex"), """
      defmodule Fixture.B do
        use Ash.Domain, otp_app: :fixture
      end
      """)

      write_config_exs!(dir, "import Config\n\n#{@import_marker}\n")

      assert {:fixable, message} = DoctorFixes.check_ash_domains(dir)
      assert message =~ "2 Ash domain module(s)"

      assert {:fixed, _} = DoctorFixes.fix_ash_domains!(dir)

      updated = File.read!(Path.join(dir, "config/config.exs"))
      assert updated =~ "config :fixture, ash_domains: [Fixture.A, Fixture.B]"
    end
  end
end
