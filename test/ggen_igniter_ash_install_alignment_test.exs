defmodule GgenIgniter.AshInstallAlignmentTest do
  @moduledoc """
  Qualifies the five REAL upstream *installer/extender* Igniter tasks that a
  ggen_igniter-manufactured `Igniter.Mix.Task` composes via
  `Igniter.compose_task/4`: `ash.install`, `ash_postgres.install`,
  `ash.extend`, `ash.patch.extend`, and `ash.set.domains`.

  ## The property under test

  ggen_igniter renders ONE composed task from an ontology; that task's only
  real leverage is the argv it hands to these upstream generators. So the
  property that actually matters is not "our renderer emitted a string" but
  "the argv we emit drives the real upstream task into the real project state
  we claim." Every assertion below therefore runs the genuine task module out
  of `deps/ash` / `deps/ash_postgres` against a real in-memory
  `Igniter.Test.test_project/1` and asserts on real resulting state -- created
  file content, real unified diffs, the real issue/notice/task lists -- never
  on "it did not crash."

  ## Why `ash_postgres.install`'s queued task is called out specially

  `ash_postgres.install` calls `Igniter.add_task/3` to queue
  `{"ash.codegen", ["initialize"]}`. That queue is precisely why a manufacture
  path must GUARD this step rather than treat it as just another idempotent
  generator: `Igniter`'s `halt_if_fails_check!/3`
  (`deps/igniter/lib/igniter.ex:1292-1340`) tests `!Enum.empty?(igniter.tasks)`
  and calls `System.halt(3)` **before** it ever reaches its
  `Igniter.has_changes?(igniter)` branch. A non-empty task queue therefore
  fails `--check` with a hard non-zero exit EVEN WHEN THE FILE DIFF IS EMPTY.
  Re-composing `ash_postgres.install` into an already-installed project is
  file-idempotent but still re-queues that task, so an unguarded manufacture
  path that runs it a second time under `--check` breaks a previously green
  build without changing a single byte on disk. `assert_has_task/3` below is
  the falsifier for that.

  ## Faker discipline

  Application names are Faker-generated, so the assertions about derived
  artifacts (the repo module `<Prefix>.Repo`, the path `lib/<prefix>/repo.ex`,
  the `config :<app>, ash_domains: [...]` key) can only pass via the real
  `app_name -> module -> path` derivation and never via a literal coincidence.
  Values that are an upstream CONTRACT -- the queued task name `"ash.codegen"`
  and its argv, the formatter keys `mix format` itself reads, the
  `ecto_repos`/`ash_domains` config keys -- stay literal, and each such site
  says why: substituting Faker there would assert nothing.

  ## Ordering constraint

  `apply_igniter/1` and `apply_igniter!/1` reset `tasks`, `warnings`,
  `notices` and `issues` to `[]`. Every `assert_has_task` / `assert_has_notice`
  / `assert_has_issue` / `assert_creates` below consequently runs BEFORE any
  apply.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Igniter.Test

  # `ash.extend`/`ash.patch.extend` call `Mix.Task.run("compile")` on the HOST
  # project and every task here writes through `Mix.shell()`, so these cannot
  # run concurrently with each other -- hence `async: false` above.

  # A Faker word alone can collide with an Elixir reserved word (`in`, `do`,
  # `end`), which would make the generated module name invalid; the numeric
  # suffix removes that hazard and also keeps two tests in the same run from
  # colliding on one app name.
  defp app_name do
    String.to_atom("#{Faker.Lorem.word()}_#{Faker.random_between(1000, 9999)}")
  end

  # Igniter derives the module prefix by camelizing the app atom and the source
  # DIRECTORY by underscoring that prefix again -- so `:rerum_4163` yields
  # module `Rerum4163` but path segment `rerum4163`, NOT `rerum_4163`. Deriving
  # the path from the atom directly would be wrong.
  defp module_prefix(app), do: Macro.camelize(Atom.to_string(app))
  defp path_prefix(app), do: Macro.underscore(module_prefix(app))

  # `ash.set.domains` writes unconditional progress chatter to stdout and its
  # "no domains found" report to stderr, and `ash.extend`'s unknown-extension
  # path prints to stdout. Capturing BOTH keeps the suite readable and makes
  # the real shell output itself assertable state.
  defp compose_capturing(igniter, task, argv) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            send(parent, {:igniter, Igniter.compose_task(igniter, task, argv)})
          end)

        send(parent, {:stdout, stdout})
      end)

    igniter =
      receive do
        {:igniter, value} -> value
      after
        5_000 -> raise "timed out waiting for {:igniter, value}"
      end

    stdout =
      receive do
        {:stdout, value} -> value
      after
        5_000 -> raise "timed out waiting for {:stdout, value}"
      end

    {igniter, stdout, stderr}
  end

  defp source_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp domain_source(prefix) do
    """
    defmodule #{prefix}.Blog do
      use Ash.Domain, validate_config_inclusion?: false

      resources do
      end
    end
    """
  end

  defp resource_source(prefix) do
    """
    defmodule #{prefix}.Blog.Post do
      use Ash.Resource, domain: #{prefix}.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """
  end

  defp project_with_resource(app) do
    prefix = module_prefix(app)
    dir = path_prefix(app)

    test_project(
      app_name: app,
      files: %{
        "lib/#{dir}/blog.ex" => domain_source(prefix),
        "lib/#{dir}/blog/post.ex" => resource_source(prefix)
      }
    )
  end

  describe "ash.install" do
    test "patches .formatter.exs so mix format loads the Spark plugin and ash's deps" do
      # `plugins:`, `Spark.Formatter` and `import_deps: [:ash, :reactor]` are the
      # literal keys `mix format` itself reads -- an upstream contract. A Faker
      # value here would assert nothing about formatting actually working.
      test_project(app_name: app_name())
      |> Igniter.compose_task("ash.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  plugins: [Spark.Formatter],
      + |  import_deps: [:ash, :reactor]
      """)
    end

    test "creates config/config.exs carrying the real ash backwards-compatibility flags" do
      test_project(app_name: app_name())
      |> Igniter.compose_task("ash.install", [])
      |> assert_creates("config/config.exs", fn content ->
        # These exact flags are what makes the install meaningful -- they opt the
        # project into Ash 4 behaviour. Asserting only "a config file exists"
        # would pass against an empty file.
        assert content =~ "config :ash,"
        assert content =~ "default_actions_require_atomic?: true"
        assert content =~ "redact_sensitive_values_in_errors?: true"

        # The Spark formatter section order is what keeps `mix format` from
        # reshuffling every generated Ash resource.
        assert content =~ "config :spark,"
        assert content =~ "\"Ash.Resource\": ["
        assert content =~ "section_order: ["
      end)
    end

    test "patches mix.exs with consolidate_protocols and the sourceror dev/test dep" do
      igniter =
        test_project(app_name: app_name())
        |> Igniter.compose_task("ash.install", [])

      assert_has_patch(igniter, "mix.exs", """
      + |      consolidate_protocols: Mix.env() != :dev
      """)

      # Ash's own DSL compilation needs sourceror; it is added dev/test-only.
      assert_has_patch(igniter, "mix.exs", """
      + |      {:sourceror, "~> 1.8", only: [:dev, :test]}
      """)
    end

    test "does NOT add {:ash, ...} to mix.exs -- the dep comes from igniter.install, not here" do
      # A manufacture path that composes `ash.install` and then assumes `:ash`
      # is now a declared dependency would be wrong. This pins that boundary.
      content =
        test_project(app_name: app_name())
        |> Igniter.compose_task("ash.install", [])
        |> source_content("mix.exs")

      refute content =~ "{:ash,"
      refute content =~ "{:ash_postgres,"
    end

    test "marks test/test_helper.exs changed via a newline-only edit that renders an EMPTY diff" do
      # FINDING, pinned deliberately rather than asserted around. Both
      # installers mark `test/test_helper.exs` as changed, but the ONLY
      # difference is a trailing newline (`ExUnit.start()` ->
      # `ExUnit.start()\n`), so `Igniter.diff/2` renders nothing at all for it.
      # That makes the path a trap in BOTH directions: `assert_has_patch/3` on
      # it fails (there is no diff text to match) and so does
      # `assert_unchanged/2` (the source really is marked changed).
      #
      # It also sharpens the `--check` story in this module's @moduledoc: on a
      # FIRST install, `--check` halts via the `has_changes?` branch partly on
      # account of a file whose visible diff is empty, which is a confusing
      # failure to debug from CI output alone.
      igniter =
        test_project(app_name: app_name())
        |> Igniter.compose_task("ash.install", [])

      assert Igniter.changed?(igniter, "test/test_helper.exs")
      assert diff(igniter, only: ["test/test_helper.exs"]) == ""

      source = Rewrite.source!(igniter.rewrite, "test/test_helper.exs")

      # Semantically identical, differing only in trailing whitespace -- the
      # precise reason the rendered diff is empty.
      assert String.trim(Rewrite.Source.get(source, :content)) ==
               String.trim(Rewrite.Source.get(source, :content, 1))
    end

    test "is idempotent: re-composing into an installed project changes nothing" do
      app = app_name()

      test_project(app_name: app)
      |> Igniter.compose_task("ash.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("ash.install", [])
      |> assert_unchanged()
    end

    test "--example generates the support resources under the Faker-derived app prefix" do
      app = app_name()
      prefix = module_prefix(app)
      dir = path_prefix(app)

      igniter =
        test_project(app_name: app)
        |> Igniter.compose_task("ash.install", ["--example"])

      # Path AND module both come from the generated app name, so this can only
      # pass via the real derivation.
      assert_creates(igniter, "lib/#{dir}/support/ticket.ex", fn content ->
        assert content =~ "defmodule #{prefix}.Support.Ticket do"
        assert content =~ "use Ash.Resource"
      end)

      assert_creates(igniter, "lib/#{dir}/support.ex", fn content ->
        assert content =~ "defmodule #{prefix}.Support do"
        assert content =~ "use Ash.Domain"
      end)
    end
  end

  describe "ash_postgres.install" do
    test "QUEUES ash.codegen initialize -- the reason the manufacture path guards this step" do
      # `"ash.codegen"` and `["initialize"]` are an upstream contract: they are
      # the exact task name and argv Igniter will shell out to. Faker here would
      # make the assertion vacuous.
      #
      # This must run BEFORE any apply -- `apply_igniter/1` resets `tasks` to [].
      test_project(app_name: app_name())
      |> Igniter.compose_task("ash_postgres.install", ["--yes"])
      |> assert_has_task("ash.codegen", ["initialize"])
    end

    test "re-queues ash.codegen on a second compose even though the file diff is empty" do
      # This is the falsifier for the moduledoc's `--check` claim: file
      # idempotence does NOT imply task-queue idempotence, and
      # `halt_if_fails_check!/3` halts on a non-empty task queue before it ever
      # looks at `has_changes?`.
      app = app_name()

      igniter =
        test_project(app_name: app)
        |> Igniter.compose_task("ash_postgres.install", ["--yes"])
        |> apply_igniter!()
        |> Igniter.compose_task("ash_postgres.install", ["--yes"])

      refute Igniter.changed?(igniter),
             "expected the second install to be file-idempotent, so the queued task is the " <>
               "only thing --check would trip on"

      assert_has_task(igniter, "ash.codegen", ["initialize"])
    end

    test "derives the repo module and its path from the Faker-generated app name" do
      app = app_name()
      prefix = module_prefix(app)
      dir = path_prefix(app)

      igniter =
        test_project(app_name: app)
        |> Igniter.compose_task("ash_postgres.install", ["--yes"])

      assert_creates(igniter, "lib/#{dir}/repo.ex", fn content ->
        assert content =~ "defmodule #{prefix}.Repo do"
        assert content =~ "use AshPostgres.Repo"
      end)

      assert_creates(igniter, "config/config.exs", fn content ->
        # `ecto_repos` is the literal key Ecto reads -- contract, not Faker. The
        # app atom and repo module on the RIGHT of it are Faker-derived.
        assert content =~ "config :#{app}, ecto_repos: [#{prefix}.Repo]"
      end)
    end

    test "patches .formatter.exs with import_deps: [:ash_postgres]" do
      test_project(app_name: app_name())
      |> Igniter.compose_task("ash_postgres.install", ["--yes"])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:ash_postgres]
      """)
    end

    test "patches mix.exs with the ash.setup test alias and the application module" do
      app = app_name()
      prefix = module_prefix(app)

      igniter =
        test_project(app_name: app)
        |> Igniter.compose_task("ash_postgres.install", ["--yes"])

      # The alias is what makes `mix test` set the database up first.
      assert_has_patch(igniter, "mix.exs", """
      + |    [test: ["ash.setup --quiet", "test"], setup: "ash.setup"]
      """)

      # The supervision tree entry is Faker-derived from the app name.
      assert_has_patch(igniter, "mix.exs", """
      + |      mod: {#{prefix}.Application, []}
      """)
    end

    test "configures the sandbox pool in config/test.exs against the derived repo" do
      app = app_name()
      prefix = module_prefix(app)

      test_project(app_name: app)
      |> Igniter.compose_task("ash_postgres.install", ["--yes"])
      |> assert_creates("config/test.exs", fn content ->
        assert content =~ "config :#{app}, #{prefix}.Repo,"
        # Chicago-style testing in the CONSUMER project depends on this exact
        # pool module, so it is a contract value.
        assert content =~ "pool: Ecto.Adapters.SQL.Sandbox"
        assert content =~ "config :ash, disable_async?: true"
      end)
    end

    test "emits a min_pg_version notice whose version is machine-dependent, not fixed" do
      # The task really shells out to `postgres -V`
      # (deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:498), so the
      # version literal differs per machine. Asserting the substring instead of
      # the number is the only assertion that is true everywhere AND still fails
      # if the notice stops being emitted.
      test_project(app_name: app_name())
      |> Igniter.compose_task("ash_postgres.install", ["--yes"])
      |> assert_has_notice(&String.contains?(&1, "min_pg_version"))
    end
  end

  describe "ash.extend" do
    test "adds the extension to the existing `use Ash.Resource` call" do
      app = app_name()
      dir = path_prefix(app)

      # `Ash.Notifier.PubSub` is a contract value: it is the extension module
      # name the task must resolve and splice in. It is also deliberately NOT
      # `Ash.Policy.Authorizer` -- see the skipped test below for why.
      argv = ["#{module_prefix(app)}.Blog.Post", "Ash.Notifier.PubSub"]
      {igniter, _out, _err} = compose_capturing(project_with_resource(app), "ash.extend", argv)

      assert igniter.issues == []

      assert_has_patch(igniter, "lib/#{dir}/blog/post.ex", """
      + |  use Ash.Resource, domain: #{module_prefix(app)}.Blog, notifiers: [Ash.Notifier.PubSub]
      """)
    end

    test "composing the same extension twice adds no duplicate (prepend_new_to_list)" do
      app = app_name()
      prefix = module_prefix(app)
      path = "lib/#{path_prefix(app)}/blog/post.ex"
      argv = ["#{prefix}.Blog.Post", "Ash.Notifier.PubSub"]

      {first, _out, _err} = compose_capturing(project_with_resource(app), "ash.extend", argv)
      {second, _out, _err} = compose_capturing(apply_igniter!(first), "ash.extend", argv)

      # Two independent falsifiers for "no duplicate was added":
      # (1) the second compose produces literally no change at all, and
      assert_unchanged(second)

      # (2) the extension name appears exactly once in the resulting source, so
      # a `notifiers: [Ash.Notifier.PubSub, Ash.Notifier.PubSub]` regression
      # fails here even if some future version made it a non-empty no-op diff.
      content = source_content(second, path)
      occurrences = length(String.split(content, "Ash.Notifier.PubSub")) - 1

      assert occurrences == 1,
             "expected Ash.Notifier.PubSub exactly once, got #{occurrences} in:\n#{content}"
    end

    test "an unresolvable extension becomes an issue, not a raise" do
      app = app_name()
      bogus = "Nope.#{Macro.camelize(Faker.Lorem.word())}.#{Faker.random_between(1000, 9999)}"

      {igniter, _out, _err} =
        project_with_resource(app)
        |> compose_capturing("ash.extend", ["#{module_prefix(app)}.Blog.Post", bogus])

      # An issue is recoverable inside a composed manufacture task; a raise is
      # not. Which one this is determines whether ggen_igniter can report a bad
      # ontology-derived extension name or just dies.
      assert_has_issue(igniter, &String.contains?(&1, "Could not find extension #{bogus}"))
      refute Igniter.changed?(igniter)
    end

    @tag skip: """
         Unexercisable under Igniter.Test: Ash.Policy.Authorizer is the only module in \
         deps/ash exporting install/5, and its install/5 calls \
         Igniter.apply_and_fetch_dependencies/2, which raises \
         "Cannot use `Igniter.apply_and_fetch_dependencies/1-2` in test mode" \
         (deps/igniter/lib/igniter.ex:956 <- ash/lib/ash/policy/authorizer/authorizer.ex:684 \
         <- ash.extend.ex:180). Missing: a real on-disk project with a real deps/ fetch. \
         The raise ITSELF is pinned by the assert_raise test immediately below; what stays \
         unverified here is the resulting `authorizers: [Ash.Policy.Authorizer]` patch.
         """
    test "adds authorizers: [Ash.Policy.Authorizer] to the resource" do
      flunk("see @tag skip reason -- requires a real deps fetch, not reachable in test mode")
    end

    test "an extension whose install/5 fetches deps raises rather than adding an issue" do
      app = app_name()

      # Documented as a real limit, and pinned so that if upstream ever converts
      # this into a recoverable issue, this test fails and the skipped test above
      # can be un-skipped. A raise ESCAPES compose_task entirely, so a
      # manufacture path cannot catch it as an issue.
      assert_raise RuntimeError, ~r/Cannot use `Igniter\.apply_and_fetch_dependencies/, fn ->
        compose_capturing(
          project_with_resource(app),
          "ash.extend",
          ["#{module_prefix(app)}.Blog.Post", "Ash.Policy.Authorizer"]
        )
      end
    end
  end

  describe "ash.patch.extend" do
    test "is a pure alias: produces byte-identical output to ash.extend" do
      app = app_name()
      path = "lib/#{path_prefix(app)}/blog/post.ex"
      argv = ["#{module_prefix(app)}.Blog.Post", "Ash.Notifier.PubSub"]

      {via_extend, _o1, _e1} = compose_capturing(project_with_resource(app), "ash.extend", argv)

      {via_patch, _o2, _e2} =
        compose_capturing(project_with_resource(app), "ash.patch.extend", argv)

      # `ash.patch.extend` delegates `igniter/1` verbatim to `ash.extend`. Equal
      # resulting SOURCE is the state-based way to assert that delegation --
      # far stronger than asserting both merely "succeeded."
      assert source_content(via_patch, path) == source_content(via_extend, path)
      assert via_patch.issues == []
    end

    test "composing the same extension twice adds no duplicate" do
      app = app_name()
      argv = ["#{module_prefix(app)}.Blog.Post", "Ash.Notifier.PubSub"]

      {first, _o, _e} = compose_capturing(project_with_resource(app), "ash.patch.extend", argv)
      {second, _o, _e} = compose_capturing(apply_igniter!(first), "ash.patch.extend", argv)

      assert_unchanged(second)
    end
  end

  describe "ash.set.domains" do
    test "writes every discovered domain into config under the Faker-generated app key" do
      app = app_name()
      prefix = module_prefix(app)

      {igniter, stdout, _stderr} =
        compose_capturing(project_with_resource(app), "ash.set.domains", [])

      # `ash_domains` is the literal key Ash reads -- contract. The app atom and
      # the domain module are both Faker-derived, so this line can only be
      # produced by real discovery of the seeded `use Ash.Domain` module.
      assert_creates(igniter, "config/config.exs", fn content ->
        assert content =~ "config :#{app}, ash_domains: [#{prefix}.Blog]"
      end)

      # The task's own report is real observable state and must agree with the
      # patch it made.
      assert stdout =~ "Found 1 domain(s)"
    end

    test "is a silent no-op with no issue when the project has no Ash.Domain module" do
      # The important half is `refute Igniter.changed?` PLUS `issues == []`: a
      # manufacture path that treats "no issue" as "domains were configured"
      # would be wrong, and this pins that the task reports the empty case only
      # on stderr.
      {igniter, _stdout, stderr} =
        compose_capturing(test_project(app_name: app_name()), "ash.set.domains", [])

      refute Igniter.changed?(igniter)
      assert igniter.issues == []
      assert stderr =~ "No modules utilizing `use Ash.Domain` were found."
    end

    test "is idempotent once the domain is already configured" do
      app = app_name()

      {first, _o, _e} = compose_capturing(project_with_resource(app), "ash.set.domains", [])
      {second, _o, _e} = compose_capturing(apply_igniter!(first), "ash.set.domains", [])

      assert_unchanged(second)
    end
  end
end
