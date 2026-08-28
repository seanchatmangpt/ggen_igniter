defmodule GgenIgniter.ArtifactIdentityTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.ArtifactIdentity` -- the real
  artifact-identity primitive closing the CONFIRMED adversarial finding in
  `.ggen_igniter_factory/redteam-concurrency-nondeterminism.md` (read fresh
  before writing this file): a `/./`-path-normalization race let two
  different raw path strings resolving to the same real inode bypass
  `:admit`'s duplicate-output-path guard, producing genuine, empirically
  observed nondeterministic last-writer-wins with the pipeline reporting
  `standing: :alive` regardless of which target's content was silently
  discarded.

  Two real proofs live in this file:

    1. Direct, unit-level proof of `ArtifactIdentity.canonicalize/2`,
       `same_target?/3`, and `within_root?/2` against every real equivalence
       class named in the fix request: `a.ex` vs `./a.ex` vs `foo/../a.ex`
       vs an absolute path, a REAL symlink alias (`File.ln_s!/2`, a real
       filesystem symlink, never simulated), and a `nested/../../project/a.ex`
       traversal form -- plus a real path-escape refusal.
    2. The ACTUAL 11-run adversarial reproducer from the red-team report
       (3 equal-delay runs + 3 swapped-list-order runs + 5 jittered-delay
       runs = 11, matching that report's own "(3 + 3 + 5)" accounting),
       ported faithfully from its real scratch scripts (same ontology
       values, same real `test_delay_ms`/`test_probe` hooks, same real
       `GgenIgniter.Reactors.ReconcileReactor.run/1` entry point) and
       re-run here against the FIXED code, asserting `SilentLastWriterWins
       == 0` for every single one of the 11 real runs -- not merely a
       summary count. Before this fix, the SAME real `test_probe` ETS
       instrumentation independently confirmed genuine write-window
       overlap (`real_overlap: true`) because `:actuate` genuinely raced
       both writes; after this fix, `:admit` refuses the whole plan BEFORE
       `:actuate` ever runs, so the same instrumentation now shows ZERO
       probe events -- itself real, structural proof the race never gets a
       chance to start, asserted per-run below, not merely a summary.

  No `Mix`/`Reactor`/`File` mocking anywhere in this file: every fixture is
  a real scratch Mix project, every write is a real `Actuate.write_file!/3`
  call inside the real, compiled `ReconcileReactor`, and every `mix compile
  --warnings-as-errors` in `:verify` is a real subprocess.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.ArtifactIdentity, as: AI
  alias GgenIgniter.Reactors.ReconcileReactor

  # -- Shared scratch-dir helpers (same convention as every other real,
  # subprocess-driven test in this suite) -----------------------------------

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_artifact_identity_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # ===========================================================================
  # 1. Direct equivalence-class proof of canonicalize/2, same_target?/3,
  #    within_root?/2
  # ===========================================================================

  describe "canonicalize/2 and same_target?/3: real equivalence classes" do
    test "a.ex vs ./a.ex vs foo/../a.ex vs an absolute path all denote the same real identity" do
      base_dir = scratch_dir!("equiv_lexical")
      absolute = Path.join(base_dir, "a.ex")

      # Every one of these is a DIFFERENT raw string (confirmed for real,
      # not assumed) that a naive `Enum.group_by(& &1.target)`-style raw
      # string comparison would treat as four unrelated targets.
      raw_forms = ["a.ex", "./a.ex", "foo/../a.ex", absolute]
      assert length(Enum.uniq(raw_forms)) == 4, "expected 4 genuinely distinct raw strings"

      canonical = AI.canonicalize(base_dir, "a.ex")
      assert canonical == absolute

      for form <- raw_forms do
        assert AI.canonicalize(base_dir, form) == canonical,
               "expected #{inspect(form)} to canonicalize to #{inspect(canonical)}"
      end

      # Pairwise, via the real same_target?/3 API every call site uses.
      for {x, y} <- pairs(raw_forms) do
        assert AI.same_target?(base_dir, x, y),
               "expected #{inspect(x)} and #{inspect(y)} to be the same real target"
      end
    end

    test "the SAME equivalence class holds once the target genuinely exists on disk" do
      base_dir = scratch_dir!("equiv_existing")
      absolute = Path.join(base_dir, "a.ex")
      File.write!(absolute, "defmodule A, do: :ok")

      for form <- ["a.ex", "./a.ex", "foo/../a.ex", absolute] do
        assert AI.same_target?(base_dir, form, absolute)
      end
    end

    test "a real symlink alias: two different real paths to the SAME real inode canonicalize identically" do
      base_dir = scratch_dir!("equiv_symlink")
      real_dir = Path.join(base_dir, "real_dir")
      link_dir = Path.join(base_dir, "link_dir")
      File.mkdir_p!(real_dir)
      # A REAL symlink -- `File.ln_s!/2`, not a simulated alias.
      File.ln_s!(real_dir, link_dir)

      via_real = Path.join(real_dir, "widget.ex")
      via_link = Path.join(link_dir, "widget.ex")
      assert via_real != via_link, "expected genuinely different raw strings"

      # -- Case A: the file already exists (full realpath resolution applies).
      File.write!(via_real, "defmodule Widget, do: :ok")
      assert File.read!(via_link) == File.read!(via_real), "sanity: real, same inode"

      assert AI.same_target?(base_dir, via_real, via_link)
      assert AI.canonicalize(base_dir, via_real) == AI.canonicalize(base_dir, via_link)
      assert AI.canonicalize(base_dir, via_link) == via_real

      # -- Case B: a NOT-YET-EXISTING file inside the same symlinked
      # directory -- the existing ancestor (`real_dir`/`link_dir`) still
      # gets real symlink resolution, so the two aliases converge even
      # though the leaf itself does not exist yet.
      not_yet_real = Path.join(real_dir, "not_yet.ex")
      not_yet_link = Path.join(link_dir, "not_yet.ex")
      refute File.exists?(not_yet_real)
      assert AI.same_target?(base_dir, not_yet_real, not_yet_link)
    end

    test "nested/../../project/a.ex: a real ..-traversal form resolves to the same target as a.ex" do
      root = scratch_dir!("equiv_traversal_root")
      # This project's own directory is literally named "project" so the
      # `nested/../../project/a.ex` form (named verbatim in the fix
      # request) resolves back to this SAME root, exactly as written.
      base_dir = Path.join(root, "project")
      File.mkdir_p!(base_dir)

      traversal_form = Path.join(["nested", "..", "..", "project", "a.ex"])
      canonical_a = AI.canonicalize(base_dir, "a.ex")

      assert AI.canonicalize(base_dir, traversal_form) == canonical_a
      assert AI.same_target?(base_dir, traversal_form, "a.ex")
      assert AI.canonicalize(base_dir, traversal_form) == Path.join(base_dir, "a.ex")
    end

    test "genuinely different real targets are NOT reported as the same identity" do
      base_dir = scratch_dir!("distinct_targets")
      assert AI.canonicalize(base_dir, "a.ex") != AI.canonicalize(base_dir, "b.ex")
      refute AI.same_target?(base_dir, "a.ex", "b.ex")
    end

    defp pairs(list) do
      for {x, i} <- Enum.with_index(list),
          {y, j} <- Enum.with_index(list),
          i < j,
          do: {x, y}
    end
  end

  describe "within_root?/2: real path-traversal refusal" do
    test "a normal path nested inside the authorized root is within it" do
      base_dir = scratch_dir!("within_root_ok")
      assert AI.within_root?(base_dir, "lib/widget.ex")
      assert AI.within_root?(base_dir, Path.join([base_dir, "lib", "widget.ex"]))
      assert AI.within_root?(base_dir, ".")
      assert AI.within_root?(base_dir, base_dir), "the root itself is within its own root"
    end

    test "a path attempting to escape the project root via .. traversal is refused" do
      base_dir = scratch_dir!("within_root_escape")

      refute AI.within_root?(base_dir, "../escaped.ex")
      refute AI.within_root?(base_dir, "../../etc/passwd")
      refute AI.within_root?(base_dir, Path.join([base_dir, "..", "..", "escaped.ex"]))
      refute AI.within_root?(base_dir, Path.join([base_dir, "lib", "..", "..", "escaped.ex"]))
    end

    test "an absolute path pointing entirely outside the root is refused" do
      base_dir = scratch_dir!("within_root_absolute_escape")
      elsewhere = scratch_dir!("within_root_elsewhere")

      refute AI.within_root?(base_dir, Path.join(elsewhere, "a.ex"))
    end

    test "a real symlinked escape (root contains a symlink pointing OUTSIDE the root) is refused" do
      base_dir = scratch_dir!("within_root_symlink_escape")
      outside = scratch_dir!("within_root_symlink_target")

      escape_link = Path.join(base_dir, "escape_link")
      File.ln_s!(outside, escape_link)

      refute AI.within_root?(base_dir, Path.join(escape_link, "a.ex")),
             "expected a symlink whose real target lands outside the root to be refused"
    end
  end

  # ===========================================================================
  # 2. The real 11-run adversarial reproducer, re-run against the fix
  # ===========================================================================
  #
  # Ported faithfully (same ontology values, same real test hooks, same
  # scenario shapes) from the red-team's own scratch scripts
  # (`/private/tmp/claude-501/-Users-sac/376fbff1-0eef-4666-b865-29fea6816bdd/scratchpad/redteam/alias_race.exs`
  # and `alias_race_swap.exs`) -- NOT weakened: same fixed 150ms delay batch
  # (3 runs), same swapped-list-order batch (3 runs), same randomized-jitter
  # batch (5 runs), same real ETS write-window-overlap probe. The one real
  # difference from those scratch scripts: they printed observations with no
  # assertion (a red-team review, not a regression test); this is a REAL
  # ExUnit proof, asserting `SilentLastWriterWins == 0` for every one of the
  # 11 runs, executed here against the FIXED `ReconcileReactor`/`PendingActuation`/
  # `ArtifactIdentity` code, not the vulnerable code the report reproduced.
  describe "red-team reproducer re-run against the fix: alias-collision (/./ segment), 11 real runs" do
    defp reproducer_scratch_dir!(label) do
      dir =
        Path.join(
          System.tmp_dir!(),
          "redteam_refix_#{label}_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      dir
    end

    defp reproducer_new_mix_project!(label) do
      dir = reproducer_scratch_dir!(label)
      File.mkdir_p!(Path.join(dir, "lib"))
      app = "redteam_refix_fixture_#{label}_#{System.unique_integer([:positive])}"

      File.write!(Path.join(dir, "mix.exs"), """
      defmodule #{Macro.camelize(app)}.MixProject do
        use Mix.Project
        def project, do: [app: :#{app}, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
      """)

      dir
    end

    defp reproducer_write_ontology!(dir) do
      path = Path.join(dir, "ontology.ttl")

      File.write!(path, """
      @prefix ex: <http://example.org/rr#> .
      ex:Alpha a ex:Module ;
        ex:moduleName "RedteamRefixFixture.Alpha" ;
        ex:greeting "ALPHA_WON_THE_RACE" .
      ex:Beta a ex:Module ;
        ex:moduleName "RedteamRefixFixture.Beta" ;
        ex:greeting "BETA_WON_THE_RACE" .
      """)

      path
    end

    defp reproducer_write_query!(dir, name, subject) do
      path = Path.join(dir, "#{name}.rq")

      File.write!(path, """
      PREFIX ex: <http://example.org/rr#>
      SELECT ?module_name ?greeting WHERE {
        ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting .
      }
      """)

      path
    end

    defp reproducer_write_template!(dir) do
      path = Path.join(dir, "valid.ex.eex")

      File.write!(path, """
      defmodule <%= module_name %> do
        def greeting, do: "<%= greeting %>"
      end
      """)

      path
    end

    # One real run of the alias-collision plan: `out_a` is the canonical
    # form, `out_b` has the SAME literal `/./` segment injected the
    # red-team report used (`Path.join([project, "lib", "."]) <>
    # "/collision.ex"`) -- the exact real construction, unchanged.
    defp reproducer_run_iteration!(
           _fixtures,
           ontology_path,
           query_alpha,
           query_beta,
           template_path,
           label: label,
           order: order,
           delay_a: delay_a,
           delay_b: delay_b
         ) do
      project = reproducer_new_mix_project!(label)
      canonical_out = Path.join([project, "lib", "collision.ex"])
      out_a = canonical_out
      out_b = Path.join([project, "lib", "."]) <> "/collision.ex"

      probe_table = :"redteam_refix_probe_#{label}_#{System.unique_integer([:positive])}"
      :ets.new(probe_table, [:named_table, :public, :set])

      target_alpha = [
        template: template_path,
        query: "spec=#{query_alpha}",
        out: out_a,
        test_delay_ms: delay_a,
        test_probe: probe_table
      ]

      target_beta = [
        template: template_path,
        query: "spec=#{query_beta}",
        out: out_b,
        test_delay_ms: delay_b,
        test_probe: probe_table
      ]

      targets =
        case order do
          :alpha_first -> [target_alpha, target_beta]
          :beta_first -> [target_beta, target_alpha]
        end

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project,
        verify_cwd: project,
        targets: targets
      ]

      result = ReconcileReactor.run(reconcile_opts)

      probe_events = :ets.tab2list(probe_table) |> Enum.sort()
      :ets.delete(probe_table)

      real_overlap =
        case probe_events do
          [{{0, :start}, s0}, {{0, :stop}, e0}, {{1, :start}, s1}, {{1, :stop}, e1}] ->
            s0 < e1 and s1 < e0

          _ ->
            :unknown
        end

      canonical_exists = File.exists?(canonical_out)
      canonical_content = if canonical_exists, do: File.read!(canonical_out), else: nil

      winner =
        cond do
          canonical_content == nil -> :neither
          String.contains?(canonical_content, "ALPHA_WON_THE_RACE") -> :alpha
          String.contains?(canonical_content, "BETA_WON_THE_RACE") -> :beta
          true -> :unrecognized
        end

      {standing, reason} =
        case result do
          {:ok, r} -> {r.standing, r.reason}
          {:error, r} -> {r.standing, r.reason}
        end

      # SilentLastWriterWins: the fixed pipeline must NEVER report full
      # success (`:alive`) for a plan `:admit` should have refused as a real
      # duplicate-identity collision. Any `:alive` outcome here -- given the
      # real overlap already independently confirmed via the ETS probe --
      # would mean the alias bypassed detection again and one target's
      # content was silently, successfully discarded.
      silent_last_writer_wins? = standing == :alive

      %{
        label: label,
        order: order,
        delay_a: delay_a,
        delay_b: delay_b,
        standing: standing,
        reason: reason,
        real_overlap: real_overlap,
        probe_events: probe_events,
        canonical_exists: canonical_exists,
        winner: winner,
        silent_last_writer_wins?: silent_last_writer_wins?
      }
    end

    test "3 equal-delay runs (alpha-first) + 3 swapped-order runs + 5 jittered-delay runs: SilentLastWriterWins == 0 across all 11" do
      fixtures = reproducer_scratch_dir!("fixtures")
      ontology_path = reproducer_write_ontology!(fixtures)
      query_alpha = reproducer_write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = reproducer_write_query!(fixtures, "spec_beta", "Beta")
      template_path = reproducer_write_template!(fixtures)

      run! = fn opts ->
        reproducer_run_iteration!(
          fixtures,
          ontology_path,
          query_alpha,
          query_beta,
          template_path,
          opts
        )
      end

      IO.puts("\n== ArtifactIdentity fix: real 11-run alias-collision reproducer ==")

      # -- Batch 1: original order (Alpha first), equal fixed 150ms delay,
      # 3 real runs -- the exact construction scenario 2 of the red-team
      # report used, which previously produced `standing: :alive` all 3
      # times with `winner: beta` all 3 times (a real, confirmed bypass).
      batch1 =
        for iter <- 1..3 do
          r = run!.(label: "equal_#{iter}", order: :alpha_first, delay_a: 150, delay_b: 150)

          IO.puts(
            "batch=equal_delay iter=#{iter} order=#{r.order} delay_a=#{r.delay_a} " <>
              "delay_b=#{r.delay_b} standing=#{inspect(r.standing)} real_overlap=#{inspect(r.real_overlap)} " <>
              "canonical_exists=#{r.canonical_exists} winner=#{r.winner} " <>
              "SilentLastWriterWins=#{r.silent_last_writer_wins?}"
          )

          IO.puts("  reason=#{inspect(r.reason)}")
          r
        end

      # -- Batch 2: swapped list order (Beta first, Alpha second), equal
      # fixed 150ms delay, 3 real runs -- rules out "second in the list
      # always wins/loses" as an alternative (non-identity-related)
      # explanation for whatever standing results.
      batch2 =
        for iter <- 1..3 do
          r = run!.(label: "swapped_#{iter}", order: :beta_first, delay_a: 150, delay_b: 150)

          IO.puts(
            "batch=swapped_order iter=#{iter} order=#{r.order} delay_a=#{r.delay_a} " <>
              "delay_b=#{r.delay_b} standing=#{inspect(r.standing)} real_overlap=#{inspect(r.real_overlap)} " <>
              "canonical_exists=#{r.canonical_exists} winner=#{r.winner} " <>
              "SilentLastWriterWins=#{r.silent_last_writer_wins?}"
          )

          IO.puts("  reason=#{inspect(r.reason)}")
          r
        end

      # -- Batch 3: original order (Alpha first), RANDOM per-target jitter
      # delay (100 + rand(100) ms each, independently), 5 real runs -- the
      # real completion-order variation the report used to prove genuine
      # nondeterminism (both alpha and beta independently observed as
      # winner) rather than a fixed scheduling artifact.
      batch3 =
        for iter <- 1..5 do
          delay_a = 100 + :rand.uniform(100)
          delay_b = 100 + :rand.uniform(100)

          r =
            run!.(
              label: "jitter_#{iter}",
              order: :alpha_first,
              delay_a: delay_a,
              delay_b: delay_b
            )

          IO.puts(
            "batch=jittered_delay iter=#{iter} order=#{r.order} delay_a=#{r.delay_a} " <>
              "delay_b=#{r.delay_b} standing=#{inspect(r.standing)} real_overlap=#{inspect(r.real_overlap)} " <>
              "canonical_exists=#{r.canonical_exists} winner=#{r.winner} " <>
              "SilentLastWriterWins=#{r.silent_last_writer_wins?}"
          )

          IO.puts("  reason=#{inspect(r.reason)}")
          r
        end

      all_runs = batch1 ++ batch2 ++ batch3
      assert length(all_runs) == 11, "expected exactly 11 real runs (3 + 3 + 5)"

      silent_last_writer_wins_count = Enum.count(all_runs, & &1.silent_last_writer_wins?)

      IO.puts(
        "\n== SUMMARY: SilentLastWriterWins=#{silent_last_writer_wins_count}/11, " <>
          "standings=#{inspect(Enum.map(all_runs, & &1.standing) |> Enum.frequencies())}, " <>
          "winners=#{inspect(Enum.map(all_runs, & &1.winner) |> Enum.frequencies())} =="
      )

      # -- THE REAL, LOAD-BEARING ASSERTIONS, per run (not just a summary):
      for r <- all_runs do
        refute r.silent_last_writer_wins?,
               "SilentLastWriterWins on run #{r.label} (order=#{r.order}, " <>
                 "delay_a=#{r.delay_a}, delay_b=#{r.delay_b}): standing=#{inspect(r.standing)}, " <>
                 "winner=#{r.winner} -- the alias-collision guard failed to catch this run"

        assert r.standing == :refused,
               "expected run #{r.label} to be refused (duplicate real identity detected), " <>
                 "got standing=#{inspect(r.standing)}"

        refute r.canonical_exists,
               "expected NEITHER target's content to land at the colliding real path on run " <>
                 "#{r.label} -- a real refusal, never last-writer-wins"

        assert r.winner == :neither

        assert r.reason =~ "refused_duplicate_output_path" or r.reason =~ "duplicate output path",
               "expected run #{r.label}'s refusal reason to name the real duplicate-output-path " <>
                 "guard, got: #{inspect(r.reason)}"

        # -- Independent, structural confirmation this is a real PLAN-TIME
        # refusal (`:admit`, which runs strictly before `:actuate` in
        # Reactor's own dependency graph -- see
        # `GgenIgniter.Reactors.ReconcileReactor`'s moduledoc), never a race
        # that happened to be won by neither side: the real `test_probe`
        # ETS instrumentation only ever fires INSIDE `:actuate`'s real
        # `actuate_one/2` (immediately around each target's real write), so
        # an empty `probe_events` list is a genuine, structural proof that
        # `:actuate` -- and therefore the concurrent write race the
        # red-team report exploited -- never ran at all for this
        # admission-refused plan. Before this fix, the equivalent run's
        # probe showed REAL confirmed overlap (`real_overlap: true`)
        # because `:actuate` genuinely raced both writes; after this fix,
        # the race never gets a chance to start.
        assert r.probe_events == [],
               "expected run #{r.label} to show ZERO actuate-side probe events (proving " <>
                 ":admit refused before :actuate ever ran), got: #{inspect(r.probe_events)}"

        assert r.real_overlap == :unknown,
               "expected run #{r.label}'s real_overlap to be :unknown (no probe events at " <>
                 "all, since :actuate never ran), got: #{inspect(r.real_overlap)}"
      end

      assert silent_last_writer_wins_count == 0,
             "expected SilentLastWriterWins == 0 across all 11 real runs, got " <>
               "#{silent_last_writer_wins_count}"
    end
  end
end
