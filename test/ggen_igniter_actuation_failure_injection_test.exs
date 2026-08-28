defmodule GgenIgniter.ActuationFailureInjectionTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.Reactors.ReconcileReactor`'s
  compensation engine under REAL mid-actuation failure injection. Real
  scratch Mix projects, real ontology/query/template fixtures, real
  `ReconcileReactor.run/1` calls, real `File.read!/1` disk checks, and (for
  the `:verify` scenario) a real `mix compile --warnings-as-errors`
  subprocess. No mocking of `File`, `Reactor`, `Mix`, or any collaborator
  anywhere in this file.

  ## Why this file exists alongside `ggen_igniter_reconcile_reactor_test.exs`

  That file's compensation test exercises `:verify` failing (a broken
  template makes `mix compile` fail) AFTER `:actuate` has already returned
  success -- Reactor's real `undo/4` hook (`:actuate`'s `undo fn` in
  `reconcile_reactor.ex`), triggered by a LATER step's failure.

  This file additionally, and separately, exercises `:actuate`'s OWN run
  failing PARTWAY THROUGH its own work -- one of two concurrent targets
  writes successfully, the other raises a real filesystem error -- which is
  `:actuate`'s internal SELF-HEAL path (`actuate_pending/2`'s `errors != []`
  branch in `reconcile_reactor.ex`, reverting via `revert_all/1` before ever
  returning `{:error, ...}`), triggering `compensate/4` (a documented no-op,
  since self-heal already ran), NOT `undo/4`. Before this file, no test in
  this repo exercised that code path at all -- see
  `reconcile_reactor.ex`'s own moduledoc, "`compensate/4` vs `undo/4`" for
  the real distinction Reactor's own `Reactor.Step` behaviour draws between
  the two hooks.

  ## The real failure injected for the `:actuate` self-heal scenario

  The second of two targets' `--out` path is deliberately made unwritable by
  pre-creating a REGULAR FILE at what would otherwise be that target's own
  parent directory -- so `Actuate.write_file!/3`'s real
  `File.mkdir_p!(Path.dirname(path))` genuinely raises `File.Error`
  ("not a directory"), confirmed empirically (see the real probe run before
  this file was written: `File.mkdir_p!` against a path whose parent
  component already exists as a plain file raises
  `%File.Error{reason: :notdir}` with message "not a directory"). This is
  deliberately NOT a permission-bit (`File.chmod!/2`) injection: this
  session's Mix builds run under a lock shared with a concurrent process,
  and a root-executed test runner can silently ignore Unix permission bits
  entirely, which would make a chmod-based injection non-portable and
  potentially silently inert. A blocked path COMPONENT fails unconditionally,
  regardless of the running user's privileges.

  ## The whole-directory-tree hash proof (task requirement 3)

  Beyond `GgenIgniter.Receipt`'s own self-reported `pre_run_hash`/
  `post_run_hash` (which only cover the exact files ONE attempt touched --
  see `Receipt`'s moduledoc), each test here ALSO computes its own
  independent SHA-256 digest over every real file under the actuated
  project directory, before the run and after full compensation, using
  `hash_tree!/2` below -- built from a real recursive `File.ls!/1` walk, not
  trusting any value the pipeline itself reports. This is deliberately a
  SEPARATE, adversarial check: the pipeline could in principle compute
  `pre_run_hash == post_run_hash` correctly while some OTHER file in the
  project silently changed; the whole-tree hash rules that out.

  One real, disclosed exclusion: `.ggen_igniter/` (receipts + manifest
  cache) is excluded from the whole-tree hash. This is intentional, not a
  loophole -- `GgenIgniter.Receipt`'s own moduledoc states its job is to
  record "what was ATTEMPTED, every time, regardless of outcome"; a
  genuinely compensated attempt is REQUIRED to append a new receipt line
  (that append is itself the proof an attempt happened and was reverted).
  Asserting the whole tree identical INCLUDING `.ggen_igniter/` would assert
  something false by design. Every file that IS subject to compensation
  (everything `:actuate` can touch -- `lib/**`, and any pre-existing file in
  the project root) is covered.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  # -- Fixture builders (same conventions as ggen_igniter_reconcile_reactor_test.exs) --

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_actuation_failure_injection_test_#{System.unique_integer([:positive])}"
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

    app = "actuation_failure_fixture_#{System.unique_integer([:positive])}"

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
      ex:moduleName "GgenIgniterActuationFailureFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterActuationFailureFixture.Beta" ;
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

  # -- Whole-directory-tree hashing (task requirement 3) ----------------------

  # Every real regular file under `root`, as paths relative to `root`, sorted.
  defp walk_files!(root) do
    root
    |> walk_rel!(root)
    |> Enum.sort()
  end

  defp walk_rel!(dir, root) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      abs = Path.join(dir, entry)

      cond do
        File.dir?(abs) -> walk_rel!(abs, root)
        File.regular?(abs) -> [Path.relative_to(abs, root)]
        true -> []
      end
    end)
  end

  # A real SHA-256 digest over every real file under `root` (relative path +
  # real content, sorted), excluding any relative path under one of
  # `opts[:exclude]`'s directory names. Reuses `GgenIgniter.Receipt.hash_entries/1`
  # -- the exact same real "sorted (path, content) pairs -> sha256" primitive
  # the production code itself uses -- rather than re-deriving a second
  # hashing scheme; this function supplies its own, independently-walked
  # entries, so it is still a genuinely separate check on the real
  # filesystem, not a trust of any value the pipeline computed.
  defp hash_tree!(root, opts) do
    exclude = Keyword.get(opts, :exclude, [])

    root
    |> walk_files!()
    |> Enum.reject(&excluded?(&1, exclude))
    |> Enum.map(fn rel -> {rel, File.read!(Path.join(root, rel))} end)
    |> Receipt.hash_entries()
  end

  defp excluded?(rel, exclude) do
    Enum.any?(exclude, fn prefix -> rel == prefix or String.starts_with?(rel, prefix <> "/") end)
  end

  # -- Scenario 1: a real failure mid-:actuate (1 of 2 writes succeeds) -------

  describe "actuate-step self-heal: a real write failure mid-:actuate reverts the already-written target" do
    test "the pre-existing file is restored to its exact pre-run bytes; the never-written target never exists" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)

      project_dir = new_mix_project!()

      # -- Target A: a REAL pre-existing file, with KNOWN content, that this
      # run will genuinely overwrite (and which must come back byte-for-byte
      # identical after compensation).
      existing_path = Path.join([project_dir, "lib", "existing_actuate_target.ex"])
      original_content = "defmodule ExistingActuateTarget do\n  def value, do: :pre_run_original\nend\n"
      File.write!(existing_path, original_content)
      assert File.exists?(existing_path)

      # -- Target B: a REAL, deliberately-invalid path. `blocked_dir` exists
      # as a plain FILE (not a directory), so `File.mkdir_p!/1` on anything
      # under it genuinely raises -- confirmed empirically (see moduledoc).
      blocked_dir = Path.join([project_dir, "lib", "blocked_dir"])
      File.write!(blocked_dir, "i am a real file, not a directory")
      bad_path = Path.join(blocked_dir, "unreachable_target.ex")
      refute File.exists?(bad_path)

      pre_hash = hash_tree!(project_dir, exclude: [".ggen_igniter"])

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: valid_template, query: "spec=#{query_alpha}", out: existing_path],
          # A short delay on the failing target: not required for correctness
          # (the self-heal below reverts whatever this SAME run's own
          # `tracked` map holds, however the two async writes interleave),
          # but it makes target A's real write settle before target B's real
          # failure is detected, matching the task's own "after 1 of 2 real
          # writes succeed" framing as an observed, not merely possible,
          # ordering.
          [template: valid_template, query: "spec=#{query_beta}", out: bad_path, test_delay_ms: 60]
        ]
      ]

      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result

      # -- THE KEY UNDO PROOF: real disk state, read back from disk.
      assert File.read!(existing_path) == original_content,
             "expected the pre-existing target to be restored to its exact pre-run bytes"

      refute File.exists?(bad_path),
             "expected the target behind the blocked path component to never have existed"

      # The blocker itself was never touched by actuation (mkdir_p! failed
      # before any write was attempted against it).
      assert File.read!(blocked_dir) == "i am a real file, not a directory"

      # -- This is `:actuate`'s OWN failure (`compensate/4`, self-healed
      # inside `run/3`), never reaching `:verify` at all.
      refute File.exists?(Manifest.path(project_dir))

      assert receipt.standing == :compensated

      assert receipt.pre_run_hash != nil
      assert receipt.post_run_hash != nil

      assert receipt.pre_run_hash == receipt.post_run_hash,
             "expected the real post-compensation hash (over the files this attempt tracked) " <>
               "to match the real pre-run hash"

      activities = Enum.map(receipt.events, & &1["activity"])
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "FILES_RESTORED" in activities
      refute "VERIFICATION_FAILED" in activities,
             "this scenario fails inside :actuate itself -- :verify must never run"

      # -- THE STRONGEST, MOST LITERAL PROOF (task requirement 3): a real
      # SHA-256 over the ENTIRE actuated project directory tree (this test's
      # own independent walk of the real filesystem, not the pipeline's
      # self-reported hash), before the run and after full compensation.
      post_hash = hash_tree!(project_dir, exclude: [".ggen_igniter"])

      assert post_hash == pre_hash,
             "expected the whole target directory tree's real content to be byte-for-byte " <>
               "identical before this run and after full compensation"

      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "compensated"
    end
  end

  # -- Scenario 2: a real :verify failure after TWO real writes (both reverted) --

  describe ":verify failure after two real writes reverts both to pre-run state" do
    test "the pre-existing file is restored; the newly-created file is deleted; whole-tree hash is identical" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      broken_template = write_broken_template!(fixtures)

      project_dir = new_mix_project!()

      # -- Target A: a REAL pre-existing file with KNOWN content.
      existing_path = Path.join([project_dir, "lib", "verify_existing_target.ex"])
      original_content = "defmodule VerifyExistingTarget do\n  def value, do: :pre_run_original\nend\n"
      File.write!(existing_path, original_content)
      assert File.exists?(existing_path)

      # -- Target B: a REAL path that does not exist before this run.
      new_path = Path.join([project_dir, "lib", "verify_new_target.ex"])
      refute File.exists?(new_path)

      pre_hash = hash_tree!(project_dir, exclude: [".ggen_igniter"])

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

      result = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt} = result

      # -- THE KEY UNDO PROOF: real disk state, read back from disk (this is
      # Reactor's real `undo/4` path -- a LATER step, :verify, failed after
      # :actuate genuinely succeeded).
      assert File.read!(existing_path) == original_content,
             "expected the pre-existing target's ORIGINAL content to be restored after :verify failed"

      refute File.exists?(new_path),
             "expected the file that did not exist before this run to be deleted again"

      refute File.exists?(Manifest.path(project_dir)),
             "expected no manifest to be committed when :verify fails"

      assert receipt.standing == :build_broken

      assert receipt.pre_run_hash != nil
      assert receipt.post_run_hash != nil

      assert receipt.pre_run_hash == receipt.post_run_hash,
             "expected the real post-compensation project hash to match the real pre-run hash"

      activities = Enum.map(receipt.events, & &1["activity"])
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "VERIFICATION_FAILED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "FILES_RESTORED" in activities

      # -- THE STRONGEST, MOST LITERAL PROOF (task requirement 3): a real
      # SHA-256 over the ENTIRE actuated project directory tree, computed by
      # this test's own independent filesystem walk, before the run and
      # after full compensation.
      post_hash = hash_tree!(project_dir, exclude: [".ggen_igniter"])

      assert post_hash == pre_hash,
             "expected the whole target directory tree's real content to be byte-for-byte " <>
               "identical before this run and after full compensation"

      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "build_broken"
    end
  end
end
