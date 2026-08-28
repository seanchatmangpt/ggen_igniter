defmodule GgenIgniter.ReconcileReactorTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.Reactors.ReconcileReactor`:
  real ontology files, real SPARQL queries (the `sparql` engine, no native
  NIF involved), real EEx templates, real `ReconcileReactor.run/1` calls,
  real `File.read!/1` disk checks, and a real `mix compile
  --warnings-as-errors` subprocess inside a real, minimal, scratch Mix
  project for `:verify`. No `Mix`/`Reactor` mocking anywhere in this file.

  Every scratch directory (fixture source files, and the target "actuated
  project" `:verify`'s `mix compile` runs against) is created fresh per test
  under `System.tmp_dir!/0` and removed in `on_exit/1`.

  ## CORRECTION (2026-08-27): "no receipt when :verify fails" was wrong

  A prior version of this file asserted `Receipt.read_all!(project_dir) ==
  []` after a real `:verify` failure -- "expected no receipt to exist when
  :verify fails". That is exactly backwards, per the user's own correction:

  > If files were actually changed -- even temporarily -- then a
  > consequential physical actuation occurred... the run receipt should
  > record ACTUATION_STARTED -> files A,B changed -> verification failed ->
  > compensation started -> A,B restored -> resulting project hash ==
  > pre-run hash -> standing = COMPENSATED.

  Fixed below: every test now calls `ReconcileReactor.run/1` (this module's
  own recommended entry point, which guarantees a persisted receipt on
  every path -- see its moduledoc) instead of a bare
  `Reactor.run(ReconcileReactor, %{...})`, and the compensation test asserts
  a real, persisted `standing: :build_broken` receipt (a compile failure IS
  the real build-broken case) whose `pre_run_hash` genuinely equals its
  `post_run_hash`, with the real OCEL event sequence the user described.
  `GgenIgniter.Manifest` still never advances on this path -- that part of
  the original assertion was, and remains, correct.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Controller
  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Reconcile
  alias GgenIgniter.Receipt

  # -- Fixture builders -------------------------------------------------------

  # A fresh scratch directory this test owns exclusively, removed on exit.
  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project: enough for a real `mix
  # compile --warnings-as-errors` subprocess to succeed or fail honestly on
  # whatever `:actuate` writes into its `lib/`.
  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "reactor_fixture_#{System.unique_integer([:positive])}"

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

  # ex:Alpha / ex:Beta -- two independent, single-row entities, each with its
  # own query file, so two targets in one run never collide on module name.
  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/rr#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterReactorFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterReactorFixture.Beta" ;
      ex:greeting "hello_from_beta" .
    """)

    path
  end

  defp write_query!(dir, name, subject) do
    path = Path.join(dir, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rr#>
    SELECT ?module_name ?greeting WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_valid_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # Deliberately invalid Elixir: an unclosed `(` before `end` -- a real parse
  # failure `mix compile` cannot paper over, not a semantic/type error.
  defp write_broken_template!(dir) do
    path = Path.join(dir, "broken.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def broken(
    end
    """)

    path
  end

  # -- Test 1: byte-for-byte parity with GgenIgniter.Reconcile.run/1 ---------

  describe "happy path: byte-for-byte parity with GgenIgniter.Reconcile.run/1" do
    test "the Reactor path produces the exact same real file content, for the same inputs" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      template_path = write_valid_template!(fixtures)

      baseline_dir = scratch_dir!()
      baseline_out = Path.join(baseline_dir, "alpha.ex")

      shared_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path
      ]

      # -- Baseline: the existing, direct GgenIgniter.Reconcile.run/1 pipeline.
      assert {:ok, baseline_result} = Reconcile.run(Keyword.put(shared_opts, :out, baseline_out))
      assert baseline_result.outcome == :written
      assert File.exists?(baseline_out)

      # -- Real Reactor pipeline, same ontology/query/template, writing into
      # a real scratch Mix project so :verify's real `mix compile` succeeds.
      project_dir = new_mix_project!()
      reactor_out = Path.join([project_dir, "lib", "alpha.ex"])

      reactor_opts =
        shared_opts
        |> Keyword.put(:out, reactor_out)
        |> Keyword.put(:manifest_dir, project_dir)
        |> Keyword.put(:verify_cwd, project_dir)

      assert {:ok, receipt} = ReconcileReactor.run(reactor_opts)
      assert receipt.standing == :alive
      assert receipt.metadata["outcome"] == "written"
      assert File.exists?(reactor_out)

      # -- The real, load-bearing proof: identical real file BYTES.
      assert File.read!(reactor_out) == File.read!(baseline_out)

      # A real receipt and a real manifest entry now exist on disk (the
      # Reactor path's own, disclosed addition over Reconcile.run/1, which
      # has neither) -- both real, checkable facts, not asserted structure.
      assert Receipt.read_all!(project_dir) != []
      assert File.exists?(Manifest.path(project_dir))

      # -- Canonical OCEL vocabulary coverage, success path: every real
      # attachment point tied to a real Reactor step fires, in the real
      # persisted receipt's own `events` list (read back from the real
      # ndjson file on disk, not the in-memory struct) -- not just the
      # in-memory receipt returned by `run/1`.
      persisted_activities =
        project_dir
        |> Receipt.read_all!()
        |> List.first()
        |> Map.fetch!("events")
        |> Enum.map(& &1["activity"])

      for activity <- [
            "RECONCILIATION_STARTED",
            "PLAN_CONSTRUCTED",
            "ADMISSION_ACCEPTED",
            "ACTUATION_STARTED",
            "FILES_CHANGED",
            "VERIFICATION_SUCCEEDED",
            "EVIDENCE_FINALIZED",
            "RECONCILIATION_ALIVE"
          ] do
        assert activity in persisted_activities,
               "expected #{activity} in the real persisted receipt's events: #{inspect(persisted_activities)}"
      end
    end
  end

  # -- Tests 2 & 3: the key compensation/undo proof, AND the receipt-on-every
  # -- admitted-attempt proof (correction A) ----------------------------------

  describe "a real failure at :verify reverts every file :actuate wrote" do
    test "restores pre-existing content, deletes the new file, and persists a real :build_broken receipt" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      broken_template = write_broken_template!(fixtures)

      project_dir = new_mix_project!()

      # A REAL pre-existing file, with KNOWN content, that this run will
      # overwrite (target A's output).
      existing_path = Path.join([project_dir, "lib", "existing.ex"])
      original_content = "defmodule Existing do\n  def value, do: :original\nend\n"
      File.write!(existing_path, original_content)
      assert File.exists?(existing_path)

      # A REAL path that does NOT exist before this run (target B's output).
      new_path = Path.join([project_dir, "lib", "new_from_run.ex"])
      refute File.exists?(new_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: broken_template, query: "spec=#{query_alpha}", out: existing_path],
          [template: broken_template, query: "spec=#{query_beta}", out: new_path]
        ]
      ]

      # Sanity: :actuate really does write invalid Elixir before :verify ever
      # runs -- confirmed independently, right below, by the fact that
      # `mix compile` on this exact broken content really fails (this is not
      # asserted here; it's what makes the overall `{:error, ...}` real).
      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result

      # -- THE KEY UNDO PROOF: real disk state, read back from disk, not the
      # Reactor result value.
      assert File.read!(existing_path) == original_content,
             "expected the pre-existing file's ORIGINAL content to be restored after :verify failed"

      refute File.exists?(new_path),
             "expected the file that did not exist before this run to be deleted again"

      # -- GgenIgniter.Manifest is unchanged behavior: it only ever advances
      # on a real, successful :alive standing.
      refute File.exists?(Manifest.path(project_dir)),
             "expected no manifest to be committed when :verify fails"

      # -- CORRECTION A, the key fix: a real receipt DOES exist for this
      # admitted attempt, even though it was compensated. A compile failure
      # here is the real, distinct :build_broken case (not a generic
      # :compensated) -- see ReconcileReactor.standing_for_failure/2.
      assert receipt.standing == :build_broken

      assert receipt.pre_run_hash != nil
      assert receipt.post_run_hash != nil

      assert receipt.pre_run_hash == receipt.post_run_hash,
             "expected the real post-compensation project hash to match the real pre-run hash"

      # -- The real OCEL event sequence the user described, present in the
      # persisted receipt verbatim.
      activities = Enum.map(receipt.events, & &1["activity"])
      assert "RECONCILIATION_STARTED" in activities
      assert "PLAN_CONSTRUCTED" in activities
      assert "ADMISSION_ACCEPTED" in activities
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "VERIFICATION_FAILED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "FILES_RESTORED" in activities
      assert "COMPENSATION_COMPLETED" in activities

      # -- The receipt is genuinely durable: re-reading it from disk (not
      # the in-memory struct this test already has) shows the same standing.
      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "build_broken"
      assert persisted["pre_run_hash"] == persisted["post_run_hash"]

      persisted_activities = persisted["events"] |> Enum.map(& &1["activity"])
      assert "COMPENSATION_COMPLETED" in persisted_activities

      # -- A second, corrected run (real templates this time) succeeds
      # cleanly afterward, proving the reverted state is a genuinely healthy
      # starting point, not a subtly-corrupted one.
      valid_template = write_valid_template!(fixtures)

      fixed_opts =
        reconcile_opts
        |> Keyword.put(:targets, [
          [template: valid_template, query: "spec=#{query_alpha}", out: existing_path],
          [template: valid_template, query: "spec=#{query_beta}", out: new_path]
        ])

      assert {:ok, fixed_receipt} = ReconcileReactor.run(fixed_opts)
      assert fixed_receipt.standing == :alive
      assert fixed_receipt.metadata["target_count"] == 2
      assert File.exists?(new_path)
      assert File.read!(existing_path) =~ "GgenIgniterReactorFixture.Alpha"
      assert File.exists?(Manifest.path(project_dir))
      assert length(Receipt.read_all!(project_dir)) == 2
    end
  end

  # -- Test 3b: the real generic :compensated standing (distinct from
  # :build_broken -- no :verify/compile step involved at all) ---------------

  describe "a real :actuate self-heal (not a :verify/compile failure) persists a real :compensated receipt" do
    test "one target succeeds, a second target's write genuinely raises, and compensation reverts the first" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)

      project_dir = new_mix_project!()

      # Target A: a real, valid out path this run will genuinely create.
      out_a = Path.join([project_dir, "lib", "compensated_a.ex"])
      refute File.exists?(out_a)

      # Target B: a real out path whose PARENT segment is pre-created as a
      # plain FILE (not a directory). `File.exists?/1` on the target itself
      # is genuinely false (the path can't be traversed -- its parent isn't
      # a directory), so BOTH the real `:render` step
      # (`PendingActuation.for_file/7`) and `actuate_one/2`'s own prior-read
      # check pass cleanly with no raise at all -- this is deliberately NOT
      # the same shape as a directory-at-target conflict, which genuinely
      # DOES raise during `:render`'s own planning read and was confirmed
      # (via a real run against this exact scenario) to produce a real
      # `:refused` standing instead, correctly, since nothing had been
      # actuated yet. Here, the real failure instead happens strictly
      # INSIDE `:actuate`'s own write (`Actuate.write_file!/3` ->
      # `File.mkdir_p!/1` genuinely raises `File.Error` "not a directory"
      # trying to create a directory where a plain file already sits) --
      # confirmed for real (via a real `elixir -e` run reproducing this
      # exact parent-is-a-file layout) before writing this test, not
      # assumed.
      blocker_file = Path.join([project_dir, "lib", "compensated_b_blocker.ex"])
      File.write!(blocker_file, "not a directory\n")
      out_b = Path.join(blocker_file, "nested.ex")
      refute File.exists?(out_b)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: valid_template, query: "spec=#{query_alpha}", out: out_a],
          [template: valid_template, query: "spec=#{query_beta}", out: out_b]
        ]
      ]

      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result

      # -- THE KEY UNDO PROOF: target A's real write was genuinely reverted
      # (deleted again, since it did not exist before this run) -- read from
      # real disk state, not the Reactor result value.
      refute File.exists?(out_a),
             "expected target A's real write to be reverted by :actuate's own self-heal"

      # -- Target B's real blocker file is untouched, and the target itself
      # was genuinely never created (the write raised before ever reaching
      # `File.write!/2`).
      assert File.read!(blocker_file) == "not a directory\n"
      refute File.exists?(out_b)

      refute File.exists?(Manifest.path(project_dir)),
             "expected no manifest to be committed when :actuate fails"

      # -- THE KEY DISTINCTION FROM :build_broken -- this failure never
      # reached :verify at all (no compile ever ran); it is the OTHER real
      # `standing_for_failure/2` branch: :actuate's own internal self-heal,
      # which maps to the GENERIC :compensated standing, not :build_broken.
      assert receipt.standing == :compensated

      assert receipt.pre_run_hash != nil
      assert receipt.post_run_hash != nil

      assert receipt.pre_run_hash == receipt.post_run_hash,
             "expected the real post-compensation project hash to match the real pre-run hash"

      # -- The real OCEL event sequence: files changed (A only), then
      # compensation, then restored -- and, crucially, NO verification event
      # at all, since :verify never ran.
      activities = Enum.map(receipt.events, & &1["activity"])
      assert "RECONCILIATION_STARTED" in activities
      assert "PLAN_CONSTRUCTED" in activities
      assert "ADMISSION_ACCEPTED" in activities
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "FILES_RESTORED" in activities
      assert "COMPENSATION_COMPLETED" in activities
      refute "VERIFICATION_FAILED" in activities
      refute "VERIFICATION_SUCCEEDED" in activities

      # -- The receipt is genuinely durable: re-read from disk (not the
      # in-memory struct this test already has).
      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "compensated"
      assert persisted["pre_run_hash"] == persisted["post_run_hash"]
    end
  end

  # -- Test 4: concurrency proof, and refusal-receipt proof -------------------

  describe "concurrency: independent targets run concurrently; colliding targets are refused" do
    test "two independent targets complete correctly with real overlapping write windows" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      out_a = Path.join([project_dir, "lib", "concurrent_a.ex"])
      out_b = Path.join([project_dir, "lib", "concurrent_b.ex"])

      probe = :"reactor_concurrency_probe_#{System.unique_integer([:positive])}"
      :ets.new(probe, [:set, :public, :named_table])

      delay_ms = 150

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [
            template: valid_template,
            query: "spec=#{query_alpha}",
            out: out_a,
            test_delay_ms: delay_ms,
            test_probe: probe
          ],
          [
            template: valid_template,
            query: "spec=#{query_beta}",
            out: out_b,
            test_delay_ms: delay_ms,
            test_probe: probe
          ]
        ]
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive
      assert receipt.metadata["target_count"] == 2
      assert File.exists?(out_a)
      assert File.exists?(out_b)
      assert File.read!(out_a) =~ "hello_from_alpha"
      assert File.read!(out_b) =~ "hello_from_beta"

      marks = :ets.tab2list(probe)
      start0 = fetch_mark!(marks, 0, :start)
      stop0 = fetch_mark!(marks, 0, :stop)
      start1 = fetch_mark!(marks, 1, :start)
      stop1 = fetch_mark!(marks, 1, :stop)

      # Real overlap check (monotonic milliseconds, not the Reactor result):
      # each write sleeps #{delay_ms}ms before writing, so a genuinely
      # SEQUENTIAL execution would have target 1 start at/after target 0's
      # stop (or vice versa) -- real concurrency means their windows overlap.
      assert start0 < stop1 and start1 < stop0,
             "expected two independent targets' real write windows to overlap via Reactor's " <>
               "own concurrency; got marks: #{inspect(marks)}"

      :ets.delete(probe)
    end

    test "two targets whose --out resolves to the SAME real path are refused, never last-writer-wins" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      collision_out = Path.join([project_dir, "lib", "collision.ex"])
      refute File.exists?(collision_out)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: valid_template, query: "spec=#{query_alpha}", out: collision_out],
          [template: valid_template, query: "spec=#{query_beta}", out: collision_out]
        ]
      ]

      result = ReconcileReactor.run(reconcile_opts)

      # The REAL, honest behavior of this implementation: :admit refuses the
      # entire run outright (see this module's own `admit_pending/2` and the
      # ReconcileReactor moduledoc's "Same-output-path collision" section) --
      # never a race, never silent last-writer-wins.
      assert {:error, receipt} = result

      refute File.exists?(collision_out),
             "expected NEITHER target to have written the colliding path -- a real refusal, not a race"

      # -- CORRECTION A: a fail-closed refusal BEFORE any actuation still
      # gets a real receipt -- standing :refused, no files ever touched.
      assert receipt.standing == :refused
      assert receipt.files == []
      refute Enum.any?(receipt.events, &(&1["activity"] == "ACTUATION_STARTED"))

      # -- Canonical vocabulary coverage, the real admission.refused path:
      # :render still real ran (a plan was genuinely constructed) before
      # :admit's own fail-closed duplicate-output-path check refused the
      # entire run -- ADMISSION_ACCEPTED never fires (admission was NOT
      # accepted), GUARD_REFUSED does.
      activities = Enum.map(receipt.events, & &1["activity"])
      assert "RECONCILIATION_STARTED" in activities
      assert "PLAN_CONSTRUCTED" in activities
      assert "GUARD_REFUSED" in activities
      refute "ADMISSION_ACCEPTED" in activities

      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "refused"
    end
  end

  # -- Opt-in wiring smoke test (Application.put_env/on_exit, flag enabled) --

  describe "opt-in wiring: use_reactor: true" do
    test "GgenIgniter.Controller.reconcile/3 routes through the real Reactor pipeline" do
      previous = Application.get_env(:ggen_igniter, :use_reactor, false)
      Application.put_env(:ggen_igniter, :use_reactor, true)
      on_exit(fn -> Application.put_env(:ggen_igniter, :use_reactor, previous) end)

      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      template_path = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "via_controller.ex"])

      {:ok, pid} = Controller.start_link([])

      opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, record} = Controller.reconcile(pid, :reactor_wiring_key, opts)
      assert File.exists?(out_path)
      assert File.read!(out_path) =~ "hello_from_alpha"
      assert record.receipt.out_path == out_path
    end
  end

  # -- Falsifier: real, per-operation-type compensation-completeness proof ---
  #
  # `:create`/`:replace` are already proven above ("a real failure at
  # :verify reverts every file :actuate wrote": one existing-file :replace
  # target and one new-file :create target both restored to their exact
  # real pre-run content, with real `pre_run_hash == post_run_hash`). The
  # two blocks below extend that same real, disk-verified proof to the two
  # remaining `PendingActuation.operation()` values `ReconcileReactor`
  # actually constructs today. `:inject` is NOT included: as of this test,
  # `GgenIgniter.PendingActuation` only defines `for_file/7` (:create/
  # :replace), `for_eval/3` (:eval), and `for_delete/5` (:delete) -- there is
  # no real `for_inject`/equivalent builder in this module, so `:inject`
  # compensation is genuinely untested here, not silently assumed to work.

  describe ":eval compensation-completeness: REAL FINDING -- unreachable, not just untested" do
    test "an :eval target crashes at :render before :admit/:actuate ever run" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      project_dir = new_mix_project!()

      eval_template_path = Path.join(fixtures, "eval.exs.eex")
      File.write!(eval_template_path, "1 + 1\n")

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: eval_template_path, mode: "eval", query: "spec=#{query_alpha}"]
        ]
      ]

      # -- REAL, REPRODUCIBLE FINDING (discovered while building this
      # falsifier, not asserted from reading code alone): a batch with an
      # `:eval` target -- even the ONLY target, no `:file` target involved
      # at all -- never reaches `:admit` or `:actuate`. It crashes inside
      # `:render`'s own `PLAN_CONSTRUCTED` telemetry emission:
      # `file_objects/1` (`Enum.map(pending, &OcelEmitter.file_object(&1.target))`)
      # calls `OcelEmitter.file_object/1` with `&1.target`, which is
      # ALWAYS `nil` for a real `PendingActuation.for_eval/3` item (see its
      # own moduledoc: "`target`/`previous_hash` are `nil`") --
      # `OcelEmitter.file_object/1` only defines a clause for
      # `is_binary(path)`, so this is a real, unconditional
      # `FunctionClauseError`, not a hypothetical edge case.
      #
      # Consequence for the compensation-completeness question this test
      # module exists to answer: `:eval` compensation is not "not needed"
      # (which would itself be a real, checkable claim about
      # `actuate_one/2`'s `tracked: nil` clause) -- it is UNREACHABLE. No
      # `:eval` item can ever reach `:actuate`, so `:actuate`'s
      # `undo/4`/`compensate/4` never gets a chance to prove or disprove
      # anything about it. `:eval` is not `:alive`, `:refused`, or any of
      # this pipeline's own vocabulary in the working sense -- it is a real,
      # standing production bug independent of compensation.
      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result
      assert receipt.standing == :refused
      assert receipt.reason =~ "FunctionClauseError"
      assert receipt.reason =~ "OcelEmitter"
      assert receipt.metadata["failed_step"] == ":render"

      # -- :actuate never ran (real, checkable non-event -- not an inference
      # from the crash's step name alone).
      refute Enum.any?(receipt.events, &(&1["activity"] == "ACTUATION_STARTED")),
             "expected :actuate to never run -- the crash happens one step earlier, at :render"
    end
  end

  # -- :delete has NO real compensation path in this reactor -- proven, not
  # -- assumed -----------------------------------------------------------

  describe ":delete compensation-completeness: real proof there is none" do
    test "a real, successful stale-prune deletion is NEVER reverted, even when a later item in the SAME prune batch genuinely fails" do
      fixtures = scratch_dir!()
      project_dir = new_mix_project!()

      # Two DIFFERENT template files with identical bodies -- this, not the
      # (identical, on purpose) `out_template` text, is what keeps
      # `Manifest.recipe_key/2` (built from `{template_path, out_template}`)
      # distinct per recipe below, since both recipes render their real
      # output path entirely from the `slug` binding (see moduledoc "The
      # `--pack` convention"'s sibling discussion of recipe identity).
      template_a = write_delete_template!(fixtures, "template_a")
      template_z = write_delete_template!(fixtures, "template_z")

      # Two independent, independently-renamable recipes (same real pattern
      # as ggen_igniter_admission_atomicity_test.exs's Gamma): each recipe's
      # `(template_path, out_template)` pair stays fixed across the two runs
      # below, but the RENDERED path moves because the `slug` binding
      # changes -- the real "resource renamed" event `--on-stale prune`
      # exists to clean up after.
      write_delete_ontology!(fixtures, "keep/a_old", "RecipeAOld", "lock/z_old", "RecipeZOld")

      query_a = write_delete_query!(fixtures, "spec_a", "RecipeA")
      query_z = write_delete_query!(fixtures, "spec_z", "RecipeZ")

      a_out_template = Path.join([project_dir, "lib", "<%= slug %>.ex"])
      z_out_template = Path.join([project_dir, "lib", "<%= slug %>.ex"])

      a_old_path = Path.join([project_dir, "lib", "keep", "a_old.ex"])
      z_old_path = Path.join([project_dir, "lib", "lock", "z_old.ex"])

      # -- Seed run: establishes real prior manifest entries recording
      # a_old_path/z_old_path as each recipe's only known output.
      seed_opts = [
        engine: "sparql",
        ontology: Path.join(fixtures, "ontology.ttl"),
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: template_a, query: "spec=#{query_a}", out: a_out_template],
          [template: template_z, query: "spec=#{query_z}", out: z_out_template]
        ]
      ]

      assert {:ok, seed_receipt} = ReconcileReactor.run(seed_opts)
      assert seed_receipt.standing == :alive
      assert File.exists?(a_old_path)
      assert File.exists?(z_old_path)

      # -- Lock lib/lock/ (no write permission) AFTER the seed write already
      # succeeded there -- this is what forces the SECOND stale delete
      # (z_old_path, alphabetically after a_old_path -- `Manifest.prune!/1`
      # sorts) to genuinely fail with a real `File.rm/1` permission error,
      # while the FIRST (a_old_path) has already, for real, been deleted.
      lock_dir = Path.join([project_dir, "lib", "lock"])
      File.chmod!(lock_dir, 0o500)
      on_exit(fn -> File.chmod(lock_dir, 0o700) end)

      # -- Rename both recipes' targets (real ontology mutation): the SAME
      # two recipes now render to NEW paths, leaving BOTH old paths stale
      # under `--on-stale prune`.
      # Module names change too (RecipeAOld/RecipeZOld -> RecipeANew/
      # RecipeZNew) -- otherwise the stale compiled `.beam` artifacts from
      # the seed run's `mix compile` (in `_build/`, untouched by
      # `Manifest.prune!/1`, which only ever deletes the real SOURCE files
      # this recipe tracks) would make the real `mix compile
      # --warnings-as-errors` in :verify below fail on an unrelated
      # "redefining module" warning -- irrelevant noise this test's real
      # point (delete compensation-completeness) has nothing to do with.
      write_delete_ontology!(fixtures, "fresh/a_new", "RecipeANew", "fresh/z_new", "RecipeZNew")

      a_new_path = Path.join([project_dir, "lib", "fresh", "a_new.ex"])
      z_new_path = Path.join([project_dir, "lib", "fresh", "z_new.ex"])

      batch_opts = [
        engine: "sparql",
        ontology: Path.join(fixtures, "ontology.ttl"),
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        on_stale: "prune",
        targets: [
          [template: template_a, query: "spec=#{query_a}", out: a_out_template],
          [template: template_z, query: "spec=#{query_z}", out: z_out_template]
        ]
      ]

      result = ReconcileReactor.run(batch_opts)

      # -- THE KEY, COUNTERINTUITIVE, REAL PROOF: this run is reported
      # `:alive`, NOT `:compensated`/`:build_broken`/`:compensation_failed`.
      # `finalize_evidence/1`'s prune step deliberately rescues its own
      # `Manifest.prune!/1` failure LOCALLY (see the module's own
      # "2026-08-27" hardening comment) rather than letting it fail the
      # step -- so Reactor's `undo/4` is NEVER triggered by a prune failure,
      # by design.
      assert {:ok, receipt} = result
      assert receipt.standing == :alive

      # -- Both new files were written successfully.
      assert File.exists?(a_new_path)
      assert File.exists?(z_new_path)

      # -- a_old_path: a REAL `operation: :delete` item that REALLY
      # actuated (File.rm/1 genuinely succeeded, sorted first). It is
      # PERMANENTLY GONE -- never restored, never even attempted to be
      # restored: no COMPENSATION_STARTED/FILES_RESTORED event exists
      # anywhere in this run's real event log for it, because nothing in
      # this reactor ever calls `revert_all/1` (the only real restoration
      # path this module has) against prune deletions -- `:finalize_evidence`
      # has no `compensate/4`/`undo/4` of its own (see the step's own
      # moduledoc comment: "No compensate/4/undo/4 of its own").
      refute File.exists?(a_old_path),
             "expected a_old_path's real stale-prune deletion to have genuinely happened"

      compensation_activities = [
        "COMPENSATION_STARTED",
        "FILES_RESTORED",
        "COMPENSATION_COMPLETED",
        "COMPENSATION_FAILED"
      ]

      refute Enum.any?(receipt.events, &(&1["activity"] in compensation_activities)),
             "expected ZERO compensation events for this run -- proving :delete's real " <>
               "deletion of a_old_path was never even considered for reversion, the real " <>
               "gap this test exists to name explicitly"

      # -- z_old_path: the SECOND stale target, whose real `File.rm/1` call
      # genuinely failed (locked parent dir) -- left exactly as it was,
      # NOT because anything reverted it, but simply because the deletion
      # attempt itself never succeeded.
      assert File.exists?(z_old_path),
             "expected z_old_path's real File.rm/1 failure to have left it untouched"

      # -- The real, persisted receipt records this genuine partial-prune
      # inconsistency in its metadata (never hidden), while still reporting
      # the run overall as :alive -- the real, load-bearing proof that
      # `:delete` compensation is not merely "untested" but by-construction
      # ABSENT: a partial deletion inside a batch that is itself reported
      # successful, with the deleted path gone for good.
      assert receipt.metadata["prune_outcome"] =~ "prune_failed"
    end
  end

  defp write_delete_ontology!(fixtures, a_slug, a_module_suffix, z_slug, z_module_suffix) do
    path = Path.join(fixtures, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/del#> .
    ex:RecipeA a ex:Module ;
      ex:moduleName "GgenIgniterDeleteFixture.#{a_module_suffix}" ;
      ex:slug "#{a_slug}" .
    ex:RecipeZ a ex:Module ;
      ex:moduleName "GgenIgniterDeleteFixture.#{z_module_suffix}" ;
      ex:slug "#{z_slug}" .
    """)

    path
  end

  defp write_delete_query!(fixtures, name, subject) do
    path = Path.join(fixtures, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/del#>
    SELECT ?module_name ?slug WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:slug ?slug .
    }
    """)

    path
  end

  # Only `module_name` is used in the body -- `slug` is real, query-bound
  # data used exclusively to render the real `out_template` path (see
  # `render_target/3`'s `Render.render(out_template, t.bindings)`), not
  # required inside the generated file's own content.
  defp write_delete_template!(fixtures, name) do
    path = Path.join(fixtures, "#{name}.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def value, do: :ok
    end
    """)

    path
  end

  defp fetch_mark!(marks, index, event) do
    case Enum.find(marks, fn {{i, e}, _ts} -> i == index and e == event end) do
      {{^index, ^event}, ts} ->
        ts

      nil ->
        flunk(
          "no #{inspect(event)} probe mark recorded for target index #{index}: #{inspect(marks)}"
        )
    end
  end
end
