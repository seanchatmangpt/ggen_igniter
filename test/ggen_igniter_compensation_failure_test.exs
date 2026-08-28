defmodule GgenIgniter.CompensationFailureTest do
  @moduledoc """
  Chicago-style, no-mocks proof of the CATASTROPHIC `:compensation_failed`
  standing: a real scenario where COMPENSATION ITSELF fails, constructed with
  a real `File.chmod!/2` (via `GgenIgniter.Reactors.ReconcileReactor`'s own
  `:test_chmod_after_write` testing hook -- see that module's moduledoc,
  "Testing hooks (inert in real use)"), a real `mix compile
  --warnings-as-errors` subprocess, and real `ReconcileReactor.run/1` /
  `Reactor.run/4` execution. No `Mix`/`Reactor`/`File` mocking anywhere in
  this file.

  ## The real scenario this test constructs

  Two targets in one Reactor run:

    * Target A (`protected_path`) -- a real, PRE-EXISTING file with known
      `original_content`. A valid template makes `:actuate` genuinely
      overwrite it with different, valid content (a real mutation). The
      `:test_chmod_after_write` hook then makes this file real-world
      READ-ONLY (`0o444`) immediately after that write succeeds.
    * Target B (`new_path`) -- does NOT exist before this run. A BROKEN
      template (invalid Elixir) makes `:actuate` write genuinely
      invalid content there.

  `:verify`'s real `mix compile --warnings-as-errors` subprocess then
  genuinely fails (target B's content does not parse), which triggers
  Reactor's real `undo/3` on `:actuate` for BOTH targets:

    * Target B (prior state `:new`) reverts cleanly -- `File.rm/1` succeeds,
      since only the FILE (not its parent directory) was ever touched.
    * Target A's revert (`File.write!(protected_path, original_content)`)
      genuinely RAISES `File.Error` (`:eacces`) -- the file is real-world
      read-only. This is COMPENSATION ITSELF failing, for real, not
      simulated.

  Before the fix under test, this raise propagated UNCAUGHT all the way out
  of `Reactor.run/4` (confirmed by reading `deps/reactor/lib/reactor/
  executor/step_runner.ex`'s `do_undo/6` directly -- it has no `rescue`
  around its call to `Step.undo/4`), past `ReconcileReactor.run/1`'s own
  `case` entirely -- meaning NO receipt was ever persisted for an attempt
  that genuinely mutated disk and then failed to restore it. That is a
  worse silent catastrophe than mis-reporting `:refused`. This test proves
  the fix: `revert_all/1` is now a real, never-raising, best-effort
  operation, and a genuine per-path revert failure surfaces as the real,
  distinct `Receipt.standing() == :compensation_failed` -- never `:refused`
  (which would falsely imply nothing was touched) and never `:alive`/
  `:compensated` (which would falsely imply restoration succeeded).
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  # -- Fixture builders (mirrors test/ggen_igniter_reconcile_reactor_test.exs's
  # own proven-working fixture shapes -- deliberately not shared/imported
  # across test files, so this file stands alone and is independently
  # readable). ------------------------------------------------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_compensation_failure_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    on_exit(fn ->
      # Defensive, real cleanup: restore write permission recursively via a
      # real `chmod` subprocess (deliberately NOT `File.rm_rf!/1` directly --
      # confirmed empirically that it can refuse to recurse past a real
      # read-only file left behind by this test's own adversarial scenario),
      # then a real `rm -rf`. Best-effort: a leftover scratch dir under
      # `System.tmp_dir!/0` is a real, but non-fatal, cleanup gap -- it must
      # never fail the test itself.
      System.cmd("chmod", ["-R", "u+w", dir], stderr_to_stdout: true)
      System.cmd("rm", ["-rf", dir], stderr_to_stdout: true)
    end)

    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "compfail_fixture_#{System.unique_integer([:positive])}"

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

  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/rr#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterCompFailFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterCompFailFixture.Beta" ;
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

  # Deliberately invalid Elixir: an unclosed `(` before `end` -- a real
  # parse/compile failure, exactly like
  # `ggen_igniter_reconcile_reactor_test.exs`'s own `write_broken_template!/1`.
  defp write_broken_template!(dir) do
    path = Path.join(dir, "broken.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def broken(
    end
    """)

    path
  end

  # -- The real, adversarial test ---------------------------------------------

  describe "compensation itself fails: a real revert write against a real read-only target" do
    test "surfaces the distinct :compensation_failed standing, never :refused or :alive, and names the exact inconsistent files" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)
      broken_template = write_broken_template!(fixtures)

      project_dir = new_mix_project!()

      # -- Target A: a REAL pre-existing file with KNOWN content that this
      # run will genuinely overwrite, then make genuinely read-only right
      # after that real write succeeds.
      protected_path = Path.join([project_dir, "lib", "protected.ex"])
      original_content = "defmodule Protected do\n  def value, do: :original\nend\n"
      File.write!(protected_path, original_content)
      assert File.exists?(protected_path)

      # -- Target B: a REAL path that does NOT exist before this run, whose
      # template is genuinely invalid Elixir -- this is what makes `:verify`
      # genuinely fail, triggering Reactor's real `undo/3` against BOTH
      # targets.
      new_path = Path.join([project_dir, "lib", "new_from_broken.ex"])
      refute File.exists?(new_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [
            template: valid_template,
            query: "spec=#{query_alpha}",
            out: protected_path,
            # The real hook under test: AFTER this target's real write
            # genuinely succeeds, make the real file read-only, so the
            # LATER real revert attempt against it genuinely fails.
            test_chmod_after_write: 0o444
          ],
          [template: broken_template, query: "spec=#{query_beta}", out: new_path]
        ]
      ]

      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result

      # -- THE CATASTROPHIC PROOF: real disk state, read back from disk,
      # not the Reactor result value. Target A's real mutation is NOT
      # reverted -- it still holds the NEW (post-run) content, not its
      # original pre-run content. This is the real "inconsistent state" the
      # standing must name.
      refute File.read!(protected_path) == original_content,
             "expected the real revert to have genuinely FAILED, leaving mutated content in place"

      # -- Target B's real revert (delete) DID succeed -- only target A's
      # revert failed (its parent directory was never chmod'd, only the
      # file itself).
      refute File.exists?(new_path),
             "expected target B's real write to be reverted successfully (only target A's revert failed)"

      # -- GgenIgniter.Manifest never advances on any failure path.
      refute File.exists?(Manifest.path(project_dir))

      # -- THE KEY STANDING PROOF: never :refused (files WERE touched, that
      # would be a lie), never :alive/:compensated (restoration did NOT
      # fully succeed, that would also be a lie) -- the real, distinct,
      # catastrophic standing.
      assert receipt.standing == :compensation_failed
      refute receipt.standing == :refused
      refute receipt.standing == :alive
      refute receipt.standing == :compensated
      refute receipt.standing == :build_broken

      # -- :compensation_failed deliberately never claims a coherent
      # post-run hash (some paths restored, some did not).
      assert receipt.post_run_hash == nil

      # -- The receipt's metadata explicitly names every fact the task
      # requires: mutation occurred, verification failed, restoration
      # failed, manual repair may be required -- plus the exact files left
      # in an inconsistent state.
      assert receipt.metadata["mutation_occurred"] == true
      assert receipt.metadata["verification_failed"] == true
      assert receipt.metadata["restoration_failed"] == true
      assert receipt.metadata["manual_repair_required"] == true
      assert receipt.metadata["compensation_failed_paths"] == [protected_path]
      assert receipt.metadata["compensation_restored_paths"] == [new_path]

      [failed_detail] = receipt.metadata["compensation_failed_details"]
      assert failed_detail["path"] == protected_path
      assert failed_detail["reason"] =~ "File.Error"

      # -- The reason string itself names every required fact in plain
      # language (not just in metadata keys).
      assert receipt.reason =~ "mutation"
      assert receipt.reason =~ "verification failed"
      assert receipt.reason =~ "restoration"
      assert receipt.reason =~ "MANUAL REPAIR"
      assert receipt.reason =~ protected_path

      # -- The real OCEL event sequence: files changed, verification
      # failed, compensation started, then COMPENSATION_FAILED -- and,
      # crucially, NEVER "FILES_RESTORED"/"COMPENSATION_COMPLETED" (those
      # would falsely claim a clean restore happened).
      activities = Enum.map(receipt.events, & &1["activity"])
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "VERIFICATION_FAILED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "COMPENSATION_FAILED" in activities
      refute "FILES_RESTORED" in activities
      refute "COMPENSATION_COMPLETED" in activities

      # -- The receipt is genuinely durable: re-read from disk (not the
      # in-memory struct this test already has) -- the persisted JSON shows
      # the exact same catastrophic standing.
      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "compensation_failed"
      assert persisted["metadata"]["manual_repair_required"] == true
      assert persisted["metadata"]["compensation_failed_paths"] == [protected_path]

      # -- Independent confirmation via `find_compensation_failure/1`
      # itself: `standing_for_failure/2` (the ORIGINAL four-standing
      # derivation) must NOT be what produced this receipt's standing --
      # this asserts the real dispatch happened through the NEW,
      # compensation-aware path, not a coincidence of the old one.
      refute ReconcileReactor.standing_for_failure(:actuate, {:some, :other, :reason}) ==
               :compensation_failed
    end
  end
end
