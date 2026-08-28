defmodule GgenIgniter.ReconcileReactorInjectTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `GgenIgniter.Reactors.ReconcileReactor`
  really constructs and dispatches `operation: :inject`
  `%GgenIgniter.PendingActuation{}` items -- closing the real gap the
  PRD/redteam notes flagged (`:inject` declared on
  `GgenIgniter.PendingActuation.t/0` but never constructed anywhere).

  Every collaborator here is real and is the ACTUAL production code path:

    * `GgenIgniter.PendingActuation.for_inject/8` -- the real constructor,
      called from `ReconcileReactor`'s private `render_inject_target/6`
      (itself called from `render_target/2` when a `mode: file` target's
      frontmatter has `inject: true`).
    * `GgenIgniter.Injection.resolve_injection!/1` -- the SAME real
      frontmatter-to-`Actuate.inject_content!/5`-args conversion
      `Mix.Tasks.GgenIgniter.Sync` itself uses (extracted to a shared
      module so both pipelines use one real implementation).
    * `GgenIgniter.Actuate.inject_content!/5` -- the real, unmocked
      line-anchored splice/idempotency/fail-closed-anchor engine.
    * `ReconcileReactor.run/1` -- the real end-to-end pipeline (:render ->
      :admit -> :actuate -> :verify -> :finalize_evidence), including a
      real `mix compile --warnings-as-errors` subprocess for `:verify`
      against a real, minimal scratch Mix project, and real Reactor
      `undo/4` compensation on a later-step failure.

  No `Mix`/`Reactor`/`File` mocking anywhere in this file -- every
  assertion is against real on-disk state or a real, persisted
  `GgenIgniter.Receipt`.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  # -- Fixture builders -------------------------------------------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_inject_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "reactor_inject_fixture_#{System.unique_integer([:positive])}"

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
    @prefix ex: <http://example.org/rri#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterReactorInjectFixture.Alpha" ;
      ex:greeting "hello_from_alpha" ;
      ex:extensionTarget "alpha_target" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterReactorInjectFixture.Beta" ;
      ex:greeting "hello_from_beta" ;
      ex:extensionTarget "beta_target" .
    """)

    path
  end

  defp write_query!(dir, name, subject) do
    path = Path.join(dir, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rri#>
    SELECT ?module_name ?greeting ?extension_target WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting ;
        ex:extensionTarget ?extension_target .
    }
    """)

    path
  end

  # A real `mode: file` template with a real `---...---` frontmatter fence:
  # `inject: true`, anchored on a literal `before:` marker.
  defp write_inject_before_template!(dir) do
    path = Path.join(dir, "inject_before.ex.eex")

    File.write!(path, """
    ---
    to: "unused_-_reactor_targets_always_pass_--out_explicitly.ex"
    inject: true
    before: "# GGEN:INJECT:BEFORE"
    ---
      def injected_<%= extension_target %>, do: "<%= greeting %>"
    """)

    path
  end

  # Same real `inject: true`/`before:` shape, but every write is idempotent
  # -- reused across the idempotency test's two runs.
  defp write_target_host_file!(_dir, path) do
    File.write!(path, """
    defmodule Host do
      # GGEN:INJECT:BEFORE
      def existing, do: :ok
    end
    """)

    path
  end

  # A real `mode: file` write template with no frontmatter at all -- the
  # ordinary, unchanged actuation path, used as the SECOND target in the
  # multi-target compensation test (its own real write is what proves
  # `undo/4` reverts an ALREADY-INJECTED first target too).
  defp write_plain_template!(dir) do
    path = Path.join(dir, "plain.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # Deliberately invalid Elixir -- a real parse failure `mix compile` cannot
  # paper over, forcing a real `:verify` failure so real Reactor `undo/4`
  # actually fires against BOTH targets (the inject target included).
  defp write_broken_template!(dir) do
    path = Path.join(dir, "broken.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def broken(
    end
    """)

    path
  end

  # -- 1. Real, working injection (closes the "declared but never
  # constructed" gap directly) -----------------------------------------------

  describe "a mode: file target with frontmatter inject: true" do
    test "ReconcileReactor really constructs an :inject PendingActuation and splices real content" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      inject_template = write_inject_before_template!(fixtures)

      project_dir = new_mix_project!()
      host_path = Path.join([project_dir, "lib", "host.ex"])
      write_target_host_file!(project_dir, host_path)
      original_content = File.read!(host_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: inject_template,
        out: host_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :alive

      new_content = File.read!(host_path)
      assert new_content != original_content
      assert new_content =~ "def injected_alpha_target, do: \"hello_from_alpha\""
      assert new_content =~ "# GGEN:INJECT:BEFORE", "expected the anchor line to still be there"

      # -- An inject target is never manifest-owned (mirrors
      # Mix.Tasks.GgenIgniter.Sync's own rule: inject_content!/5 requires
      # and never creates a pre-existing file this pack does not own) --
      # no manifest is committed for a run whose only target is inject.
      refute File.exists?(GgenIgniter.Manifest.path(project_dir))

      # -- The receipt is genuinely durable.
      assert [persisted] = Receipt.read_all!(project_dir)
      assert persisted["standing"] == "alive"
    end
  end

  # -- 2. Idempotency: a second, identical run does not duplicate the body ---

  describe "idempotency" do
    test "re-running the exact same injection twice never duplicates the spliced block" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      inject_template = write_inject_before_template!(fixtures)

      project_dir = new_mix_project!()
      host_path = Path.join([project_dir, "lib", "host.ex"])
      write_target_host_file!(project_dir, host_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: inject_template,
        out: host_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, receipt1} = ReconcileReactor.run(reconcile_opts)
      assert receipt1.standing == :alive
      content_after_first = File.read!(host_path)

      occurrences = fn content, needle ->
        content
        |> String.split(needle)
        |> length()
        |> Kernel.-(1)
      end

      assert occurrences.(content_after_first, "def injected_alpha_target") == 1

      # -- Real re-run, identical opts: Actuate.inject_content!/5's own real
      # idempotency check (already_present_at?/4) must return :unchanged,
      # never re-splicing a second copy.
      assert {:ok, receipt2} = ReconcileReactor.run(reconcile_opts)
      assert receipt2.standing == :alive

      content_after_second = File.read!(host_path)
      assert content_after_second == content_after_first, "expected byte-identical content"
      assert occurrences.(content_after_second, "def injected_alpha_target") == 1
    end
  end

  # -- 3. Missing anchor: fail-closed, never a silent no-op -------------------

  describe "missing anchor" do
    test "a marker that matches zero lines raises, and the run fails closed with no mutation" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      inject_template = write_inject_before_template!(fixtures)

      project_dir = new_mix_project!()
      host_path = Path.join([project_dir, "lib", "host.ex"])

      # A REAL existing file, but WITHOUT the "# GGEN:INJECT:BEFORE" anchor
      # line the template's frontmatter requires.
      original_content = "defmodule Host do\n  def existing, do: :ok\nend\n"
      File.write!(host_path, original_content)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: inject_template,
        out: host_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :compensated

      # -- Fail-closed: the real file was never mutated at all (the raise
      # happens inside Actuate.inject_content!/5 before any File.write!/2).
      assert File.read!(host_path) == original_content

      # -- The real reason names the real, exact failure -- never a silent
      # swallow.
      assert receipt.reason =~ "matched no line"
    end
  end

  # -- 4. Ambiguous anchor: fail-closed, never a best-effort pick -------------

  describe "multiple anchor matches" do
    test "a marker that matches more than one line raises, and the run fails closed" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures, "spec_alpha", "Alpha")
      inject_template = write_inject_before_template!(fixtures)

      project_dir = new_mix_project!()
      host_path = Path.join([project_dir, "lib", "host.ex"])

      # A REAL existing file with the anchor line duplicated -- an
      # inherently ambiguous target for a single-anchor injection.
      original_content = """
      defmodule Host do
        # GGEN:INJECT:BEFORE
        def one, do: :ok
        # GGEN:INJECT:BEFORE
        def two, do: :ok
      end
      """

      File.write!(host_path, original_content)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: inject_template,
        out: host_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :compensated
      assert File.read!(host_path) == original_content
      assert receipt.reason =~ "ambiguous"
    end
  end

  # -- 5. Compensation covers :inject targets too: a LATER step's failure
  # restores the inject target's REAL PRIOR content -------------------------

  describe "compensation restores an already-injected target's prior content" do
    test "a second target's real :verify failure reverts BOTH the inject splice and the write" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      inject_template = write_inject_before_template!(fixtures)
      broken_template = write_broken_template!(fixtures)

      project_dir = new_mix_project!()

      host_path = Path.join([project_dir, "lib", "host.ex"])
      write_target_host_file!(project_dir, host_path)
      original_host_content = File.read!(host_path)

      broken_path = Path.join([project_dir, "lib", "broken_target.ex"])
      refute File.exists?(broken_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: inject_template, query: "spec=#{query_alpha}", out: host_path],
          [template: broken_template, query: "spec=#{query_beta}", out: broken_path]
        ]
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :build_broken

      # -- THE KEY UNDO PROOF for :inject: the real splice this run's
      # :actuate step genuinely performed on `host_path` is genuinely
      # reverted back to its REAL pre-run content, read from disk (not from
      # the Reactor result value).
      assert File.read!(host_path) == original_host_content,
             "expected the inject target's ORIGINAL content to be restored after :verify failed"

      refute File.exists?(broken_path),
             "expected the file that did not exist before this run to be deleted again"

      assert receipt.pre_run_hash == receipt.post_run_hash

      activities = Enum.map(receipt.events, & &1["activity"])
      assert "ACTUATION_STARTED" in activities
      assert "FILES_CHANGED" in activities
      assert "VERIFICATION_FAILED" in activities
      assert "COMPENSATION_STARTED" in activities
      assert "FILES_RESTORED" in activities
      assert "COMPENSATION_COMPLETED" in activities
    end
  end

  # -- 6. Duplicate-output-path admission still applies to :inject items -----

  describe "same-output-path collision" do
    test "an :inject target and a :file target resolving to the SAME real path are refused" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      inject_template = write_inject_before_template!(fixtures)
      plain_template = write_plain_template!(fixtures)

      project_dir = new_mix_project!()
      host_path = Path.join([project_dir, "lib", "host.ex"])
      write_target_host_file!(project_dir, host_path)
      original_content = File.read!(host_path)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: inject_template, query: "spec=#{query_alpha}", out: host_path],
          [template: plain_template, query: "spec=#{query_beta}", out: host_path]
        ]
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)
      assert receipt.standing == :refused
      assert receipt.reason =~ "duplicate output path"

      # -- Refused before any actuation: the real file is genuinely untouched.
      assert File.read!(host_path) == original_content
    end
  end
end
