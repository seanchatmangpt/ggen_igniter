defmodule GgenIgniter.AshManufacturePackTest do
  @moduledoc """
  Chicago-style proof that `test/fixtures/ash_manufacture_pack/` projects the
  ontology into a real, parseable, composed `Igniter.Mix.Task` -- and that the
  projection is DERIVED from semantic facts rather than from CLI strings
  stored in the ontology.

  Real subprocess, real oxigraph query engine, real rendered file on disk,
  real `Code.compile_string/2` of that file, real `Igniter.Test` composition
  of the module it defines. No doubles.

  ## Two oracles, and what each one can see

  The drift check (`bin/drift_check.py`) compares the ontology and the
  rendered invocation as SETS in both directions. It was falsified before
  being trusted: injecting an extra `--attribute` with no fact behind it, and
  deleting a projected fact, each make it exit 1 naming the specific item.
  That falsifiability is re-established here rather than assumed, so a drift
  check that silently stopped working cannot pass as a green run.

  Drift is a claim about ARGV. It says nothing about the rendered task's own
  control flow -- `apply_step/3`, which emits a refusal and skips composition
  when the step's guard module already exists and composes otherwise. That
  function is the idempotency mechanism the whole architecture rests on, so
  this file executes it instead of reading it:

    * `plan/0` and `refusals/0` are CALLED on the compiled module, so every
      step is inspected. The previous revision `String.split`'d the rendered
      SOURCE with `parts: 2` and therefore read only the first of two
      `ash.gen.resource` steps -- the second step's `guard:` was never seen by
      any assertion.
    * The compiled task is composed TWICE through `Igniter.Test`, and run 2 is
      asserted inert against the real `--check` predicate (no changes, no
      queued tasks, no issues, no warnings).
    * A negative control composes the raw upstream step into the same applied
      project and requires it to COLLIDE, which is what makes run 2's
      inertness attributable to `apply_step/3` rather than to upstream
      tolerance.

  ## Two preconditions the in-process runs must supply, and why

  A phase boundary in the real pack is an OS process boundary: run 2 is a
  separate `mix` invocation that boots the config run 1 wrote. `Igniter.Test`
  has no second process, so two real application-env values that the boundary
  would carry are set here directly, with real `Application.put_env/3` and with
  values read off the plan itself:

    * `:base_resources` -- `ash.gen.resource --base X` validates X against it
      (deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:152). This is the exact
      fact that forces the base/core split in the first place.
    * `:ash_domains` -- set BETWEEN the two core runs, not before run 1.
      `Ash.Domain.Igniter.add_resource_reference/3` asks `list_domains/1`
      whether the target is a domain, and that answer is this env plus a scan
      of the sources CHANGED in the current run
      (deps/ash/lib/ash/domain/igniter.ex:10-35). Run 1 writes the domain, so
      the scan finds it; run 2 touches nothing, so the env is the only evidence
      left. Without it the call falls through to
      `upgrade_plain_module_to_domain/4` and appends a SECOND `use Ash.Domain`
      and `resources` block to an already-correct domain. That was observed,
      not assumed -- it is what this file's first execution actually produced.

  ## What this file deliberately does not pin

  One workstream is replacing `ash_postgres.install`'s whole-task guard with a
  post-compose task drain. Both designs satisfy the invariant that actually
  matters (`igniter.tasks == []` on run 2), so the guard assertions below are
  written as structural rules -- "a guard, if present, observes its own
  step's subject", "a step never both guards and passes upstream's own
  admission flag" -- plus a per-task policy table in which that one task is
  explicitly unpinned. An assertion hard-coding today's guard would fail that
  landing for the wrong reason.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Igniter.Test

  @moduletag :integration

  @pack "test/fixtures/ash_manufacture_pack"

  # Ontology properties the template actually READS to build argv. Each must
  # hold a fact; none may hold a generator flag.
  @projected_properties ~w(attributeName attributeType extensionName primaryKeyKind
                           primaryKeyName relationshipKind relationshipName supportKind
                           supportModuleName enumValue domainModule resourceModule
                           mixTask phase standing)

  # The subset of the above whose values are drawn from a CLOSED vocabulary (a
  # real mix task name; base/core/lifecycle; the status vocabulary). They can
  # never structurally contain a CLI flag, so they inflate the apparent breadth
  # of the flag refutation without adding discriminating power. Named here so
  # the check's real strength is visible instead of implied.
  @closed_vocabulary_properties ~w(mixTask phase standing)

  # The keys `apply_step/3` destructures and the OCEL emitter reads. A step
  # missing `:guard` would silently take the unguarded clause. Asserted as a
  # REQUIRED SUBSET, not an exact set: a step may carry additional strategy
  # keys (`:drain_queued` is one, read through `Map.get/3` with a default), and
  # forbidding those would fail a legitimate extension.
  @required_plan_keys [:argv, :guard, :object_type, :phase, :step, :subject, :task]

  # Contract, from the manufactured task's own `## Usage` section: the plan is
  # actuated as `--phase base` then `--phase core`, two separate mix
  # invocations. Order is load-bearing, not cosmetic -- `ash.gen.resource
  # --base X` validates X against the application env, which only a PRIOR mix
  # run can populate.
  @expected_phases ["base", "core"]

  # This repo's status vocabulary. A refusal outside it is an unclassified
  # refusal.
  @standings ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED REFUSED)

  # Guard policy per UPSTREAM task. Stated once, as data, because each verdict
  # is a claim about upstream's re-run behaviour -- not about our renderer --
  # and each has an executed proof somewhere in this repo.
  #
  #   :guarded   -- upstream has no existence check and no `--ignore-if-exists`.
  #                 `Igniter.Project.Module.create_module/3` delegates to
  #                 `Igniter.create_new_file/3`, whose `on_exists:` default is
  #                 `:error`, so a second compose adds a "File already exists"
  #                 issue. Executed for the three support generators in
  #                 test/ggen_igniter_ash_gen_support_alignment_test.exs, and
  #                 for `ash.gen.base_resource` by the negative control in this
  #                 file.
  #   :unguarded -- upstream owns the admission check itself: `ash.gen.domain`
  #                 reads `--ignore-if-exists` off `argv_flags`
  #                 (deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex:35),
  #                 `ash.gen.enum`/`ash.gen.resource` declare
  #                 `ignore_if_exists: :boolean`, and `ash.gen.resource` also
  #                 skips creation via `ensure_resource_exists/5`. Adding our
  #                 own check would reimplement a fence upstream owns.
  #   :either    -- deliberately UNPINNED. `ash_postgres.install` is
  #                 file-idempotent but re-queues `ash.codegen initialize`
  #                 (test/ggen_igniter_ash_install_alignment_test.exs), and a
  #                 non-empty task queue fails `--check` on its own. A
  #                 whole-task guard and a post-compose task drain both fix
  #                 that; this file asserts the invariant (`tasks == []` on run
  #                 2), not the mechanism.
  @guard_policy %{
    "ash.install" => :unguarded,
    "ash_postgres.install" => :either,
    "ash.gen.base_resource" => :guarded,
    "ash.gen.domain" => :unguarded,
    "ash.gen.enum" => :unguarded,
    "ash.gen.resource" => :unguarded,
    "ash.gen.validation" => :guarded,
    "ash.gen.change" => :guarded,
    "ash.gen.preparation" => :guarded
  }

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_ash_manufacture_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    out = Path.join(dir, "manufacture.ex")

    {output, code} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack-dir",
          @pack,
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
    assert File.exists?(out), "sync reported success but wrote nothing:\n#{output}"

    %{out: out, source: File.read!(out), dir: dir}
  end

  test "renders a real, parseable Igniter.Mix.Task -- not Ash resource source", ctx do
    assert {:defmodule, _, _} = Code.string_to_quoted!(ctx.source)

    assert ctx.source =~ "defmodule Mix.Tasks.BookLibrary.Manufacture do"
    assert ctx.source =~ "use Igniter.Mix.Task"
    assert ctx.source =~ "Igniter.compose_task(igniter, step.task, step.argv)"

    # The whole point: ggen_igniter renders the MANUFACTURING TASK, and the
    # upstream generators render the Ash surfaces. A template that emitted
    # `use Ash.Resource` would be the exact failure this architecture exists
    # to prevent.
    refute ctx.source =~ ~r/^\s*use Ash\.Resource/m
    refute ctx.source =~ ~r/^\s*use Ash\.Domain/m
    refute ctx.source =~ ~r/^\s*attributes do/m
  end

  test "attribute modifiers are derived from boolean facts, not stored as flags", ctx do
    ontology = File.read!(Path.join(@pack, "ontology.ttl"))

    # The ontology states publicness/requiredness/sensitivity as booleans...
    assert ontology =~ "amp:isPublic true"
    assert ontology =~ "amp:isSensitive true"

    # ...and stores no generator flag as DATA. The precise claim is not
    # "the file never mentions a flag" -- rdfs:label/rdfs:comment/amp:evidence
    # naming the flag a property projects to is exactly the provenance this
    # pack should carry, and deleting it would make the ontology less
    # traceable, not more semantic. The claim is that no PROJECTED property
    # -- one the template actually reads to build argv -- has a flag in its
    # object position.
    scanned =
      Map.new(@projected_properties, fn property ->
        values =
          ~r/amp:#{property} "([^"]*)"/
          |> Regex.scan(ontology)
          |> Enum.map(fn [_match, value] -> value end)

        {property, values}
      end)

    # NON-VACUITY GATE, and it must run BEFORE the refutation below. The
    # previous revision was a single `for property <- ..., [_, value] <-
    # Regex.scan(...)` comprehension: a comprehension over zero matches yields
    # `[]` and reports success, so a prefix rename (`amp:` -> `ash:`), a
    # language tag (`"x"@en`) or a datatype suffix (`"x"^^xsd:string`) turned
    # the strongest-sounding assertion in this file into a silent no-op.
    for {property, values} <- scanned do
      assert values != [],
             "amp:#{property} matched nothing in ontology.ttl, so the flag refutation " <>
               "below would pass vacuously. Either the property was renamed or its " <>
               "literal form changed (language tag, datatype suffix, prefix)."
    end

    # Strength disclosure, so the breadth of this check is not read as stronger
    # than it is. Measured 2026-09-08 against this ontology: 104 scanned values,
    # of which 63 (mixTask/phase/standing, 21 each) come from closed
    # vocabularies that cannot structurally contain a flag. Only the remaining
    # open-vocabulary values can carry a smuggled one. Counts are recorded, not
    # pinned -- admitting one more capability legitimately changes all three.
    closed = Enum.flat_map(@closed_vocabulary_properties, &Map.fetch!(scanned, &1))
    open = Enum.flat_map(@projected_properties -- @closed_vocabulary_properties, &scanned[&1])

    assert closed != []
    assert open != [], "no open-vocabulary values remain; this check would discriminate nothing"

    for {property, values} <- scanned, value <- values do
      refute value =~ "--",
             "amp:#{property} carries the CLI fragment #{inspect(value)}; " <>
               "projected properties must hold facts, not generator flags"
    end

    # ...yet the rendered invocation carries the real modifiers, in the real
    # `name:type:modifier` shape ash.gen.resource parses.
    assert ctx.source =~ ~s("borrower_name:string:public:required:sensitive")
    assert ctx.source =~ ~s("isbn:string:public")
    assert ctx.source =~ ~s("--uuid-primary-key")
    assert ctx.source =~ ~s("--timestamps")
  end

  test "an inadmissible capability is refused with a typed reason, never composed", ctx do
    module = load_manufacture_task!(ctx)
    refusals = module.refusals()
    plan_tasks = MapSet.new(module.plan(), & &1.task)

    assert refusals != [], "refusals/0 is empty; every assertion below would be vacuous"

    for refusal <- refusals do
      assert refusal.standing in @standings,
             "#{refusal.mix_task} carries standing #{inspect(refusal.standing)}, which is " <>
               "outside the status vocabulary #{inspect(@standings)}"

      assert String.trim(refusal.reason) != "",
             "#{refusal.mix_task} is refused with no reason; a bare refusal is an omission"

      # The real invariant, executed rather than approximated. The previous
      # revision split the rendered SOURCE on "@refusals" and regex'd the first
      # half, which is a textual proxy for exactly this set disjointness.
      refute refusal.mix_task in plan_tasks,
             "#{refusal.mix_task} is both refused and composed; a refusal must remove the " <>
               "capability from the plan, not annotate it"
    end

    # ash.gen.custom_expression is BUILD_BROKEN upstream at ash 3.33.1: the
    # generator emits `args:` but Ash.CustomExpression.__using__/1 requires
    # `arguments:` and raises otherwise.
    custom = Enum.find(refusals, &(&1.mix_task == "ash.gen.custom_expression"))

    assert custom, "ash.gen.custom_expression is not refused at all"
    assert custom.standing == "BUILD_BROKEN"

    # The module IS modelled in the ontology, so its absence from the plan is
    # a derived refusal rather than an omission.
    assert File.read!(Path.join(@pack, "ontology.ttl")) =~
             "BookLibrary.Catalog.Expressions.TitleLength"
  end

  describe "plan/0, executed" do
    test "every step's guard is structurally admissible, all of them", ctx do
      module = load_manufacture_task!(ctx)
      plan = module.plan()

      assert plan != [], "plan/0 is empty; every assertion below would be vacuous"

      for step <- plan do
        missing = @required_plan_keys -- Map.keys(step)

        assert missing == [],
               "step #{inspect(step[:step])} is missing #{inspect(missing)}; apply_step/3 " <>
                 "destructures #{inspect(@required_plan_keys)}, and an absent :guard key " <>
                 "silently selects the unguarded clause"
      end

      # `chunk_by`, not `uniq`: a plan that interleaved base/core/base would
      # survive `uniq` (which yields ["base", "core"] for it) but cannot be
      # actuated by two mix invocations. `chunk_by` rejects it.
      phase_blocks = plan |> Enum.chunk_by(& &1.phase) |> Enum.map(&hd(&1).phase)

      assert phase_blocks == @expected_phases,
             "phase blocks are #{inspect(phase_blocks)}; the plan must be actuable as " <>
               "#{inspect(@expected_phases)}, in that order, each block contiguous"

      # A guard is only meaningful if it observes the step's OWN subject.
      # `guard: SomeOtherModule` would answer a different question than the step
      # asks, and would silently skip or repeat work. Derived from the plan, so
      # it survives a change of guard strategy.
      for step <- plan do
        assert step.guard == nil or step.guard == Igniter.Project.Module.parse(step.subject),
               "step #{step.step} guards on #{inspect(step.guard)} but its subject is " <>
                 "#{step.subject}; a guard must observe the subject it admits"
      end

      # Chesterton's fence as an executable rule: never both our guard AND
      # upstream's own admission flag. `--ignore-if-exists` is upstream's
      # contract string, not test data.
      for step <- plan do
        refute step.guard != nil and "--ignore-if-exists" in step.argv,
               "step #{step.step} both guards on #{inspect(step.guard)} and passes " <>
                 "--ignore-if-exists; one of the two checks is redundant"
      end
    end

    test "each composed task's guard matches its declared upstream policy", ctx do
      module = load_manufacture_task!(ctx)
      plan = module.plan()
      plan_tasks = MapSet.new(plan, & &1.task)

      # Bijection with the policy table, both directions. Left to right: a new
      # task cannot be admitted without classifying its real upstream re-run
      # behaviour. Right to left: a policy entry whose task left the plan would
      # otherwise sit here asserting nothing.
      for task <- plan_tasks do
        assert Map.has_key?(@guard_policy, task),
               "the plan composes #{task}, which has no declared guard policy. Classify it " <>
                 "against real upstream re-run behaviour before admitting it."
      end

      for {task, _policy} <- @guard_policy do
        assert task in plan_tasks,
               "@guard_policy classifies #{task}, which the plan no longer composes; the rule " <>
                 "for it now asserts nothing"
      end

      for step <- plan do
        case Map.fetch!(@guard_policy, step.task) do
          :guarded ->
            assert step.guard != nil,
                   "step #{step.step} composes #{step.task} unguarded, but that task has no " <>
                     "upstream existence check and no --ignore-if-exists: a second run adds a " <>
                     "\"File already exists\" issue and breaks --check"

          :unguarded ->
            assert step.guard == nil,
                   "step #{step.step} guards #{step.task} on #{inspect(step.guard)}, but that " <>
                     "task owns its own admission check; guarding it hides a real upstream " <>
                     "property behind ours"

          :either ->
            :ok
        end
      end
    end

    test "BOTH ash.gen.resource steps are unguarded, not just the first", ctx do
      module = load_manufacture_task!(ctx)
      resource_steps = Enum.filter(module.plan(), &(&1.task == "ash.gen.resource"))

      # Non-vacuity, and the reason this test exists. The previous revision
      # split the rendered source with `parts: 2` and inspected only the first
      # `ash.gen.resource` step; the second step's `guard:` was read by nothing.
      # Pinning a minimum of two makes that hole impossible to reopen quietly.
      assert length(resource_steps) >= 2,
             "expected at least two ash.gen.resource steps, got #{length(resource_steps)}; " <>
               "with fewer, the per-step assertion below covers no second step"

      for step <- resource_steps do
        assert step.guard == nil,
               "step #{step.step} (#{step.subject}) guards ash.gen.resource on " <>
                 "#{inspect(step.guard)}. That task is idempotent by construction " <>
                 "(ensure_resource_exists/5 plus the default --conflicts ignore), so a guard " <>
                 "here masks a real upstream property"
      end
    end
  end

  describe "apply_step/3, executed through Igniter.Test" do
    test "phase base: run 1 manufactures each guarded subject, run 2 is inert", ctx do
      module = load_manufacture_task!(ctx)
      steps = phase_steps(module, "base")

      assert steps != [], "phase base has no steps; this test would assert nothing"

      guarded = for %{guard: guard} <- steps, guard != nil, do: guard

      assert guarded != [],
             "phase base declares no guarded step, so run 1 below cannot distinguish a " <>
               "working guard branch from an inverted one"

      {first, _io} = compose_manufacture(test_project(app_name: app_name(module)), module, "base")

      # Run 1 MUST really create every guarded subject. Without this assertion
      # the whole test passes with the guard branch inverted (skip when the
      # module is absent, compose when present): run 1 would create nothing,
      # run 2 would also create nothing, and "unchanged" below would be
      # satisfied by a task that manufactured nothing at all.
      for guard <- guarded do
        path = Igniter.Project.Module.proper_location(first, guard)

        assert_creates(first, path, fn content ->
          assert content =~ "defmodule #{inspect(guard)} do"
        end)
      end

      {second, _io} = compose_manufacture(apply_igniter!(first), module, "base")

      # The real `--check` predicate, spelled out. `halt_if_fails_check!/3`
      # tests the task queue, the warnings and the issues BEFORE it ever looks
      # at `has_changes?`, so an unchanged diff alone would not prove run 2 is
      # green.
      assert_unchanged(second)

      assert second.tasks == [],
             "run 2 queued #{inspect(second.tasks)}; a non-empty task queue fails --check " <>
               "even with an empty file diff"

      assert second.issues == [], "run 2 raised issues: #{inspect(second.issues)}"
      assert second.warnings == [], "run 2 raised warnings: #{inspect(second.warnings)}"
    end

    test "run 2's inertness comes from the guard, not from upstream tolerance", ctx do
      module = load_manufacture_task!(ctx)
      step = guarded_step!(module, "base", "ash.gen.base_resource")

      applied =
        test_project(app_name: app_name(module))
        |> compose_manufacture(module, "base")
        |> elem(0)
        |> apply_igniter!()

      path = Igniter.Project.Module.proper_location(applied, step.guard)

      # NEGATIVE CONTROL. If `ash.gen.base_resource` were itself idempotent,
      # the previous test's inertness would say nothing about `apply_step/3`.
      # It is not: `create_module/3` -> `create_new_file/3` defaults to
      # `on_exists: :error`. The issue string is upstream's own contract text.
      {collided, _io} = compose_capturing(applied, step.task, step.argv)

      assert_has_issue(collided, "#{path}: File already exists")

      # ...and the manufactured task, over the very same project, does not.
      {second, _io} = compose_manufacture(applied, module, "base")
      assert second.issues == []
    end

    test "phase core: the support-module guards make run 2 inert", ctx do
      module = load_manufacture_task!(ctx)
      app = app_name(module)
      steps = phase_steps(module, "core")

      assert steps != [], "phase core has no steps; this test would assert nothing"

      guarded = for %{guard: guard} <- steps, guard != nil, do: guard

      assert guarded != [],
             "phase core declares no guarded step, so run 1 below cannot distinguish a " <>
               "working guard branch from an inverted one"

      # PRECONDITION 1, not a stub. `ash.gen.resource --base X` validates X
      # against `Application.get_env(app, :base_resources)`
      # (deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:152). In a real run that
      # env comes from config the PRIOR `--phase base` mix invocation
      # committed -- which is precisely why the plan is split into two phases.
      # In-process there is no second OS process to reload config, so the same
      # real application env is set here, with the value read off the plan's own
      # `--base` argument. Real API, real value; nothing is faked.
      restore_app_env(app, :base_resources, base_resources(module))

      {first, _io} = compose_manufacture(test_project(app_name: app), module, "core")

      assert first.issues == [], "run 1 raised issues: #{inspect(first.issues)}"
      assert first.warnings == [], "run 1 raised warnings: #{inspect(first.warnings)}"

      # Same inversion trap as the base-phase test: without this, an
      # apply_step/3 that skipped every guarded step would still satisfy the
      # "run 2 is unchanged" assertion below.
      for guard <- guarded do
        path = Igniter.Project.Module.proper_location(first, guard)

        assert_creates(first, path, fn content ->
          assert content =~ "defmodule #{inspect(guard)} do"
        end)
      end

      applied = apply_igniter!(first)

      # PRECONDITION 2, and a finding this test produced rather than assumed.
      # `Ash.Domain.Igniter.add_resource_reference/3` (called by every
      # `ash.gen.resource`) asks `list_domains/1` whether the target domain is
      # a domain. That answer is `Application.get_env(app, :ash_domains)` plus
      # a scan of the sources CHANGED in this run
      # (deps/ash/lib/ash/domain/igniter.ex:10-35). On run 1 the domain source
      # is freshly written, so the scan finds it; on run 2 nothing has touched
      # it, so the application env is the only remaining evidence. Without it
      # the call falls through to `upgrade_plain_module_to_domain/4`
      # (:177-205), which appends a SECOND `use Ash.Domain` and a second
      # `resources` block to an already-correct domain -- a real, observed
      # non-idempotency, reproduced and then removed by populating this env.
      #
      # A real actuation gets that env for free: run 2 is a separate mix
      # process that boots the `config :app, ash_domains: [...]` run 1 wrote.
      # In-process there is no second process, so the same real env is set
      # between the runs, at exactly the boundary the two mix invocations sit.
      restore_app_env(app, :ash_domains, domain_modules(module))

      {second, _io} = compose_manufacture(applied, module, "core")

      assert_unchanged(second)
      assert second.tasks == [], "run 2 queued #{inspect(second.tasks)}"
      assert second.issues == [], "run 2 raised issues: #{inspect(second.issues)}"
      assert second.warnings == [], "run 2 raised warnings: #{inspect(second.warnings)}"
    end
  end

  test "the ontology and the rendered invocation do not drift, in either direction", ctx do
    {out, code} =
      System.cmd("python3", [Path.join(@pack, "bin/drift_check.py"), @pack, ctx.out],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert code == 0, "drift detected:\n#{out}"

    report = Jason.decode!(out)
    assert report["no_drift"]
    assert report["drift"] == []
    assert report["steps"] > 0
    assert report["ontology_counts"]["attributes"] > 0
  end

  test "the drift check actually fails when the rendered task is hand-edited", ctx do
    # A check that cannot fail proves nothing. Inject an argument with no
    # ontology fact behind it -- the exact signature of an agent hand-editing
    # generated output -- and require the check to name it.
    tampered = Path.join(ctx.dir, "tampered.ex")

    File.write!(
      tampered,
      String.replace(
        ctx.source,
        ~s("isbn:string:public"),
        ~s("isbn:string:public",\n        "--attribute",\n        "smuggled:string:public")
      )
    )

    assert File.read!(tampered) =~ "smuggled", "tamper did not land; the test would be vacuous"

    {out, code} =
      System.cmd("python3", [Path.join(@pack, "bin/drift_check.py"), @pack, tampered],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert code == 1, "hand-edit went undetected:\n#{out}"
    assert Jason.decode!(out)["drift"] |> Enum.any?(&(&1 =~ "smuggled"))
  end

  # -- helpers ---------------------------------------------------------------

  # Loads the rendered file as REAL code. `:ignore_module_conflict` is set
  # around the call because every test in this file that needs the plan
  # compiles the same module name into the same VM; the render is
  # byte-identical across syncs, so the redefinition is a duplicate, not a
  # divergence.
  defp load_manufacture_task!(ctx) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    compiled =
      try do
        Code.compile_string(ctx.source, ctx.out)
      after
        Code.put_compiler_option(:ignore_module_conflict, previous)
      end

    tasks =
      for {module, _bytecode} <- compiled,
          match?(["Mix", "Tasks" | _], Module.split(module)),
          do: module

    case tasks do
      [module] ->
        module

      other ->
        flunk("expected the render to define exactly one Mix.Tasks module, got #{inspect(other)}")
    end
  end

  # The in-memory project must be the application the plan's modules belong to
  # -- `BookLibrary.Repo` is only derivable from `:book_library`. Derived from
  # the rendered task's own name rather than typed a second time.
  defp app_name(module) do
    module |> Module.split() |> Enum.at(2) |> Macro.underscore() |> String.to_atom()
  end

  defp phase_steps(module, phase), do: Enum.filter(module.plan(), &(&1.phase == phase))

  defp guarded_step!(module, phase, task) do
    step = Enum.find(phase_steps(module, phase), &(&1.task == task and &1.guard != nil))

    assert step, "no guarded #{task} step in phase #{phase}; this test would assert nothing"

    step
  end

  # Every module named by a `--base` argument anywhere in the plan. `--base` is
  # ash.gen.resource's own flag name, an upstream contract string.
  defp base_resources(module) do
    for step <- module.plan(),
        ["--base", value] <- Enum.chunk_every(step.argv, 2, 1, :discard),
        uniq: true,
        do: Igniter.Project.Module.parse(value)
  end

  # Every domain the plan manufactures, read off the steps that generate them.
  defp domain_modules(module) do
    for step <- module.plan(),
        step.task == "ash.gen.domain",
        uniq: true,
        do: Igniter.Project.Module.parse(step.subject)
  end

  # Sets a real application env value for the duration of the test and puts the
  # previous state back afterwards, so one test cannot leak a precondition into
  # another (this file is `async: false`, but the VM is shared with every other
  # suite in the run).
  defp restore_app_env(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, restored} -> Application.put_env(app, key, restored)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  # `--no-ocel` is a CONTRACT flag of the manufactured task itself (its
  # `schema: [ocel: :boolean]`). Without it the task writes a real OCEL log
  # into `.ggen_igniter/ocel/` in this repo's working directory, which a test
  # must not do. `--phase` is likewise the task's own flag.
  defp compose_manufacture(igniter, module, phase) do
    compose_capturing(igniter, module, ["--phase", phase, "--no-ocel"])
  end

  # Composed generators write progress chatter to both streams (`ash.extend`
  # prints to stdout, `ash.set.domains` to stderr), so both are captured and
  # returned as real observable state rather than leaked into the test report.
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

    result =
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

    {result, stdout <> stderr}
  end
end
