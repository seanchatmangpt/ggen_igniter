defmodule GgenIgniter.AshGenCoreAlignmentTest do
  @moduledoc """
  Chicago-style alignment tests for the four upstream Ash generators that the
  `ash_manufacture_pack` composes most: `ash.gen.domain`, `ash.gen.resource`,
  `ash.gen.enum` and `ash.gen.base_resource`.

  ## The property under test

  `test/fixtures/ash_manufacture_pack/templates/manufacture.ex.eex` renders ONE
  `Igniter.Mix.Task` whose only real work is turning semantic facts into upstream
  generator argv and handing that argv to `Igniter.compose_task/4`. The pack owns
  the *derivation*; upstream owns the *effect*. So the thing that can silently rot
  is the JOINT between them: an ontology boolean stops producing the modifier the
  pack thinks it produces, or an upstream generator's re-run behaviour changes and
  the pack's guard/`--ignore-if-exists` choice becomes wrong.

  Each test here therefore reproduces the pack's argv derivation verbatim
  (`manufacture.ex.eex:31-101`) and asserts on the REAL resulting state produced by
  the REAL upstream task module in `deps/ash` -- created-file content, config
  content, and the real `igniter.issues` list. Asserting "it did not crash" would
  not catch any of the drift this file exists to catch.

  ## Why this is the right property, and not a weaker one

  The pack's per-step `guard:`/`--ignore-if-exists` choices
  (`manufacture.ex.eex:219-271`) are *claims about upstream re-run behaviour*. The
  fixture run qualifies them end-to-end with Igniter's own `--check` oracle. These
  tests are the in-memory twin of that oracle: compose the SAME task a second time
  in the SAME project and assert the real re-run outcome. If upstream ever makes
  `ash.gen.base_resource` idempotent, or drops `ash.gen.domain`'s raw
  `argv_flags` scan, a test here fails and names the exact step whose guard is now
  wrong -- before the fixture's `--check` fails for a reason nobody can localize.

  ## Naming discipline

  Module names, app names, attribute names and enum values are Faker-generated so
  an assertion can only pass via the property it names, never via a literal that
  happens to appear in a template. Upstream CONTRACT strings (flag names, the
  `public`/`required`/`sensitive` modifier vocabulary, the `read`/`create`/
  `update`/`destroy` default-action vocabulary, the `postgres` extension short
  code) stay literal, and each is commented, because Faker-generating a contract
  would make the assertion meaningless.

  ## Anchoring discipline

  A Faker-generated name makes an assertion immune to a coincidental literal, but
  it does NOT bind the assertion to the right construct: when a test generates
  three attributes into one file, a whole-file search for `allow_nil?(false)`
  passes whether the modifier landed on the intended attribute, on a sibling, or
  on top of another modifier. So any claim about a construct that has SIBLINGS in
  the generated file is asserted through `attribute_block/3` or `defaults_call/1`,
  which match the enclosing block rather than the file.

  Assertions on constructs with no sibling -- the single `use` option list, the
  single `postgres do` block -- are left as substring matches on purpose. Anchoring
  those would have to pin the formatter's line-wrapping, which depends on the
  length of the Faker-generated names and is not a property of the derivation.
  """

  use ExUnit.Case, async: false

  import Igniter.Test

  describe "ash.gen.domain -- the pack's `gen_domain` step" do
    test "creates the domain module and registers it under the app's :ash_domains" do
      app = faker_app()
      domain = faker_module(2)
      igniter = test_project(app_name: app)
      domain_path = Igniter.Project.Module.proper_location(igniter, parse(domain))

      # Exactly `manufacture.ex.eex:232`: `[d["domain_module"], "--ignore-if-exists"]`.
      composed = Igniter.compose_task(igniter, "ash.gen.domain", [domain, "--ignore-if-exists"])

      assert_creates(composed, domain_path, fn content ->
        # `use Ash.Domain` and the `resources do end` block are the upstream
        # contract the pack's later `add_resource_reference` step writes into.
        assert content =~ "defmodule #{domain} do"
        assert content =~ "use Ash.Domain"
        assert content =~ "otp_app: #{inspect(app)}"
        assert content =~ "resources do"
      end)

      # The config registration is what makes the domain reachable at runtime; a
      # domain module with no `:ash_domains` entry is invisible to `mix ash.codegen`.
      assert_creates(composed, "config/config.exs", fn content ->
        assert content =~ "config #{inspect(app)}, ash_domains: [#{domain}]"
      end)
    end

    test "--ignore-if-exists survives compose_task, making the re-run a real no-op" do
      app = faker_app()
      domain = faker_module(2)
      argv = [domain, "--ignore-if-exists"]

      rerun =
        test_project(app_name: app)
        |> Igniter.compose_task("ash.gen.domain", argv)
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.domain", argv)

      # In-memory twin of the fixture's `--check` oracle for this step: zero diff
      # AND zero issues, which is what lets the pack leave `guard: nil` on it.
      assert rerun.issues == []
      assert_unchanged(rerun)
    end

    test "without --ignore-if-exists the same re-run raises a File already exists issue" do
      app = faker_app()
      domain = faker_module(2)
      igniter = test_project(app_name: app)
      domain_path = Igniter.Project.Module.proper_location(igniter, parse(domain))

      rerun =
        igniter
        |> Igniter.compose_task("ash.gen.domain", [domain])
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.domain", [domain])

      # This is the falsifier for the test above: it proves the flag is
      # load-bearing rather than decorative. `assert_has_issue/3`'s `path` argument
      # does NOT scope the match (it only decorates the failure message), so the
      # path is asserted here as part of the issue string itself, which upstream
      # really does embed.
      assert_has_issue(rerun, &String.contains?(&1, "#{domain_path}: File already exists"))
    end

    # The other half of the CLI-vs-compose asymmetry is deliberately NOT asserted
    # here. `ash.gen.domain` declares `schema: []` and reads the flag by raw string
    # scan of `igniter.args.argv_flags` (`deps/ash/.../ash.gen.domain.ex:35`), while
    # the real CLI path merges the global options in and parses with `strict:`
    # (`deps/igniter/lib/igniter/util/info.ex`), so `mix ash.gen.domain X
    # --ignore-if-exists` is rejected as an unknown option. Only `compose_task`'s
    # non-strict `switches:` parse lets it through -- which is precisely why the
    # pack composes instead of shelling out. Proving the rejecting half requires a
    # real CLI invocation; that belongs to the fixture run, not to an in-memory
    # `Igniter.Test` project, and asserting it here would be asserting nothing.
  end

  describe "ash.gen.base_resource -- the pack's `gen_base_resource` step" do
    test "creates a __using__ macro module and registers it under :base_resources" do
      app = faker_app()
      base = faker_module(2)
      igniter = test_project(app_name: app)
      base_path = Igniter.Project.Module.proper_location(igniter, parse(base))

      # Exactly `manufacture.ex.eex:223`: `[base_resource_module]`, no flags.
      composed = Igniter.compose_task(igniter, "ash.gen.base_resource", [base])

      assert_creates(composed, base_path, fn content ->
        # The macro shape is the whole point of a base resource: resources `use`
        # this module instead of `Ash.Resource`, so the `__using__`/`quote` pair
        # and the delegation target are the real contract.
        assert content =~ "defmodule #{base} do"
        assert content =~ "defmacro __using__(opts) do"
        assert content =~ "use Ash.Resource, unquote(opts)"
      end)

      # `ash.gen.resource --base X` validates X against this exact config key, so
      # a missing registration is what makes a later `--base` step raise.
      assert_creates(composed, "config/config.exs", fn content ->
        assert content =~ "config #{inspect(app)}, base_resources: [#{base}]"
      end)
    end

    test "re-running adds a File already exists issue -- this is why the pack guards it" do
      app = faker_app()
      base = faker_module(2)
      igniter = test_project(app_name: app)
      base_path = Igniter.Project.Module.proper_location(igniter, parse(base))

      rerun =
        igniter
        |> Igniter.compose_task("ash.gen.base_resource", [base])
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.base_resource", [base])

      # `ash.gen.base_resource` has no existence check and no --ignore-if-exists
      # flag, so `create_module -> create_new_file` hits its `on_exists: :error`
      # default. The pack's `guard: <base_resource_module>`
      # (`manufacture.ex.eex:224`) exists to skip the step before this happens.
      assert_has_issue(rerun, &String.contains?(&1, "#{base_path}: File already exists"))

      # An issue, not a diff: the failed step leaves the project untouched, which
      # is what makes the guard a correct fix rather than a papered-over one.
      assert_unchanged(rerun)
    end
  end

  describe "ash.gen.enum -- the pack's `gen_enum` step" do
    test "turns the ontology's enum values into a real Ash.Type.Enum values list" do
      app = faker_app()
      enum_mod = faker_module(3)
      [v1, v2, v3] = faker_words(3)
      igniter = test_project(app_name: app)
      enum_path = Igniter.Project.Module.proper_location(igniter, parse(enum_mod))

      # Exactly `manufacture.ex.eex:87-101` + `:241`: the values are comma-joined
      # into ONE positional argument, then `--ignore-if-exists` is appended.
      argv = [enum_mod, Enum.join([v1, v2, v3], ","), "--ignore-if-exists"]
      composed = Igniter.compose_task(igniter, "ash.gen.enum", argv)

      assert_creates(composed, enum_path, fn content ->
        assert content =~ "defmodule #{enum_mod} do"
        # Upstream splits on "," and maps `String.to_atom/1`, so the emitted list
        # is the inspected atom list -- asserted via `inspect/1` rather than a
        # hand-built ":#{v}" string so the assertion tracks upstream's own encoding.
        expected = inspect(Enum.map([v1, v2, v3], &String.to_atom/1))
        assert content =~ "use Ash.Type.Enum, values: #{expected}"
      end)
    end

    test "--ignore-if-exists makes the re-run a real no-op" do
      app = faker_app()
      enum_mod = faker_module(3)
      argv = [enum_mod, Enum.join(faker_words(2), ","), "--ignore-if-exists"]

      rerun =
        test_project(app_name: app)
        |> Igniter.compose_task("ash.gen.enum", argv)
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.enum", argv)

      assert rerun.issues == []
      assert_unchanged(rerun)
    end

    test "without --ignore-if-exists the same re-run raises a File already exists issue" do
      app = faker_app()
      enum_mod = faker_module(3)
      argv = [enum_mod, Enum.join(faker_words(2), ",")]
      igniter = test_project(app_name: app)
      enum_path = Igniter.Project.Module.proper_location(igniter, parse(enum_mod))

      rerun =
        igniter
        |> Igniter.compose_task("ash.gen.enum", argv)
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.enum", argv)

      assert_has_issue(rerun, &String.contains?(&1, "#{enum_path}: File already exists"))
    end
  end

  describe "ash.gen.resource -- the pack's `gen_resource` step" do
    test "every derived flag lands as the real Ash DSL construct it claims to produce" do
      %{app: app, domain: domain, resource: resource, base: base} = ctx = resource_context()
      pk = faker_attr()
      [public_attr, required_attr, sensitive_attr] = faker_attrs(3)

      igniter = install_base_resource(ctx)
      resource_path = Igniter.Project.Module.proper_location(igniter, parse(resource))

      # `manufacture.ex.eex:31-39` + `:65-85`, reproduced verbatim. The modifier
      # words and the flag names are upstream CONTRACT vocabulary
      # (`attribute_modifier_string/1` in ash.gen.resource.ex raises on anything
      # else), so they stay literal; every NAME is Faker-generated.
      argv =
        [resource] ++
          ["--uuid-primary-key", pk] ++
          ["--attribute", "#{public_attr}:string:public"] ++
          ["--attribute", "#{required_attr}:integer:public:required"] ++
          ["--attribute", "#{sensitive_attr}:string:public:sensitive"] ++
          ["--default-actions", "read,destroy,create,update"] ++
          ["--timestamps"] ++
          ["--base", base] ++
          ["--domain", domain]

      composed = Igniter.compose_task(igniter, "ash.gen.resource", argv)
      assert composed.issues == []

      assert_creates(composed, resource_path, fn content ->
        # `--base` replaces `use Ash.Resource`; `--domain` fills the domain option.
        assert content =~ "use #{base},"
        assert content =~ "otp_app: #{inspect(app)}"
        assert content =~ "domain: #{domain}"

        # `--uuid-primary-key <name>` -> a real uuid_primary_key attribute.
        assert content =~ "uuid_primary_key(:#{pk})"

        # One modifier -> one DSL option inside the block of the attribute that is
        # supposed to CARRY it. Each assertion matches a whole attribute block,
        # `do` through `end`, so it fails three separate ways: the modifier
        # vanishes, the modifier lands on the wrong attribute, or two modifiers
        # pile onto one attribute. A bare whole-file search for
        # `allow_nil?(false)` cannot distinguish any of those from success, since
        # all three attribute names are Faker-generated into the same file.
        assert content =~ attribute_block(public_attr, "string", ["public?(true)"])

        assert content =~
                 attribute_block(required_attr, "integer", ["public?(true)", "allow_nil?(false)"])

        assert content =~
                 attribute_block(sensitive_attr, "string", ["public?(true)", "sensitive?(true)"])

        # `--timestamps` -> the real timestamps() macro, inside `attributes do`.
        assert content =~ "timestamps()"

        # `--default-actions` -> a real `defaults` call: read/destroy as BARE
        # ATOMS and create/update carrying the accept list built from the PUBLIC
        # attributes only, all four in argv order. Anchoring to the `defaults(`
        # call is what makes this a claim about the actions block rather than
        # about the file -- a bare `":read,"` search matches any list anywhere.
        accept = inspect([public_attr, required_attr, sensitive_attr] |> Enum.map(&:"#{&1}"))

        assert content =~
                 defaults_call([
                   "[",
                   ":read,",
                   ":destroy,",
                   "create: #{accept},",
                   "update: #{accept}",
                   "]"
                 ])
      end)
    end

    test "a non-public attribute is generated but kept out of the create/update accept list" do
      %{domain: domain, resource: resource, base: base} = ctx = resource_context()
      [public_attr, private_attr] = faker_attrs(2)

      igniter = install_base_resource(ctx)
      resource_path = Igniter.Project.Module.proper_location(igniter, parse(resource))

      # An `amp:Attribute` with `amp:isPublic false` yields NO modifiers at all
      # (`manufacture.ex.eex:31-39`), so this is the real ontology-derived shape.
      argv =
        [resource] ++
          ["--attribute", "#{public_attr}:string:public"] ++
          ["--attribute", "#{private_attr}:string"] ++
          ["--default-actions", "create,update"] ++
          ["--domain", domain] ++
          ["--base", base]

      composed = Igniter.compose_task(igniter, "ash.gen.resource", argv)

      assert_creates(composed, resource_path, fn content ->
        # Both attributes really exist, in their two distinct shapes: no modifiers
        # means upstream emits a bare call the formatter parenthesizes, so the
        # parens themselves assert the ABSENCE of a block, and the anchored block
        # asserts `public?(true)` sits inside the public attribute specifically.
        assert content =~ "attribute(:#{private_attr}, :string)"
        assert content =~ attribute_block(public_attr, "string", ["public?(true)"])

        # ...but only the public one is acceptable input. This is the falsifier for
        # the accept-list assertion in the test above: if upstream ever accepted
        # every attribute, that test would still pass and this one would fail.
        # Upstream drops the outer list brackets here because every element is a
        # keyword -- unlike the read/destroy case above, which keeps them.
        assert content =~
                 defaults_call(["create: [:#{public_attr}],", "update: [:#{public_attr}]"])

        # The refute is anchored INTO the accept lists rather than left as a bare
        # `":#{private_attr}]"` search. That bare form only caught a leaked
        # attribute in LAST position: `create: [:private, :public]` contains no
        # `:private]` substring at all, so the leak this test exists to detect
        # slipped through whenever it was not the final element.
        refute content =~ ~r/(?:create|update): \[[^\]]*:#{private_attr}\b/
      end)
    end

    test "re-running the identical derived argv is idempotent -- the pack leaves it unguarded" do
      %{domain: domain, resource: resource, base: base} = ctx = resource_context()
      pk = faker_attr()
      [attr] = faker_attrs(1)

      argv =
        [resource] ++
          ["--uuid-primary-key", pk] ++
          ["--attribute", "#{attr}:string:public"] ++
          ["--default-actions", "read,create"] ++
          ["--timestamps"] ++
          ["--base", base] ++
          ["--domain", domain]

      rerun =
        ctx
        |> install_base_resource()
        |> Igniter.compose_task("ash.gen.resource", argv)
        |> apply_igniter!()
        |> Igniter.compose_task("ash.gen.resource", argv)

      # In-memory twin of the fixture's `--check` oracle for the step the pack
      # deliberately leaves `guard: nil` on (`manufacture.ex.eex:251-256`):
      # `ensure_resource_exists/5` skips creation when the module is found and the
      # default `--conflicts ignore` skips already-present attributes and actions.
      assert rerun.issues == []
      assert_unchanged(rerun)
    end

    test "--extend derived from ontology extensions emits the real data layer and its block" do
      %{app: app, domain: domain, resource: resource, base: base} = ctx = resource_context()
      pk = faker_attr()

      igniter = install_base_resource(ctx)
      resource_path = Igniter.Project.Module.proper_location(igniter, parse(resource))

      # "postgres" is an upstream CONTRACT short code (`ash.extend`'s resource-only
      # alias table); Faker-generating it would just produce a "Could not find
      # extension" issue and assert nothing.
      argv =
        [resource] ++
          ["--uuid-primary-key", pk] ++
          ["--extend", "postgres"] ++
          ["--timestamps"] ++
          ["--base", base] ++
          ["--domain", domain]

      composed = Igniter.compose_task(igniter, "ash.gen.resource", argv)
      assert composed.issues == []

      repo = Macro.camelize(Atom.to_string(app)) <> ".Repo"
      last_segment = resource |> String.split(".") |> List.last() |> Macro.underscore()

      assert_creates(composed, resource_path, fn content ->
        # The extension really rewrote the `use` options...
        assert content =~ "data_layer: AshPostgres.DataLayer"

        # ...and really added the data-layer's own DSL section. The repo module is
        # derived from the Faker app name, so this cannot pass by coincidence. The
        # table name is asserted as a prefix because upstream pluralizes it.
        assert content =~ "postgres do"
        assert content =~ "repo(#{repo})"
        assert content =~ "table(\"#{last_segment}"
      end)
    end

    test "--base raises when no base resource was generated into the project at all" do
      %{app: app, domain: domain, resource: resource, base: base} = resource_context()

      # `ash.gen.resource` validates `--base` against
      # `Application.get_env(app_name, :base_resources)`. It is a raise, not an
      # issue, so it escapes `compose_task` entirely and would abort a whole
      # manufacture run rather than degrade it -- which is why the pack treats the
      # base resource as a hard ordering prerequisite.
      argv = [resource, "--base", base, "--domain", domain]

      assert_raise RuntimeError, ~r/is not in the list of base resources/, fn ->
        Igniter.compose_task(test_project(app_name: app), "ash.gen.resource", argv)
      end
    end

    test "--base is accepted in the SAME run as ash.gen.base_resource, contra the pack docs" do
      %{app: app, domain: domain, resource: resource, base: base} = resource_context()

      # DISCREPANCY, measured not assumed. `manufacture.ex.eex:142-145` justifies
      # the pack's two-phase split by claiming "config written earlier in the same
      # Igniter run is not yet in the application environment, so the base
      # resource must be committed by a PRIOR mix invocation". Under igniter 0.8.3
      # that premise is FALSE: `Igniter.Project.Config.configure/5` -- which
      # `ash.gen.base_resource` calls -- formats the config source it just
      # touched, and `Igniter.format/2` evaluates it with `Config.Reader.eval!`
      # and `Application.put_all_env/1` so formatter plugins can read it
      # (`deps/igniter/lib/igniter.ex:1656-1701`). Its `after` clause restores by
      # merging the PREVIOUS env back, and `put_all_env/1` merges rather than
      # replaces, so a key that did not exist before is never removed. The value
      # therefore lands in the real VM application environment immediately, at
      # compose time, with no apply and no second mix invocation.
      assert Application.get_env(app, :base_resources) == nil

      igniter =
        test_project(app_name: app)
        |> Igniter.compose_task("ash.gen.base_resource", [base])

      assert Application.get_env(app, :base_resources) == [parse(base)]

      # Consequence: the single-run composition the pack's docs say cannot work
      # does work, with zero issues.
      argv = [resource, "--base", base, "--domain", domain]
      composed = Igniter.compose_task(igniter, "ash.gen.resource", argv)

      assert composed.issues == []
      resource_path = Igniter.Project.Module.proper_location(igniter, parse(resource))
      assert_creates(composed, resource_path, fn content -> assert content =~ "use #{base}," end)
    end
  end

  # ---- anchored structural matchers -----------------------------------------

  # A regex matching ONE attribute's whole `do`/`end` block, with exactly the
  # given DSL options, in order. Binding each modifier to its own attribute is
  # what makes the modifier assertions falsifiable: every attribute name in a
  # test is Faker-generated into the SAME file, so a whole-file search for
  # `allow_nil?(false)` passes just as happily when the modifier is attached to
  # the wrong attribute, or when two modifiers pile onto one.
  #
  # Option ORDER is upstream's own derivation, not an artifact of formatting:
  # `attribute_modifier_string/1` maps over the argv modifiers in argv order
  # (`deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:218-245`). Listing every
  # option and closing on `end` also makes the block EXHAUSTIVE, so an extra
  # modifier arriving from nowhere fails too.
  #
  # `\n\s*` rather than a fixed indent: a `do` block is always multi-line, but
  # its indentation depends on nesting depth, which is not what is under test.
  defp attribute_block(name, type, options) do
    body = Enum.map_join(options, "", fn option -> "\\n\\s*" <> Regex.escape(option) end)
    Regex.compile!("attribute :#{name}, :#{type} do" <> body <> "\\n\\s*end")
  end

  # A regex matching the real `defaults(...)` call with the given literal
  # fragments in order. `\s*` between fragments absorbs the formatter's line
  # wrapping, which depends on the Faker-generated name lengths and so must not
  # be asserted; the fragment ORDER is upstream's (`Enum.sort_by/2` at
  # `ash.gen.resource.ex:140`, joined at `:607-620`) and is asserted.
  defp defaults_call(fragments) do
    body = Enum.map_join(fragments, "\\s*", &Regex.escape/1)
    Regex.compile!("defaults\\(\\s*" <> body <> "\\s*\\)")
  end

  # ---- real-collaborator setup (no doubles) ---------------------------------

  # Runs the REAL `ash.gen.base_resource` and commits it, which is the state
  # `--base` requires. No `Application.put_env/3` is needed or wanted here: the
  # generator's own `Igniter.Project.Config.configure/5` call already writes the
  # value through into the real VM application environment -- see the
  # "contra the pack docs" test above for the measured mechanism. Setting it by
  # hand would mask that behaviour instead of exercising it.
  #
  # The `on_exit` deletes rather than restores because that write-through is a
  # one-way leak (`put_all_env/1` merges, so igniter's own restore cannot remove a
  # newly added key); `faker_app/0` registers that cleanup once, for every key.
  defp install_base_resource(%{app: app, base: base}) do
    test_project(app_name: app)
    |> Igniter.compose_task("ash.gen.base_resource", [base])
    |> apply_igniter!()
  end

  defp resource_context do
    root = faker_segment()
    domain = root <> "." <> faker_segment()

    %{
      app: faker_app(),
      base: root <> "." <> faker_segment(),
      domain: domain,
      resource: domain <> "." <> faker_segment()
    }
  end

  # ---- Faker-derived names --------------------------------------------------

  defp parse(module_name), do: Igniter.Project.Module.parse(module_name)

  # A latin-only lowercase word. Faker's lorem corpus is latin, but a word can
  # carry punctuation, and the empty remainder must not silently become a literal
  # fallback -- so this retries instead of substituting a hardcoded default.
  defp faker_word do
    case Faker.Lorem.word() |> String.downcase() |> String.replace(~r/[^a-z]/, "") do
      "" -> faker_word()
      word -> word
    end
  end

  defp faker_words(count), do: Enum.map(1..count, fn _ -> faker_word() <> unique() end)

  # Attribute names must satisfy upstream's `~r/^[a-zA-Z][a-zA-Z0-9_]*[!?]?$/`.
  defp faker_attr, do: faker_word() <> "_" <> unique()
  defp faker_attrs(count), do: Enum.map(1..count, fn _ -> faker_attr() end)

  defp faker_segment, do: Macro.camelize(faker_word()) <> unique()

  # Every app name is distinct, so no test can see another's config. The cleanup
  # is still required: these generators write their config through into the real
  # VM application environment (mechanism measured in the "contra the pack docs"
  # test), and that write-through is one-way, so without this the suite would
  # leave stale entries behind for every app name it ever invented.
  defp faker_app do
    app = String.to_atom(faker_word() <> unique())

    on_exit(fn ->
      Enum.each(Application.get_all_env(app), fn {key, _} -> Application.delete_env(app, key) end)
    end)

    app
  end

  # Distinctness across names within one test; the NAME itself is still Faker's.
  defp unique, do: Integer.to_string(System.unique_integer([:positive]))

  defp faker_module(segments) do
    1..segments |> Enum.map_join(".", fn _ -> faker_segment() end)
  end
end
