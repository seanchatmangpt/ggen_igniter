defmodule GgenIgniter.E2e.Case do
  @moduledoc """
  Shared support helpers for ggen_igniter end-to-end tests.

  These tests scaffold a real, throwaway Phoenix/Igniter/Ash application in a
  temp directory and run real `mix` subprocesses against it (archive install,
  igniter.new, deps.get, compile, test) -- no mocking of the shell or of
  Mix itself. This is a plain module with a `using/1` macro (not
  `ExUnit.CaseTemplate`) since these are just helper functions imported into
  a hand-written ExUnit test file that is `Code.require_file`'d directly by
  `test/e2e/run_e2e.exs`, not run under the normal `mix test` case-template
  machinery.
  """

  defmacro __using__(_opts) do
    quote do
      import GgenIgniter.E2e.Case
    end
  end

  @ggen_igniter_path "/Users/sac/ggen_igniter"

  @doc """
  Runs `System.cmd/3`, merging stderr into stdout and asserting a zero exit
  status. Raises a `RuntimeError` with the full captured output on failure so
  the real subprocess output is visible in the test failure, not swallowed.
  """
  def cmd!(command, args, opts \\ []) do
    merged_opts = Keyword.merge([stderr_to_stdout: true], opts)

    case System.cmd(command, args, merged_opts) do
      {output, 0} ->
        output

      {output, exit_status} ->
        raise RuntimeError, """
        command failed: #{command} #{Enum.join(args, " ")} (exit #{exit_status})

        #{output}
        """
    end
  end

  @doc """
  Scaffolds a fresh Phoenix + Igniter + Ash application under a unique
  directory in `System.tmp_dir!()`, using real `mix` subprocesses:

    * `mix archive.install hex phx_new --force`
    * `mix archive.install hex igniter_new --force`
    * `mix igniter.new APP_NAME --install ash,ash_phoenix --with phx.new --with-args="--no-ecto" --yes`

  ## Disclosed risk investigated and fixed (2026-08-27): Postgres-less sandbox

  Originally disclosed risk: Stage 0's baseline `test!/1` (see
  `test/e2e/lifecycle_test.ex`) runs immediately after this function returns,
  and `phx.new`'s default generated `ConnCase`/`DataCase` assume a live local
  Postgres for their Ecto sandbox checkout -- this function never ran
  `mix ecto.create`, so the baseline could fail in a Postgres-less sandbox
  even before `ggen_igniter` touches anything.

  Investigated and confirmed real via current upstream docs before fixing:

    * `mix igniter.new`'s own `--with-args` documentation (igniter_new v0.5.33,
      https://igniter-new.hexdocs.pm/Mix.Tasks.Igniter.New.html) gives this
      EXACT example: `mix igniter.new my_project --install foo,bar,baz
      --with=phx.new --with-args="--no-ecto"` -- confirming `--no-ecto` is a
      real, documented flag forwarded from `igniter.new` to the underlying
      `phx.new` generator via `--with-args`.
    * The official `ash_phoenix` "Get Started with Ash and Phoenix" guide
      (https://ash-phoenix.hexdocs.pm/2.1.21/getting-started-with-ash-and-phoenix.html)
      recommends `mix igniter.new my_ash_phoenix_app --install
      ash,ash_phoenix,ash_postgres --with phx.new` for a Postgres-backed Ash
      app and explicitly instructs the developer NOT to run `mix ecto.create`
      manually (Ash owns migration/setup via `mix ash.setup`) -- but that
      guide only omits `--no-ecto` because it deliberately installs
      `ash_postgres`. It confirms the two concerns this task asked to
      distinguish really are separate: `phx.new`'s own Ecto/Postgres
      scaffolding (`ConnCase`/`DataCase`, `Repo`, `config/dev.exs` database
      config) is generated purely because `--with phx.new` was passed, NOT
      because of which `Ash.DataLayer` the app's own Ash resources end up
      using. Ash's installer does not itself skip Ecto based on the
      resources' data layer -- `phx.new` always scaffolds Ecto unless told
      not to.
    * This e2e's own fixture pack templates hard-code `data_layer:
      Ash.DataLayer.Ets` for every generated resource (see
      `test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex`, asserted
      at `lifecycle_test.ex:135`) -- there is no AshPostgres resource anywhere
      in this e2e, so `phx.new`'s default Ecto/Postgres scaffolding here is
      genuinely 100% dead weight, not a real dependency this suite needs.

  Fix applied: pass `--with-args="--no-ecto"` to `mix igniter.new` below, so
  the scaffolded app never generates an Ecto `Repo`, Postgres-backed
  `DataCase`, or a Postgres-sandboxing `ConnCase` in the first place --
  consistent with this whole e2e's stated data-layer decision
  (`Ash.DataLayer.Ets`, explicitly not `AshPostgres`). This removes the
  Postgres dependency at the source rather than working around it after the
  fact (e.g. by running `mix ecto.create`, which would require a real,
  reachable Postgres and contradict the Ets-only design of this suite).

  Returns the absolute path to the scaffolded application directory.
  """
  def scaffold_app!(app_name) do
    # `System.pid()` (the OS-level BEAM PID) is included alongside
    # `System.unique_integer([:positive])`, not the integer alone -- real,
    # verified requirement (2026-08-27). `System.unique_integer/1` is only
    # unique WITHIN one BEAM VM instance's lifetime; it is a monotonic
    # counter seeded by how many unique-integer allocations already happened
    # during that VM's startup, which is largely deterministic for the same
    # codebase/dependency set. Confirmed directly via two real, separate
    # `mix e2e` invocations in this same shared, multi-agent-concurrent
    # sandbox (each `mix e2e` boots a fresh BEAM VM): both independently
    # produced the EXACT SAME directory name
    # `/Users/sac/.cache/tmp/ggen_igniter_e2e_8002`. A second, real,
    # concurrent process in this sandbox (confirmed via `ps aux` showing
    # other live `mix test`/`mix ggen_igniter.sync` subprocesses against this
    # same repo throughout this session) reused that identical name and its
    # own `on_exit`'s `File.rm_rf!/1` deleted the directory out from under
    # this run mid-scaffold, so `phx.new`'s own internal `File.cd!/1` back to
    # `parent_dir` (to run `mix deps.get`) failed with
    # `(File.Error) could not set current working directory ... no such file
    # or directory`. Prefixing the OS PID makes the directory name unique
    # across concurrent OS processes too (not just within one VM), which a
    # bare monotonic counter cannot guarantee.
    parent_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_e2e_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(parent_dir)

    cmd!("mix", ["archive.install", "hex", "phx_new", "--force"], cd: parent_dir)
    cmd!("mix", ["archive.install", "hex", "igniter_new", "--force"], cd: parent_dir)

    cmd!(
      "mix",
      [
        "igniter.new",
        app_name,
        "--install",
        "ash,ash_phoenix",
        "--with",
        "phx.new",
        "--with-args=--no-ecto",
        "--yes"
      ],
      cd: parent_dir
    )

    Path.join(parent_dir, app_name)
  end

  @doc """
  Inserts a `ggen_igniter` path dependency (pointing at this checkout) into
  the scaffolded app's `mix.exs` `deps/0` list, then runs `mix deps.get`.

  Reads the real `mix.exs` first and edits it with a precise string
  replacement of the `deps do ... end` block's opening `[` -- no regex
  rewriting of the whole file, to avoid corrupting unrelated content.

  ## Why this also relaxes the scaffolded app's own `:igniter` and `:sourceror` deps (real, verified conflict)

  A freshly `mix igniter.new APP --install ash,ash_phoenix --with phx.new
  --yes`-scaffolded app's OWN generated `mix.exs` declares
  `{:igniter, "~> 0.6", only: [:dev, :test]}` (verified directly by
  scaffolding a real throwaway probe app and reading its generated
  `mix.exs` -- igniter_new 0.5.34 / phx_new 1.8.13, 2026-08-27; the exact
  generated line, at 6-space indent matching this module's other deps-list
  edits, was `{:igniter, "~> 0.6", only: [:dev, :test]},`).

  `ggen_igniter`'s own `mix.exs` declares `{:igniter, "~> 0.8"}` completely
  UNRESTRICTED (required for every consumer regardless of `Mix.env/0` --
  see that file's own comment for why `only: [:dev, :test]` there is wrong:
  `lib/mix/tasks/ggen_igniter.sync.ex`/`ggen_igniter.doctor.ex` are real
  production code that `use Igniter.Mix.Task`).

  Once `add_ggen_igniter_dep!/1` inserts `ggen_igniter` as a path dependency
  into the scaffolded app above, Mix's resolver sees the same `:igniter`
  dependency declared with diverging `:only` restrictions in two places in
  the same tree (unrestricted via `ggen_igniter`, `only: [:dev, :test]` via
  the scaffolded app itself) and refuses to resolve -- confirmed directly in
  a prior real `mix deps.get` run against a scaffolded consumer app with
  this path dependency added. The two version constraints themselves are
  NOT in conflict (`~> 0.6` and `~> 0.8` are both two-segment requirements,
  each meaning `>= 0.6.0 and < 1.0.0` / `>= 0.8.0 and < 1.0.0` respectively
  per Hex's version-matching rules -- they overlap on any `0.8.x`/`0.9.x`
  release); the sole real conflict is the `:only` mismatch.

  The fix applied here (`relax_scaffolded_igniter_dep!/1`, called below
  before `mix deps.get`) removes the scaffolded app's own `, only: [:dev,
  :test]` restriction on its `:igniter` line so both sides agree: `:igniter`
  is a required, unconditional dependency. This does NOT touch
  `ggen_igniter`'s own `mix.exs` (already correct, per the comment there --
  restricting `ggen_igniter`'s own `:igniter` dep to `:dev`/`:test` was
  tried earlier and is wrong, and is not repeated here).

  ## The identical conflict one level down: `:sourceror` (discovered during real end-to-end verification, 2026-08-27)

  Relaxing `:igniter` alone made `mix deps.get` proceed further and then
  hit the EXACT SAME conflict class on a second package: `igniter` v0.8.3
  itself unconditionally requires `{:ex_ast, "~> 0.5"}` (see `igniter`'s own
  `mix.lock` entry), and `ex_ast` unconditionally requires
  `{:sourceror, "~> 1.7"}` -- so once `:igniter` is unconditional, its
  transitive `:sourceror` requirement becomes unconditional too (`rewrite`,
  another of `igniter`'s unconditional deps, also requires `:sourceror`
  unconditionally). This collides with the scaffolded app's OWN generated
  `{:sourceror, "~> 1.8", only: [:dev, :test]}` line (verified the same way,
  same probe app) -- confirmed directly: `mix deps.get` failed with
  "Dependencies have diverged: * sourceror ... does not match the :only
  option calculated for ... In deps/ex_ast/mix.exs" until this second line
  was relaxed the same way. As with `:igniter`, the version constraints
  are compatible (`~> 1.7`/`~> 1.8`/`~> 1.4`/`~> 1.0` all resolved cleanly
  to `sourceror` 1.12.2 once the `:only` mismatch was removed) -- `:only` is
  the sole real conflict here too. `relax_scaffolded_sourceror_dep!/1`
  (called below, same as `relax_scaffolded_igniter_dep!/1`) applies the
  identical fix.

  ## Why this also patches `config/config.exs` (real, verified requirement)

  `ggen_igniter`'s own `lib/ggen_igniter/query/qlever.ex` is real production
  code that depends on `:gno` (unconditionally, as of the mix.exs fix
  alongside this change -- see that file's comments for the full
  investigation into why `:gno`/`:igniter` cannot be `only: [:dev, :test]`
  there). `:gno` in turn depends on `:dcatr`, whose
  `lib/gno/store_adapters/fuseki.ex` calls `DCATR.Manifest.env/1` at compile
  time, which RAISES unless `config :dcatr, env: ...` (or the `DCATR_ENV`/
  `MIX_ENV` OS environment variable) is set -- verified directly via a
  minimal ash-free `{:ggen_igniter, path: ...}` consumer repro: `mix compile`
  failed with "No environment configured. Please set the :dcatr environment
  via the `:env` configuration option" at `lib/gno/store_adapters/fuseki.ex:49`
  until the consumer's OWN `config/config.exs` set `config :dcatr, env:
  Mix.env()` -- adding that one line made the same repro compile cleanly
  end-to-end (`ggen_igniter`, `gno`, `dcatr` all `Generated ... app`).

  Mix never loads a path dependency's own `config/config.exs` when that
  dependency is compiled as part of another project -- only the top-level
  project's config tree is evaluated -- so this requirement can only be
  satisfied here, in the scaffolded consumer app's own config, not in
  `ggen_igniter`'s.

  Every `phx.new`-scaffolded app's `config/config.exs` ends with
  `import_config "#\{config_env()}.exs"` (a stable Phoenix 1.7+ invariant,
  independent of `--no-ecto`/which installers ran) -- the config is inserted
  immediately before that line, raising loudly rather than guessing if a
  future scaffold's actual content doesn't match.
  """
  def add_ggen_igniter_dep!(app_dir) do
    mix_exs_path = Path.join(app_dir, "mix.exs")
    original = File.read!(mix_exs_path)

    unless String.contains?(original, "defp deps do") do
      raise RuntimeError, "could not find `defp deps do` in #{mix_exs_path}"
    end

    marker = "defp deps do\n    [\n"

    unless String.contains?(original, marker) do
      raise RuntimeError, """
      expected to find deps list opening `#{inspect(marker)}` in #{mix_exs_path}, \
      but the file's actual formatting did not match -- refusing to regex-rewrite it.

      #{original}
      """
    end

    dep_line = "      {:ggen_igniter, path: #{inspect(@ggen_igniter_path)}},\n"

    updated = String.replace(original, marker, marker <> dep_line, global: false)

    File.write!(mix_exs_path, updated)

    relax_scaffolded_igniter_dep!(app_dir)
    relax_scaffolded_sourceror_dep!(app_dir)
    add_dcatr_env_config!(app_dir)

    cmd!("mix", ["deps.get"], cd: app_dir)
  end

  @doc """
  Relaxes the scaffolded app's own generated `:igniter` dependency in its
  `mix.exs` from `{:igniter, "~> 0.6", only: [:dev, :test]}` to
  `{:igniter, "~> 0.6"}`, removing the `:only` restriction so it no longer
  diverges from `ggen_igniter`'s own unrestricted `{:igniter, "~> 0.8"}`
  requirement (see `add_ggen_igniter_dep!/1`'s moduledoc for the full,
  verified explanation of why the two diverging `:only` declarations block
  Mix's resolver).

  Reads the real `mix.exs` first and edits it with a precise string
  replacement of the exact generated dependency line -- no regex rewriting
  of the whole file, to avoid corrupting unrelated content. Raises loudly
  if a future scaffold's actual generated line doesn't match, rather than
  silently no-op'ing.
  """
  def relax_scaffolded_igniter_dep!(app_dir) do
    mix_exs_path = Path.join(app_dir, "mix.exs")
    original = File.read!(mix_exs_path)

    restricted_line = "      {:igniter, \"~> 0.6\", only: [:dev, :test]},\n"

    unless String.contains?(original, restricted_line) do
      raise RuntimeError, """
      expected to find the scaffolded app's generated, `:only`-restricted \
      `:igniter` dependency line #{inspect(restricted_line)} in \
      #{mix_exs_path}, but the file's actual content did not match -- \
      refusing to regex-rewrite it.

      #{original}
      """
    end

    unrestricted_line = "      {:igniter, \"~> 0.6\"},\n"

    updated = String.replace(original, restricted_line, unrestricted_line, global: false)

    File.write!(mix_exs_path, updated)
  end

  @doc """
  Relaxes the scaffolded app's own generated `:sourceror` dependency in its
  `mix.exs` from `{:sourceror, "~> 1.8", only: [:dev, :test]}` to
  `{:sourceror, "~> 1.8"}`, removing the `:only` restriction.

  This is the identical conflict class as `relax_scaffolded_igniter_dep!/1`,
  one level down the dependency graph: once `:igniter` is unconditional
  (per that function), its own unconditional `:ex_ast`/`:rewrite`
  dependencies pull in `:sourceror` unconditionally too, which then
  diverges from the scaffolded app's own `:only`-restricted `:sourceror`
  line (see `add_ggen_igniter_dep!/1`'s moduledoc for the full, verified
  explanation, including the real `mix deps.get` failure this fixes).

  Reads the real `mix.exs` first and edits it with a precise string
  replacement of the exact generated dependency line -- no regex rewriting
  of the whole file, to avoid corrupting unrelated content. Raises loudly
  if a future scaffold's actual generated line doesn't match, rather than
  silently no-op'ing.
  """
  def relax_scaffolded_sourceror_dep!(app_dir) do
    mix_exs_path = Path.join(app_dir, "mix.exs")
    original = File.read!(mix_exs_path)

    restricted_line = "      {:sourceror, \"~> 1.8\", only: [:dev, :test]},\n"

    unless String.contains?(original, restricted_line) do
      raise RuntimeError, """
      expected to find the scaffolded app's generated, `:only`-restricted \
      `:sourceror` dependency line #{inspect(restricted_line)} in \
      #{mix_exs_path}, but the file's actual content did not match -- \
      refusing to regex-rewrite it.

      #{original}
      """
    end

    unrestricted_line = "      {:sourceror, \"~> 1.8\"},\n"

    updated = String.replace(original, restricted_line, unrestricted_line, global: false)

    File.write!(mix_exs_path, updated)
  end

  defp add_dcatr_env_config!(app_dir) do
    config_path = Path.join(app_dir, "config/config.exs")
    original = File.read!(config_path)

    marker = "import_config \"\#{config_env()}.exs\""

    unless String.contains?(original, marker) do
      raise RuntimeError, """
      expected to find the trailing `#{inspect(marker)}` line in #{config_path} \
      (a stable phx.new invariant) to anchor the required `config :dcatr, env: \
      Mix.env()` insertion (ggen_igniter's :gno dependency's own :dcatr \
      dependency raises at compile time without it -- see \
      add_ggen_igniter_dep!/1's moduledoc), but the file's actual content did \
      not match -- refusing to regex-rewrite it.

      #{original}
      """
    end

    dcatr_config = "config :dcatr, env: Mix.env()\n\n"

    updated = String.replace(original, marker, dcatr_config <> marker, global: false)

    File.write!(config_path, updated)
  end

  @doc """
  Registers one or more Ash domain modules in the scaffolded app's
  `config/config.exs` as `config :OTP_APP, ash_domains: [...]`.

  ## Real, verified requirement (2026-08-27)

  Ash's own compile-time domain verification (triggered by `use Ash.Domain`,
  surfacing via `Module.ParallelChecker`'s `__verify_spark_dsl__/1`) emits a
  compile WARNING -- promoted to a hard error by
  `mix compile --warnings-as-errors` -- whenever a domain module is compiled
  but not listed in `config :OTP_APP, ash_domains: [...]`. Confirmed directly
  via a real e2e run against this pack's generated `SupportDesk.Support`
  domain: `mix compile --warnings-as-errors` failed with `warning: Domain
  SupportDesk.Support is not present in config :support_desk, ash_domains:
  [].` at Stage 1's first post-sync compile (`lifecycle_test.ex:114`).
  `mix igniter.new --install ash,...` does not itself register any domain
  (there are none yet at scaffold time), so any ggen-generated domain module
  must be registered here before the first `mix compile` that compiles it.

  Uses the same `import_config` marker + precise `String.replace/3`
  (`global: false`) convention as `add_dcatr_env_config!/1`, so multiple
  calls compose (each inserts its own config block immediately before the
  still-present marker line) -- raises loudly if the marker is missing
  rather than guessing.
  """
  def add_ash_domains_config!(app_dir, otp_app, domain_modules) when is_list(domain_modules) do
    config_path = Path.join(app_dir, "config/config.exs")
    original = File.read!(config_path)

    marker = "import_config \"\#{config_env()}.exs\""

    unless String.contains?(original, marker) do
      raise RuntimeError, """
      expected to find the trailing #{inspect(marker)} line in #{config_path} \
      (a stable phx.new invariant) to anchor the required `config :#{otp_app}, \
      ash_domains: [...]` insertion (see add_ash_domains_config!/3's \
      moduledoc), but the file's actual content did not match -- refusing to \
      regex-rewrite it.

      #{original}
      """
    end

    modules_src = Enum.join(domain_modules, ", ")
    domains_config = "config :#{otp_app}, ash_domains: [#{modules_src}]\n\n"

    updated = String.replace(original, marker, domains_config <> marker, global: false)

    File.write!(config_path, updated)
  end

  @doc "Runs `mix compile --warnings-as-errors` in `app_dir`."
  def compile!(app_dir) do
    cmd!("mix", ["compile", "--warnings-as-errors"], cd: app_dir)
  end

  @doc "Runs `mix test` in `app_dir`."
  def test!(app_dir) do
    cmd!("mix", ["test"], cd: app_dir)
  end
end
