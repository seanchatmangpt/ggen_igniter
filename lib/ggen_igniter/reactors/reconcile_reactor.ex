defmodule GgenIgniter.Reactors.ReconcileReactor do
  @moduledoc """
  The real Reactor coordination pipeline for `ggen_igniter`'s reconciliation
  spine: observe -> load -> resolve -> query -> render -> admit -> actuate ->
  verify -> finalize evidence. `use Reactor` (plain `Reactor`, NOT
  `Ash.Reactor` -- `ggen_igniter` must stay usable without Ash as a mandatory
  runtime dependency).

  ## Corrections applied (2026-08-27), on top of the design below

  Two real architectural corrections from the user, applied directly to this
  module (this section documents WHAT changed and WHY; the rest of this
  moduledoc, describing the pipeline's shape, is otherwise unchanged):

  ### A. A receipt for every admitted attempt, not only success

  Quoting the user directly:

  > If files were actually changed -- even temporarily -- then a
  > consequential physical actuation occurred... the run receipt should
  > record ACTUATION_STARTED -> files A,B changed -> verification failed ->
  > compensation started -> A,B restored -> resulting project hash ==
  > pre-run hash -> standing = COMPENSATED.

  Before this correction, `:receipt` only ran on the success path (gated
  behind `:commit_manifest`'s own success, itself gated behind `:verify`) --
  a refusal in `:admit`, a compile failure in `:verify`, or a partial-
  actuation self-heal in `:actuate` produced NO receipt at all, even though
  real bytes may have hit disk and been reverted. Fixed by:

    * `run/1` (this module's new, recommended public entry point --
      `Reactor.run(__MODULE__, %{reconcile_opts: opts})` still works, but
      only `run/1` guarantees a persisted receipt on every path) wraps the
      bare `Reactor.run/4` call and, on ANY `{:error, _}` result, derives a
      real `standing_for_failure/2` from which step failed and why, then
      persists a real `GgenIgniter.Receipt` via
      `GgenIgniter.Receipt.append!/2` before returning.
    * `:actuate` (both its internal self-heal branch in `actuate_pending/2`
      AND its real Reactor `undo/3`, triggered when `:verify` fails
      afterward) emits real `GgenIgniter.Telemetry.OcelEmitter` events
      (`ACTUATION_STARTED` / `FILES_CHANGED` / `COMPENSATION_STARTED` /
      `FILES_RESTORED`, the last carrying real `pre_run_hash`/
      `post_run_hash`/`matches_pre_run_hash` computed via
      `GgenIgniter.Receipt.hash_entries/1` and `hash_files/1`). `:verify`'s
      own compile failure is tagged `reason_type: "build_broken"`
      specifically -- a real, distinct meaning from a generic verification
      failure, giving `standing_for_failure/2` a genuine basis for
      `:build_broken` vs. the more general `:compensated`.
    * The four standings (`:alive` / `:refused` / `:compensated` /
      `:build_broken`) are `GgenIgniter.Receipt.standing/0`'s own closed
      set, not invented here.

  See `test/ggen_igniter_receipt_compensated_test.exs` for the real, running
  proof: a genuinely invalid Elixir template makes `:verify`'s real `mix
  compile --warnings-as-errors` fail for real, Reactor's real `undo/3`
  restores the real pre-run file content, and the persisted receipt's
  `pre_run_hash == post_run_hash` is asserted from the real file on disk --
  no mock anywhere in that chain.

  ### B. Evidence finalization is one boundary, not two independent steps

  Quoting the user directly:

  > verify succeeds -> manifest advances -> receipt write fails. Now you
  > have standing state with no standing evidence.

  The former `:commit_manifest` + `:receipt` two-step split is replaced by
  ONE `:finalize_evidence` step (`finalize_evidence/1`) that, in this exact
  order:

    1. Prepares BOTH the next manifest content (`commit_recipe/5`, reusing
       `GgenIgniter.Manifest`'s own real API, unchanged) and the new
       `GgenIgniter.Receipt` payload, entirely in memory -- nothing durable
       written yet.
    2. Persists the receipt FIRST: `GgenIgniter.Receipt.append!/2`, a real
       append-only `File.write!/3`. If this itself raises, `:finalize_evidence`
       fails like any other step -- since `:actuate` already wrote real
       files, Reactor's own `undo/3` rolls them back (a real `:compensated`
       outcome, recorded by `run/1`'s failure path, since this step never
       gets to build a receipt of its own in that case).
    3. Only once that append genuinely succeeds does it attempt to promote
       the manifest, via `GgenIgniter.Manifest.persist!/2`'s OWN existing
       temp-file-then-`File.rename!/2` atomic-rename protocol (unchanged;
       not reimplemented here). If THIS specific call fails, it is caught
       LOCALLY (not re-raised) -- the attempt is still genuinely `:alive`
       (files were written and verified correctly; rolling them back
       because the manifest CACHE failed to update would be wrong) --
       `metadata["manifest_promotion"]` instead records the pending state,
       with the now-durable receipt as the real recovery anchor for a retry
       to reconcile against.

  This ordering makes "manifest advanced but no receipt exists to explain
  why" structurally impossible: the manifest write is not even ATTEMPTED
  until the receipt line is already flushed to disk. See
  `test/ggen_igniter_finalize_evidence_ordering_test.exs` for a real,
  no-mock proof: the manifest's own target path is pre-created as a
  DIRECTORY (so `File.rename!/2` genuinely raises `File.RenameError`, not a
  simulated failure), and the test asserts the real receipt file already
  contains the real `:alive` line while the manifest path is still
  untouched.

  ---

  Grounded directly in real prior art explored this session (`~/ash_r2rml`'s
  `reactor_pipeline.ex` + `Admission` module, `~/xaas`'s `Actuation.Reactor`,
  `~/ex4pm`'s "Reactor is the single workflow execution kernel" rule, `~/ggen`'s
  `sync.rs` plan/actuate split) -- see
  `~/.claude/plans/i-want-you-to-humming-knuth.md` sections 1-2 for the full
  design rationale. This module implements sections 1-2, PLUS (per the
  corrections above) a real, working slice of sections 3-4 (a real
  `GgenIgniter.Receipt` and real `GgenIgniter.Telemetry.OcelEmitter` event
  emission) -- not the full SHA-256 hash-CHAIN across receipts those
  sections may still describe, which remains legitimate future work.

  ## Steps

      observe_prior_manifest  -- pure read: GgenIgniter.Manifest.load/1
      load_ontology           -- pure read: GgenIgniter.Ontology.load!/1
      resolve_pack            -- pure read: GgenIgniter.Pack.resolve_dir!/1
      run_queries             -- GgenIgniter.Engine.fetch!/run, per target
      render                  -- GgenIgniter.Render.render/2 PLUS
                                  GgenIgniter.Manifest lookups, produces the
                                  real intended delta as `[%PendingActuation{}]`
                                  (one create/replace/eval intent per target,
                                  plus one real `:delete` item per stale-prune
                                  candidate) -- never a bare `{out_path,
                                  content}` pair; nothing is written yet (the
                                  same plan/actuate split as ggen's own
                                  `sync.rs` PendingWrite/SyncReport -- see
                                  GgenIgniter.PendingActuation's own moduledoc)
      admit                   -- accumulating, fail-closed gate inspecting the
                                  FULL `[%PendingActuation{}]` plan (not just
                                  output paths): real duplicate-target
                                  refusal, real refusal of any `:delete` item
                                  lacking `ownership: true`, and
                                  GgenIgniter.Manifest's real stale/--on-stale
                                  policy -- never reimplemented
      actuate                 -- the ONLY step that touches the filesystem for
                                  real create/replace/eval intents
                                  (GgenIgniter.Actuate.write_file!/3,
                                  eval_code!/2), consuming each
                                  `%PendingActuation{}`'s own `operation`
                                  field directly rather than re-deriving it;
                                  tracks exactly what it wrote, in its own
                                  return value, for real undo. Real `:delete`
                                  items pass through admitted but unactuated
                                  here -- see "Prune timing" below
      verify                  -- a real `mix compile --warnings-as-errors`
                                  subprocess against the actuated project.
                                  A compile failure here is the real
                                  `:build_broken` standing (correction A).
      finalize_evidence       -- receipt persisted FIRST, manifest promoted
                                  atomically only after (correction B); also
                                  where real --on-stale prune deletions run
                                  (see "Prune timing" below), only after
                                  :verify

      return :finalize_evidence

  `:observe_prior_manifest`, `:load_ontology`, and `:resolve_pack` all depend
  only on the `:reconcile_opts` input, so Reactor's own dependency-graph
  scheduler runs them concurrently -- no manual concurrency management for
  that part of the pipeline.

  ## Multi-target input shape

  `:reconcile_opts` accepts the exact same flat opts `GgenIgniter.Reconcile.run/1`
  does (`:ontology`/`:query`/`:template`/`:pack`/`:pack_dir`/`:engine`/`:mode`/
  `:out`/`:unless_exists`/`:skip_if`/`:dry_run`, plus `:on_stale`/`:manifest_dir`/
  `:verify_cwd`, new here) for the single-output case -- this is what makes
  test 1's byte-for-byte parity against `Reconcile.run/1` meaningful: with no
  `:targets` key, this pipeline runs exactly one target, built from the flat
  opts themselves.

  Passing `:targets` (a list of keyword lists, each a per-target override of
  `:query`/`:template`/`:mode`/`:out`/`:unless_exists`/`:skip_if`/`:dry_run`,
  merged onto the shared top-level opts) runs N independent render/actuate
  targets in one Reactor pipeline run -- this is the real, in-memory
  "PendingWrite list" the plan's `:render` step describes, and is what the
  concurrency proof in the test suite exercises. `:ontology`/`:engine`/`:pack`/
  `:pack_dir` at the TOP level are shared across every target (loaded/resolved
  once); a target may still override its own `:pack`/`:pack_dir`/`:engine` for
  its own template/query resolution.

  ## Same-output-path collision: real, explicit refusal (never last-writer-wins)

  `:actuate` runs independent targets' real writes concurrently
  (`Task.async_stream/3`) for real throughput on independent files. Two
  DIFFERENT targets resolving to the SAME real output location in the SAME
  run would otherwise race -- there is no principled dependency order the
  ontology itself expresses for two unrelated queries that happen to render
  the same path. `:admit` detects this structurally (grouping this run's own
  pending file-mode writes by each item's real `canonical_target` --
  `GgenIgniter.ArtifactIdentity.canonicalize/2`'s result, NEVER the raw
  `target` string) and refuses the ENTIRE run with `{:error,
  {:refused_duplicate_output_path, [...]}}` before any actuation happens at
  all -- chosen deliberately over inventing an implicit dependency-ordering
  mechanism the ontology has no way to express; see the test suite's
  concurrency proof for the real, asserted behavior.

  ### Correction (2026-08-27): grouping by raw string was a real, confirmed gap

  `.ggen_igniter_factory/redteam-concurrency-nondeterminism.md` (an
  independent adversarial review, its real reproducer re-run against this
  fix in `test/ggen_igniter_artifact_identity_test.exs`) found that this
  guard used to group by the raw `target` STRING
  (`Enum.group_by(& &1.target)`) -- so two targets whose `--out`/`to:`
  strings differed only by a redundant `/./` segment (the same root cause
  covers `//`, `..`-traversal, and symlink-based aliases) resolved to the
  SAME real inode while comparing as different Elixir strings, silently
  bypassing this guard entirely. `:actuate`'s real `Task.async_stream/3`
  then genuinely raced both writes against the identical real file --
  confirmed, empirically, as real nondeterministic last-writer-wins (both
  possible targets independently observed as the real surviving winner
  across repeated real runs), with the pipeline reporting `standing:
  :alive` (full, false success) regardless of which target's content was
  actually discarded. Fixed by grouping on `GgenIgniter.PendingActuation`'s
  real `canonical_target` field instead -- see `GgenIgniter.ArtifactIdentity`
  for the real canonicalization primitive this and `within_root?/2`'s
  real path-escape guard (also enforced in `:admit`, alongside this check)
  are built on.

  ## `compensate/4` vs `undo/4` -- real Reactor semantics, not folklore

  Reactor's real `Reactor.Step` behaviour (confirmed by reading
  `deps/reactor/lib/reactor/step.ex` and
  `deps/reactor/documentation/tutorials/02-error-handling.md` directly, not
  assumed) gives each step TWO distinct rollback hooks with different
  triggers:

    * `compensate/4` fires when THIS step's OWN `run/3` returns `{:error,
      reason}` -- it decides whether to retry/continue/fail, it does not by
      itself revert a DIFFERENT, already-successful step.
    * `undo/4` fires when a LATER step in the same reactor run fails, and
      Reactor needs to roll back THIS already-successful step's work.

  The scenario this module's key test proves -- `:verify` (a later step)
  fails after `:actuate` has genuinely written files -- is exactly `undo/4`'s
  real trigger, not `compensate/4`'s. `:actuate` implements BOTH, honestly:
  `undo/4` is the real, tested revert mechanism for "a later step failed";
  `compensate/4` handles `:actuate`'s OWN run failing (e.g. one target's
  write raising mid-loop) by self-healing INSIDE `run/3` before ever
  returning `{:error, ...}` (reverting every write this SAME invocation
  already made), so `compensate/4` itself has nothing left to do and
  correctly returns `:ok`.

  ## `:verify` scope

  Runs a real `mix compile --warnings-as-errors` subprocess (`System.cmd/3`)
  against `reconcile_opts[:verify_cwd] || reconcile_opts[:manifest_dir] ||
  File.cwd!()` -- the actuated project's own directory. `mix format
  --check-formatted`-equivalent verification (the plan's "in-process where
  feasible" aside) is deliberately deferred this pass -- the compile check is
  the load-bearing proof this pipeline's compensation exists to protect
  against, and is what the task's own adversarial test exercises.

  ## Prune timing: deliberately AFTER `:verify`, not before

  `Mix.Tasks.GgenIgniter.Sync` applies `--on-stale prune`'s real deletions
  right after its own writes, with no compile-check gate at all. This
  pipeline moves real prune deletions into `:commit_manifest` -- i.e. only
  after `:verify` has confirmed the newly-actuated project actually compiles
  -- a strictly safer ordering (never delete a stale path until the new
  state is confirmed good), disclosed here as a deliberate difference from
  `sync.ex`'s existing behavior, not an oversight.

  ## Testing hooks (inert in real use)

  Three optional, per-target opts keys exist ONLY to make `:actuate`'s real
  concurrency, and its compensation path, independently observable from a
  test, and are otherwise inert no-ops:

    * `:test_delay_ms` -- `Process.sleep/1` for this many ms immediately
      before this target's real write.
    * `:test_probe` -- an atom naming a public ETS table; if given,
      `{{index, :start}, monotonic_ms}` and `{{index, :stop}, monotonic_ms}`
      are inserted around the (possibly delayed) write, so a test can assert
      two targets' real write windows actually overlapped.
    * `:test_chmod_after_write` -- an integer POSIX mode (e.g. `0o444`); if
      given, `File.chmod!/2` is called with this mode against the target
      path IMMEDIATELY after this target's real write genuinely succeeds
      (deterministic, not timing-dependent: `:actuate` is a separate,
      strictly-later Reactor step than `:verify`/`:actuate`'s own undo, so
      the file is guaranteed read-only well before either ever runs). This
      is what lets a test construct a REAL "compensation itself fails"
      scenario without racing a background process against the pipeline:
      the real mutation genuinely happens first (this target's write
      succeeds normally), then the file becomes genuinely unwritable, then
      a later step's real failure triggers a real revert attempt against
      it -- see "Compensation failure: `:compensation_failed`" below and
      `test/ggen_igniter_compensation_failure_test.exs`.

  None of the three is read anywhere outside `actuate_one/2` below, and all
  are `nil` (no-op) unless a caller deliberately sets them.

  ## Compensation failure: `:compensation_failed` (the sixth -- catastrophic -- outcome)

  Every rollback attempt this module makes (`revert_all/1`, called from both
  `:actuate`'s real `undo/3` -- a LATER step failed -- and from
  `actuate_pending/2`'s own internal self-heal -- `:actuate`'s OWN run
  failed) used to call `revert_one/2` directly and let a real revert failure
  (a target that became read-only or was deleted out from under the
  process) RAISE uncaught. Reactor's own `do_undo/6`
  (`deps/reactor/lib/reactor/executor/step_runner.ex`) has NO `rescue`
  around its call to `Step.undo/4` -- confirmed by reading that file
  directly, not assumed -- so a raise from inside `undo/3` used to propagate
  as a bare, uncaught exception all the way out of `Reactor.run/4`, past
  this module's OWN `run/1` `case` entirely. That is strictly WORSE than
  mis-reporting `:refused`: no receipt was persisted at all, for an attempt
  that genuinely mutated disk and then failed to restore it -- exactly the
  silent-catastrophe class this module's evidence guarantee (correction A)
  exists to close.

  Fixed: `revert_all/1` is now a real, best-effort, NEVER-RAISING operation
  -- each path's own revert is individually rescued (`revert_one_safe/2`),
  so one path's failure does not stop attempts on the others, and the
  overall result is a tagged `{:ok, restored_paths}` or
  `{:error, %{paths:, restored:, failed:}}` (`failed` :: `[{path,
  {module, message}}]`). Both call sites (`:actuate`'s `undo/3` and
  `actuate_pending/2`'s self-heal branch) now inspect this tagged result:
  on `:error`, they emit a real `COMPENSATION_FAILED` OCEL event and return
  `{:error, {:compensation_failed, details}}` from their OWN
  run/undo-callback -- Reactor's documented, non-raising failure contract
  (`{:error, reason}`), never a raw exception. `run/1`'s error branch
  (`find_compensation_failure/1`) recursively searches the returned
  `Reactor.Error` class for this specific tagged reason -- regardless of
  which step name Reactor happens to attach it to (`:actuate`'s undo
  failing surfaces as an `UndoStepError`; `:actuate`'s own self-heal failing
  surfaces as a `RunStepError` for `:actuate` itself) -- and when found,
  builds a `GgenIgniter.Receipt` with `standing: :compensation_failed`
  whose `reason` names, explicitly and in one sentence: that a real
  mutation occurred, that verification failed, that restoration
  (compensation) itself ALSO failed, the exact paths that could not be
  restored and why, which paths (if any) WERE restored, and that manual
  repair may be required. See `GgenIgniter.Receipt`'s moduledoc for this
  standing's full contract, and `test/ggen_igniter_compensation_failure_test.exs`
  for the real, no-mock proof (`File.chmod!/2` on a real target makes a
  real revert write fail, via the `:test_chmod_after_write` hook above).
  """

  use Reactor

  alias GgenIgniter.{
    Actuate,
    ArtifactIdentity,
    Engine,
    Frontmatter,
    Injection,
    Manifest,
    Ontology,
    Pack,
    PendingActuation,
    Receipt,
    Reconcile,
    Render
  }

  alias GgenIgniter.Telemetry.OcelEmitter

  input(:reconcile_opts)

  # side_effect: pure -- real disk read (`Manifest.load/1`), no mutation;
  # safe to retry/rerun with Reactor's default retry policy.
  step :observe_prior_manifest do
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{reconcile_opts: opts}, _context ->
      OcelEmitter.emit(opts[:event_sink], "RECONCILIATION_STARTED", [], %{
        "manifest_dir" => opts[:manifest_dir] || File.cwd!()
      })

      manifest_dir = opts[:manifest_dir] || File.cwd!()
      manifest = Manifest.load(manifest_dir)
      {:ok, %{manifest_dir: manifest_dir, manifest: manifest}}
    end)
  end

  # side_effect: pure -- real disk read (`Ontology.load!/1`), no mutation.
  step :load_ontology do
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{reconcile_opts: opts}, _context ->
      ontology_path = resolve_ontology_path!(opts)
      graph = Ontology.load!(ontology_path)
      {:ok, %{ontology_path: ontology_path, graph: graph}}
    end)
  end

  # side_effect: pure -- real disk read (`Pack.resolve_dir!/1`), no mutation.
  step :resolve_pack do
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{reconcile_opts: opts}, _context ->
      pack_dir = if pack_given?(opts), do: Pack.resolve_dir!(opts)
      {:ok, %{pack_dir: pack_dir}}
    end)
  end

  # side_effect: pure -- runs `Engine.prepare!/run` against the already-loaded
  # in-memory `graph`; no disk/network write, deterministic given the same
  # graph + query text.
  step :run_queries do
    argument(:reconcile_opts, input(:reconcile_opts))
    argument(:ontology, result(:load_ontology))

    run(fn %{reconcile_opts: opts, ontology: %{graph: graph}}, _context ->
      queried =
        opts
        |> normalize_targets()
        |> Enum.with_index()
        |> Enum.map(fn {target_opts, index} -> run_target_queries(target_opts, graph, index) end)

      {:ok, %{targets: queried}}
    end)
  end

  # side_effect: pure -- real template-file reads (`File.read!/1` in
  # `render_target/2`) plus in-memory rendering/manifest lookups; produces a
  # plan (`[%PendingActuation{}]`) but writes nothing to the filesystem.
  step :render do
    argument(:queried, result(:run_queries))
    argument(:observed, result(:observe_prior_manifest))
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{queried: %{targets: targets}, observed: %{manifest: manifest}, reconcile_opts: opts},
           _context ->
      base_dir = opts[:manifest_dir] || File.cwd!()
      plan = build_plan(targets, manifest, base_dir)

      OcelEmitter.emit(
        opts[:event_sink],
        "PLAN_CONSTRUCTED",
        file_objects(plan.pending),
        %{
          "target_count" => length(targets),
          "pending_count" => length(plan.pending)
        }
      )

      {:ok, plan}
    end)
  end

  # side_effect: observing -- no filesystem mutation; emits real
  # `OcelEmitter` telemetry (`ADMISSION_ACCEPTED` / `GUARD_REFUSED`) as its
  # only real-world effect. Fail-closed gate over the full plan.
  step :admit do
    argument(:render, result(:render))
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{render: render_out, reconcile_opts: opts}, _context ->
      case admit_pending(render_out, opts) do
        {:ok, result} ->
          OcelEmitter.emit(
            opts[:event_sink],
            "ADMISSION_ACCEPTED",
            file_objects(result.pending),
            %{
              "pending_count" => length(result.pending),
              "on_stale" => Atom.to_string(result.on_stale)
            }
          )

          {:ok, result}

        {:error, reason} = error ->
          OcelEmitter.emit(opts[:event_sink], "GUARD_REFUSED", [], %{"reason" => inspect(reason)})
          error
      end
    end)
  end

  # side_effect: mutating -- the ONLY step that writes real files
  # (`Actuate.write_file!/3`, `eval_code!/2`). `max_retries 0`: an
  # actuation-class step must never be silently retried by Reactor after a
  # failure (`run/3` already self-heals partial writes from ITS OWN failure
  # before returning `{:error, _}`; the real rollback-on-a-LATER-step-failure
  # path is `undo/4` below, not a Reactor-driven re-run of `run/3`). Real
  # `compensate/4` + `undo/4` both defined (see below).
  step :actuate do
    argument(:admitted, result(:admit))
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{admitted: admitted, reconcile_opts: opts}, _context ->
      actuate_pending(admitted, opts[:event_sink])
    end)

    compensate(fn _reason ->
      # `run/3` above already self-heals any partial writes from ITS OWN
      # failure (see `actuate_pending/2`'s `revert_all/1` call on the error
      # path) before ever returning `{:error, ...}` -- so there is nothing
      # left for this step's own compensation to revert. The real
      # rollback-on-a-LATER-step-failure path is `undo/3` below (Reactor's
      # actual mechanism for "a downstream step failed, roll back this
      # already-successful step" -- see this module's moduledoc).
      :ok
    end)

    undo(fn %{tracked: tracked}, %{reconcile_opts: opts} ->
      event_sink = opts[:event_sink]
      paths = Map.keys(tracked)
      pre_hash = Receipt.hash_entries(prior_entries(tracked))

      OcelEmitter.emit(event_sink, "COMPENSATION_STARTED", file_objects_for_paths(paths), %{
        "paths" => paths
      })

      case revert_all(tracked) do
        {:ok, _restored} ->
          post_hash = Receipt.hash_files(paths)

          OcelEmitter.emit(event_sink, "FILES_RESTORED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "pre_run_hash" => pre_hash,
            "post_run_hash" => post_hash,
            "matches_pre_run_hash" => post_hash == pre_hash
          })

          OcelEmitter.emit(event_sink, "COMPENSATION_COMPLETED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "matches_pre_run_hash" => post_hash == pre_hash
          })

          :ok

        {:error, %{restored: restored, failed: failed} = details} ->
          # CATASTROPHIC, real, and NEVER silently swallowed: a real mutation
          # happened (`paths`), a later step's failure triggered this real
          # undo, and the real restore attempt itself genuinely failed for
          # one or more paths -- see moduledoc "Compensation failure". This
          # is returned as a real Reactor `{:error, reason}` (Reactor's own
          # documented, non-raising undo-callback contract), NEVER left to
          # raise uncaught -- `run/1`'s `find_compensation_failure/1` is what
          # turns this into the real, distinct `:compensation_failed`
          # standing rather than `:refused`/`:alive`.
          OcelEmitter.emit(event_sink, "COMPENSATION_FAILED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "restored" => restored,
            "failed" =>
              Enum.map(failed, fn {path, reason} ->
                %{"path" => path, "reason" => inspect(reason)}
              end),
            "pre_run_hash" => pre_hash
          })

          {:error, {:compensation_failed, details}}
      end
    end)

    max_retries(0)
  end

  # side_effect: observing -- real `mix compile` subprocess against the
  # actuated project (does write build artifacts under `_build/`, but never
  # touches the tracked/undoable project files this pipeline reasons about);
  # its purpose is to CHECK the actuated state, not extend it.
  # `max_retries 0`: a failed compile is a genuine, non-transient signal
  # (`:build_broken`) this pipeline's compensation exists to protect
  # against -- it must never be silently retried by Reactor.
  step :verify do
    argument(:actuated, result(:actuate))
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn %{reconcile_opts: opts}, _context ->
      event_sink = opts[:event_sink]
      project_dir = opts[:verify_cwd] || opts[:manifest_dir] || File.cwd!()

      case System.cmd("mix", ["compile", "--warnings-as-errors"],
             cd: project_dir,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          OcelEmitter.emit(event_sink, "VERIFICATION_SUCCEEDED", [], %{})
          {:ok, :verified}

        {output, _status} ->
          OcelEmitter.emit(event_sink, "VERIFICATION_FAILED", [], %{
            "reason_type" => "build_broken",
            "message" => output
          })

          {:error, {:compile_failed, output}}
      end
    end)

    max_retries(0)
  end

  # side_effect: mutating -- real evidence writes (`Receipt.append!/2` FIRST,
  # then `Manifest.persist!/2`'s atomic rename, then any real `on_stale:
  # :prune` deletions -- see `finalize_evidence/1` and correction B).
  # `max_retries 0`, hardened to match `:actuate`/`:verify` (both explicit
  # actuation-class steps): this step performs real, durable side effects
  # (an append-only receipt write, an atomic manifest rename, real file
  # deletion) that must never be silently re-run by Reactor after a
  # failure -- a retried `Receipt.append!/2` in particular would append a
  # second, redundant line to the same real receipt log rather than fail
  # cleanly. No `compensate/4`/`undo/4` of its own: nothing this step writes
  # needs reverting on ITS OWN failure (see `finalize_evidence/1`'s ordering
  # -- the receipt is only durable once genuinely complete), and it is the
  # pipeline's terminal step, so no later step's failure can ever trigger an
  # `undo/4` against it.
  step :finalize_evidence do
    argument(:verify, result(:verify))
    argument(:admitted, result(:admit))
    argument(:actuated, result(:actuate))
    argument(:observed, result(:observe_prior_manifest))
    argument(:pack, result(:resolve_pack))
    argument(:ontology, result(:load_ontology))
    argument(:reconcile_opts, input(:reconcile_opts))

    run(fn args, _context -> finalize_evidence(args) end)

    max_retries(0)
  end

  return(:finalize_evidence)

  # -- Public entry point (correction A) -------------------------------------

  @doc """
  The recommended entry point: runs one full reconcile attempt for
  `reconcile_opts` (the same flat/`:targets` shape this module's steps
  accept -- see moduledoc). Unlike calling
  `Reactor.run(__MODULE__, %{reconcile_opts: reconcile_opts})` directly,
  this function GUARANTEES a real `GgenIgniter.Receipt` is persisted
  (`GgenIgniter.Receipt.append!/2`) on every path: `:alive` on success
  (already true of the bare `:finalize_evidence` step), and `:refused` /
  `:compensated` / `:build_broken` on the three real failure paths, which
  `:finalize_evidence` structurally cannot reach itself (it only runs after
  `:admit` + `:actuate` + `:verify` all succeed). See moduledoc's
  "Corrections applied" section (correction A).
  """
  @spec run(keyword()) :: {:ok, Receipt.t()} | {:error, Receipt.t()}
  def run(reconcile_opts) when is_list(reconcile_opts) do
    # `Reactor.run/4` requires the real `:reactor` OTP application to be
    # STARTED (not merely loaded/compiled): `Reactor.Application.start/2`
    # supervises `Reactor.Executor.ConcurrencyTracker`, the named ETS table
    # `Reactor.Executor.State.maybe_allocate_concurrency_pool/1` writes into
    # on every run -- confirmed by reading `deps/reactor/lib/reactor/
    # application.ex` directly. `mix ggen_igniter.sync` (this module's real
    # AR-9 caller, `Mix.Tasks.GgenIgniter.Sync.igniter/1`) is an
    # `Igniter.Mix.Task`, which does not itself guarantee `:reactor` was
    # started before `igniter/1` runs (unlike a full OTP release boot).
    # `Application.ensure_all_started/1` is idempotent and cheap when
    # `:reactor` is already running (the common case inside a real
    # `GgenIgniter.Application`-booted BEAM), so this is a safe, defensive
    # guarantee rather than a redundant no-op removed later.
    {:ok, _} = Application.ensure_all_started(:reactor)

    event_sink = OcelEmitter.new_sink()
    opts = Keyword.put(reconcile_opts, :event_sink, event_sink)
    manifest_dir = opts[:manifest_dir] || File.cwd!()
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    case Reactor.run(__MODULE__, %{reconcile_opts: opts}, %{}, async?: false) do
      {:ok, receipt} ->
        {:ok, receipt}

      {:error, error} ->
        events = OcelEmitter.drain_sink(event_sink)
        {step_name, original_reason} = failed_step_info(error)

        receipt =
          case find_compensation_failure(error) do
            {:ok, details} ->
              # CATASTROPHIC path: a real mutation occurred AND the real
              # attempt to undo it ALSO genuinely failed for one or more
              # paths -- see moduledoc "Compensation failure" and
              # `GgenIgniter.Receipt`'s moduledoc for this standing's full
              # contract. Deliberately NOT `standing_for_failure/2` (which
              # only ever produces the four ORIGINAL standings) -- this is
              # the one case this pipeline refuses to let collapse into
              # `:refused` (implying nothing was touched -- false) or
              # `:alive`/`:compensated` (implying restoration succeeded --
              # also false).
              #
              # `original_reason` above (from `failed_step_info/1`'s single
              # "first match" search) can genuinely BE the very same
              # `{:compensation_failed, _}` tuple -- Reactor's own
              # `state.errors` accumulates the compensation-tagged error
              # (prepended, since it is discovered LATER than the ORIGINAL
              # failure that triggered undo/self-heal in the first place)
              # ahead of the original one, so a naive "first match" grabs
              # the wrong one. `find_step_error/2` below searches
              # specifically for a DIFFERENT, non-compensation-tagged
              # reason (the real "why did verification/actuation fail in
              # the first place"), so the reason string never nonsensically
              # quotes the compensation failure as its own cause.
              {orig_step_name, orig_reason} =
                case find_step_error(error, &(not match?({:compensation_failed, _}, &1))) do
                  {:ok, name, reason} -> {name, reason}
                  :error -> {step_name, original_reason}
                end

              Receipt.new(%{
                standing: :compensation_failed,
                recipe_key: nil,
                started_at: started_at,
                # Deliberately `nil`, never a computed digest: some paths
                # restored and some did not, so there is no single coherent
                # "post-run project hash" to claim -- claiming one would
                # misrepresent a genuinely inconsistent on-disk state as a
                # verified-consistent one.
                pre_run_hash: event_attr(events, "COMPENSATION_FAILED", "pre_run_hash"),
                post_run_hash: nil,
                files: details.paths,
                events: events,
                reason: describe_compensation_failure(details, orig_reason),
                metadata: %{
                  "failed_step" => inspect(step_name),
                  "triggering_step" => inspect(orig_step_name),
                  "raw_error" => inspect(orig_reason),
                  "mutation_occurred" => true,
                  "verification_failed" => true,
                  "restoration_failed" => true,
                  "manual_repair_required" => true,
                  "compensation_restored_paths" => details.restored,
                  "compensation_failed_paths" =>
                    Enum.map(details.failed, fn {path, _reason} -> path end),
                  "compensation_failed_details" =>
                    Enum.map(details.failed, fn {path, reason} ->
                      %{"path" => path, "reason" => inspect(reason)}
                    end),
                  "post_run_state_hash" => Receipt.hash_files(details.paths)
                }
              })

            :error ->
              standing = standing_for_failure(step_name, original_reason)

              Receipt.new(%{
                standing: standing,
                recipe_key: nil,
                started_at: started_at,
                pre_run_hash: event_attr(events, "FILES_RESTORED", "pre_run_hash"),
                post_run_hash: event_attr(events, "FILES_RESTORED", "post_run_hash"),
                files: event_attr(events, "ACTUATION_STARTED", "paths") || [],
                events: events,
                reason: describe_failure(original_reason),
                metadata: %{
                  "failed_step" => inspect(step_name),
                  "raw_error" => inspect(original_reason)
                }
              })
          end

        Receipt.append!(manifest_dir, receipt)
        {:error, receipt}
    end
  end

  # -- Public entry point (read-only admission preview) --------------------

  @doc """
  Read-only admission preview backing `mix ggen_igniter.plan`
  (`Mix.Tasks.GgenIgniter.Plan` -- see that module's moduledoc for the full
  CLI contract). Runs the SAME observe-prior-manifest -> load-ontology ->
  resolve-pack -> run-queries -> render -> admit sequence `run/1` runs for a
  real reconciliation -- reusing the exact same private helpers
  (`normalize_targets/1`, `run_target_queries/3`, `build_plan/3`,
  `admit_pending/2`) rather than a parallel plan-only implementation -- but
  STOPS before `:actuate`/`:verify`/`:finalize_evidence` ever run: nothing is
  written to disk, no `GgenIgniter.Receipt` is persisted, and no manifest is
  promoted. This is a plain function, not a `Reactor.run/4` invocation --
  there is nothing here for Reactor's compensation/undo machinery to protect
  against, since no mutation ever happens on this path.

  Returns `{:ok, [%PendingActuation{}]}` -- the exact admitted plan `:admit`
  would hand to `:actuate`, unwrapped from `admit_pending/2`'s own
  `%{pending: pending, ...}` map since callers of `plan/1` (today, only
  `Mix.Tasks.GgenIgniter.Plan.report/3`) only need the list itself.

  `{:error, {:unsupported_capability, reason}}` when the resolved template
  has a `---` frontmatter header -- this bounded pipeline (like `run/1`,
  via `Mix.Tasks.GgenIgniter.Sync`'s own `run_via_reactor/3` guard) does not
  implement frontmatter parsing. `{:error, reason}` for any other
  admission-time refusal (one of `admit_pending/2`'s own tagged reasons:
  `:refused_duplicate_output_path` / `:refused_path_escapes_root` /
  `:refused_unowned_delete` / `:refused_stale_outputs`).

  Raises `ArgumentError` for an unresolvable input (missing/ambiguous
  template, ontology, or query) -- the same vocabulary `resolve_ontology_path!/1`
  and `resolve_template_path!/1` already raise for `run/1`; `Mix.Tasks.GgenIgniter.Plan`
  rescues this itself and turns it into exit code 2, this function does not
  catch its own raises.
  """
  @spec plan(keyword()) ::
          {:ok, [PendingActuation.t()]}
          | {:error, {:unsupported_capability, String.t()}}
          | {:error, term()}
  def plan(reconcile_opts) when is_list(reconcile_opts) do
    manifest_dir = reconcile_opts[:manifest_dir] || File.cwd!()
    manifest = Manifest.load(manifest_dir)

    ontology_path = resolve_ontology_path!(reconcile_opts)
    graph = Ontology.load!(ontology_path)

    template_path = resolve_template_path!(reconcile_opts)

    {frontmatter, _frontmatter_mode, _template_string} =
      Frontmatter.split_template(File.read!(template_path))

    if frontmatter != nil do
      {:error,
       {:unsupported_capability,
        "template frontmatter (#{template_path} has a --- header -- " <>
          "GgenIgniter.Reactors.ReconcileReactor.plan/1 does not implement frontmatter parsing)"}}
    else
      targets =
        reconcile_opts
        |> normalize_targets()
        |> Enum.with_index()
        |> Enum.map(fn {target_opts, index} -> run_target_queries(target_opts, graph, index) end)

      built_plan = build_plan(targets, manifest, manifest_dir)

      case admit_pending(built_plan, reconcile_opts) do
        {:ok, %{pending: pending}} -> {:ok, pending}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Pulls `{step_name, original_reason}` back out of Reactor's own error
  # taxonomy (`%Reactor.Error.Invalid{errors: [%Reactor.Error.Invalid.RunStepError{
  # step: %Reactor.Step{name: ...}, error: ...}, ...]}`, confirmed empirically
  # against a real minimal reactor, not assumed) -- matched structurally
  # (`%{step: %{name: _}, error: _}`) rather than against the exact struct
  # name, so this stays robust to Reactor internal error variants that carry
  # the same two fields.
  @doc false
  @spec failed_step_info(term()) :: {atom(), term()}
  def failed_step_info(%{errors: errors}) when is_list(errors) do
    case Enum.find(errors, &match?(%{step: %{name: _}, error: _}, &1)) do
      %{step: %{name: name}, error: reason} -> {name, reason}
      _ -> {:unknown, errors}
    end
  end

  def failed_step_info(other), do: {:unknown, other}

  # Recursively searches Reactor's own nested `Splode`-based error class
  # (`%Reactor.Error.Invalid{errors: [...]}`, each element either itself
  # nested (`.errors`) or a leaf carrying `.error` -- the same real shape
  # `failed_step_info/1` above already relies on) for a `{:compensation_failed,
  # details}` tagged reason placed there by `revert_all/1`'s two real call
  # sites (`:actuate`'s `undo/3` and `actuate_pending/2`'s self-heal branch).
  # Deliberately independent of `failed_step_info/1`'s "first match" choice
  # (which step's error `Enum.find/2` happens to pick first is irrelevant
  # here -- both real call sites tag the SAME reason shape, and this
  # function's whole point is to find it wherever it is, not to assume an
  # ordering).
  @doc false
  @spec find_compensation_failure(term()) :: {:ok, map()} | :error
  def find_compensation_failure(%{errors: errors}) when is_list(errors) do
    Enum.reduce_while(errors, :error, fn e, :error ->
      case find_compensation_failure(e) do
        {:ok, _details} = found -> {:halt, found}
        :error -> {:cont, :error}
      end
    end)
  end

  def find_compensation_failure(%{error: {:compensation_failed, details}}), do: {:ok, details}
  def find_compensation_failure(%{error: nested}), do: find_compensation_failure(nested)
  def find_compensation_failure(_other), do: :error

  # General-purpose sibling of `find_compensation_failure/1`: recursively
  # searches the same real nested `Splode` error shape for the FIRST leaf
  # `{step_name, reason}` pair whose `reason` satisfies `pred`. Used by
  # `run/1` to find the genuine ORIGINAL failure reason (e.g. `:verify`'s
  # real `{:compile_failed, output}`) specifically EXCLUDING any
  # `{:compensation_failed, _}`-tagged reason, since `state.errors`
  # accumulates the compensation error ahead of the original one (it is
  # discovered later, and Reactor prepends) -- a naive single "first match"
  # (like `failed_step_info/1`'s) can otherwise pick the wrong one.
  @doc false
  @spec find_step_error(term(), (term() -> boolean())) :: {:ok, atom(), term()} | :error
  def find_step_error(%{errors: errors}, pred) when is_list(errors) do
    Enum.reduce_while(errors, :error, fn e, :error ->
      case find_step_error(e, pred) do
        {:ok, _name, _reason} = found -> {:halt, found}
        :error -> {:cont, :error}
      end
    end)
  end

  def find_step_error(%{step: %{name: name}, error: reason}, pred) do
    cond do
      pred.(reason) -> {:ok, name, reason}
      match?(%{errors: _}, reason) -> find_step_error(reason, pred)
      true -> :error
    end
  end

  def find_step_error(_other, _pred), do: :error

  # Derives this attempt's real `GgenIgniter.Receipt.standing/0` from WHICH
  # step failed and WHY -- every pre-`:actuate` step failing means no file
  # was ever touched (`:refused`); `:verify` failing specifically because
  # the actuated project does not compile is the real `:build_broken` case;
  # every other post-`:actuate` failure (a `:verify` semantic failure,
  # `:actuate`'s own internal self-heal, or `:finalize_evidence`'s receipt
  # write failing) is `:compensated` -- real files were written, then
  # genuinely rolled back.
  @doc false
  @spec standing_for_failure(atom(), term()) :: Receipt.standing()
  def standing_for_failure(step_name, reason) do
    cond do
      step_name in [
        :observe_prior_manifest,
        :load_ontology,
        :resolve_pack,
        :run_queries,
        :render,
        :admit
      ] ->
        :refused

      step_name == :verify ->
        case reason do
          {:compile_failed, _output} -> :build_broken
          _ -> :compensated
        end

      step_name in [:actuate, :finalize_evidence] ->
        :compensated

      true ->
        :refused
    end
  end

  defp describe_failure({:compile_failed, output}),
    do: "verification failed (mix compile): #{output}"

  defp describe_failure({:refused_duplicate_output_path, collisions}),
    do: "refused: duplicate output path(s): #{inspect(collisions)}"

  defp describe_failure({:refused_path_escapes_root, canonical_target}),
    do:
      "refused: target #{inspect(canonical_target)} resolves outside the authorized project root"

  defp describe_failure({:refused_unowned_delete, target}),
    do: "refused: stale-prune candidate #{inspect(target)} is not owned by this recipe"

  defp describe_failure({:refused_stale_outputs, paths}),
    do: "refused: stale outputs with on_stale=refuse: #{inspect(MapSet.to_list(paths))}"

  defp describe_failure({:actuate_failed, reasons}),
    do: "actuation failed and was reverted: #{inspect(reasons)}"

  defp describe_failure(other), do: inspect(other)

  # Builds the CATASTROPHIC-standing reason string -- names, explicitly and
  # in one sentence, every fact `:compensation_failed`'s contract requires:
  # a real mutation occurred, verification failed (and why), restoration
  # (compensation) itself ALSO failed (and for which exact paths, and why),
  # which paths (if any) WERE genuinely restored, and that manual repair may
  # be required. See `GgenIgniter.Receipt`'s moduledoc for the full contract
  # this string is proving.
  defp describe_compensation_failure(
         %{paths: paths, restored: restored, failed: failed},
         original_reason
       ) do
    failed_desc =
      Enum.map_join(failed, "; ", fn {path, reason} -> "#{path} (#{inspect(reason)})" end)

    restored_clause =
      if restored != [] do
        "Successfully restored: #{inspect(restored)}. "
      else
        "No path was successfully restored. "
      end

    "CATASTROPHIC (:compensation_failed): a real mutation occurred (files actuated: " <>
      "#{inspect(paths)}); #{describe_failure(original_reason)}; " <>
      "restoration (compensation) of the pre-run state ALSO failed for: #{failed_desc}. " <>
      restored_clause <>
      "MANUAL REPAIR MAY BE REQUIRED -- the listed failed path(s) are left holding POST-run " <>
      "(mutated) content on disk, not their original pre-run content, and this receipt is the " <>
      "only durable record of that fact."
  end

  defp event_attr(events, activity, key) do
    case OcelEmitter.find_last(events, activity) do
      %{"attributes" => attrs} -> Map.get(attrs, key)
      _ -> nil
    end
  end

  # -- :run_queries / :render helpers --------------------------------------

  # Distinct "recipes" for this run: `opts[:targets]` (a list of per-target
  # keyword-list overrides merged onto the shared top-level opts), or -- when
  # absent -- the flat `opts` themselves as the single implicit target. This
  # single-target-by-default shape is exactly `Reconcile.run/1`'s own bounded
  # scope, which is what makes the parity test meaningful.
  @doc false
  @spec normalize_targets(keyword()) :: [keyword()]
  def normalize_targets(opts) do
    case Keyword.get(opts, :targets) do
      nil ->
        [opts]

      [] ->
        raise ArgumentError, "reconcile_opts[:targets] must not be an empty list when given"

      targets when is_list(targets) ->
        shared = Keyword.drop(opts, [:targets])
        Enum.map(targets, fn target -> Keyword.merge(shared, target) end)
    end
  end

  defp run_target_queries(target_opts, graph, index) do
    engine_name = target_opts[:engine] || "oxigraph"
    engine_module = Engine.fetch!(engine_name)
    template_path = resolve_template_path!(target_opts)
    named_queries = resolve_named_queries!(target_opts)
    query_context = engine_module.prepare!(graph, target_opts)

    named_results =
      Enum.map(named_queries, fn {name, text} ->
        {name, engine_module.run(query_context, text)}
      end)

    %{
      index: index,
      engine_name: engine_name,
      template_path: template_path,
      bindings: Reconcile.build_bindings(named_results),
      mode: resolve_mode!(target_opts[:mode]),
      out_template: target_opts[:out],
      write_opts: [
        unless_exists: target_opts[:unless_exists] || false,
        skip_if: target_opts[:skip_if],
        dry_run: target_opts[:dry_run] || false
      ],
      test_delay_ms: target_opts[:test_delay_ms],
      test_probe: target_opts[:test_probe],
      test_chmod_after_write: target_opts[:test_chmod_after_write]
    }
  end

  # Builds this run's REAL plan: `pending` is the full intended delta as
  # `[%PendingActuation{}]` -- one real create/replace/eval intent per
  # target, PLUS one real `operation: :delete` item per stale-prune
  # candidate `GgenIgniter.Manifest.stale_paths/2` finds for that target's
  # recipe -- never a bare `{out_path, content}` pair (see
  # `GgenIgniter.PendingActuation`'s own moduledoc). `recipes`/`exec` are
  # execution-only metadata that ride ALONGSIDE the real plan: `recipes`
  # is `:commit_manifest`'s existing, UNCHANGED manifest-commit bookkeeping
  # (recipe_key/template_path/out_template/out_path/old_entry/index), and
  # `exec` is `:actuate`'s per-target write options and test hooks
  # (`write_opts`/`test_delay_ms`/`test_probe`/`index`), keyed by each
  # item's own `logical_id` -- neither is part of the admission-relevant
  # IR itself, same real distinction `GgenIgniter.PendingActuation`'s
  # moduledoc draws for its own `desired_content` field.
  defp build_plan(targets, manifest, base_dir) do
    built = Enum.map(targets, &render_target(&1, manifest, base_dir))

    write_pending = Enum.map(built, & &1.pending_actuation)
    delete_pending = Enum.flat_map(built, & &1.stale_pending)
    recipes = for %{recipe: recipe} <- built, recipe != nil, do: recipe
    exec = for b <- built, into: %{}, do: {b.pending_actuation.logical_id, b.exec}

    %{pending: write_pending ++ delete_pending, recipes: recipes, exec: exec}
  end

  defp render_target(t, manifest, base_dir) do
    raw_template = File.read!(t.template_path)
    {frontmatter, _frontmatter_mode, body} = Frontmatter.split_template(raw_template)
    content = Render.render(body, t.bindings)

    exec = %{
      index: t.index,
      write_opts: t.write_opts,
      test_delay_ms: t.test_delay_ms,
      test_probe: t.test_probe,
      test_chmod_after_write: t.test_chmod_after_write
    }

    case t.mode do
      :file ->
        out_template =
          t.out_template ||
            raise ArgumentError, "target #{t.index}: :out is required for mode: file"

        out_path = Render.render(out_template, t.bindings)
        recipe_key = Manifest.recipe_key(t.template_path, out_template)
        old_entry = Manifest.get_entry(manifest, recipe_key)

        semantic_source = %{
          index: t.index,
          engine_name: t.engine_name,
          recipe_key: recipe_key,
          out_template: out_template
        }

        inject? = frontmatter != nil and (frontmatter.inject || false)

        if inject? do
          render_inject_target(
            t,
            base_dir,
            out_path,
            content,
            old_entry,
            semantic_source,
            frontmatter,
            exec
          )
        else
          render_file_target(t, base_dir, out_path, content, old_entry, semantic_source, exec)
        end

      :eval ->
        semantic_source = %{index: t.index, engine_name: t.engine_name, bindings: t.bindings}
        pending_actuation = PendingActuation.for_eval(content, t.template_path, semantic_source)

        %{pending_actuation: pending_actuation, stale_pending: [], recipe: nil, exec: exec}
    end
  end

  # `mode: file`, no `inject:` -- this function's body is the exact former
  # `:file` clause of `render_target/3`, extracted so `render_target/3` can
  # branch on `inject?` without duplicating the whole `:file` case.
  defp render_file_target(t, base_dir, out_path, content, old_entry, semantic_source, exec) do
    out_template = semantic_source.out_template
    recipe_key = semantic_source.recipe_key

    pending_actuation =
      PendingActuation.for_file(
        base_dir,
        out_path,
        content,
        t.template_path,
        out_template,
        old_entry,
        semantic_source
      )

    # Stale-prune detection now diffs by REAL canonical identity (never
    # the raw `out_path` string) -- see `GgenIgniter.PendingActuation`'s
    # `canonical_target` and this module's own moduledoc/red-team
    # citation: `GgenIgniter.Manifest`'s `outputs` keys are themselves
    # canonical identities (built the same way in `commit_recipe/5` /
    # `finalize_evidence/1` below), so comparing them against anything
    # OTHER than this run's own canonical identity would silently
    # reintroduce the exact alias-blindness this whole primitive exists
    # to close.
    stale = Manifest.stale_paths(old_entry, [pending_actuation.canonical_target])

    stale_pending =
      for path <- Enum.sort(MapSet.to_list(stale)) do
        PendingActuation.for_delete(
          base_dir,
          path,
          t.template_path,
          out_template,
          Map.put(semantic_source, :reason, :stale)
        )
      end

    recipe = %{
      index: t.index,
      recipe_key: recipe_key,
      template_path: t.template_path,
      out_template: out_template,
      out_path: out_path,
      canonical_out_path: pending_actuation.canonical_target,
      old_entry: old_entry
    }

    %{
      pending_actuation: pending_actuation,
      stale_pending: stale_pending,
      recipe: recipe,
      exec: exec
    }
  end

  # `mode: file`, frontmatter `inject: true` -- reuses
  # `GgenIgniter.Injection.resolve_injection!/1` (the SAME real
  # frontmatter-to-`inject_content!/5`-args conversion
  # `Mix.Tasks.GgenIgniter.Sync` uses, extracted to a shared module -- see
  # `GgenIgniter.Injection`'s moduledoc) to turn `before:`/`after:`/`at_line:`
  # into `marker`/`insert_mode`/`insert_opts`, then builds a real
  # `operation: :inject` `%PendingActuation{}` via `for_inject/9`.
  #
  # Deliberately no `recipe` (`recipe: nil`) and no `stale_pending`: an
  # inject target is never reconciliation-owned by this pack (mirrors
  # `Mix.Tasks.GgenIgniter.Sync`'s own `reconcile? = mode == :file and
  # inject_spec == nil` rule -- `inject_content!/5` requires and never
  # creates a PRE-EXISTING file this pack does not own, so treating a splice
  # target as "manufactured by this pack" would let `--on-stale prune`
  # delete a file this pack never created).
  defp render_inject_target(
         t,
         base_dir,
         out_path,
         content,
         old_entry,
         semantic_source,
         frontmatter,
         exec
       ) do
    {marker, insert_mode, insert_opts} = Injection.resolve_injection!(frontmatter)

    pending_actuation =
      PendingActuation.for_inject(
        base_dir,
        out_path,
        content,
        t.template_path,
        semantic_source.out_template,
        old_entry,
        Map.put(semantic_source, :insert_opts, insert_opts),
        marker,
        insert_mode
      )

    %{pending_actuation: pending_actuation, stale_pending: [], recipe: nil, exec: exec}
  end

  defp resolve_mode!(nil), do: :file
  defp resolve_mode!("file"), do: :file
  defp resolve_mode!("eval"), do: :eval
  defp resolve_mode!(:file), do: :file
  defp resolve_mode!(:eval), do: :eval

  defp resolve_mode!(other),
    do: raise(ArgumentError, "mode must be \"file\" or \"eval\", got: #{inspect(other)}")

  defp pack_given?(opts), do: opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""]

  defp resolve_ontology_path!(opts) do
    cond do
      opts[:ontology] not in [nil, ""] ->
        opts[:ontology]

      pack_given?(opts) ->
        path = Pack.default_ontology(Pack.resolve_dir!(opts))

        unless File.exists?(path) do
          raise ArgumentError, "pack/pack_dir resolved ontology not found at #{path}"
        end

        path

      true ->
        raise ArgumentError, "ontology is required (directly, or via pack/pack_dir)"
    end
  end

  defp resolve_template_path!(opts) do
    cond do
      opts[:template] not in [nil, ""] ->
        opts[:template]

      pack_given?(opts) ->
        pack_dir = Pack.resolve_dir!(opts)

        case Pack.discover_template(pack_dir, opts[:pack_template_stem]) do
          {:ok, path} ->
            path

          {:error, :none} ->
            raise ArgumentError,
                  "no *.eex/*.tmpl template found in #{pack_dir}/templates/ -- pass :template explicitly"

          {:error, {:ambiguous, paths}} ->
            raise ArgumentError,
                  "multiple templates found in #{pack_dir}/templates/ (#{Enum.join(paths, ", ")}) -- pass :template explicitly"

          {:error, {:stem_not_found, stem, paths}} ->
            raise ArgumentError,
                  "pack template stem #{inspect(stem)} did not match any template in #{pack_dir}/templates/ " <>
                    "(available: #{Enum.join(paths, ", ")})"
        end

      true ->
        raise ArgumentError, "template is required (directly, or via pack/pack_dir)"
    end
  end

  defp resolve_named_queries!(opts) do
    explicit =
      opts
      |> Keyword.get_values(:query)
      |> Enum.map(&parse_named_query!/1)
      |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

    if pack_given?(opts) do
      pack_dir = Pack.resolve_dir!(opts)

      pack_queries =
        pack_dir
        |> Pack.discover_queries()
        |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

      if pack_queries == [] and explicit == [] do
        raise ArgumentError,
              "no *.rq files found in #{pack_dir}/gates/ and no explicit query given"
      end

      Enum.reduce(explicit, pack_queries, fn {name, text}, acc ->
        List.keystore(acc, name, 0, {name, text})
      end)
    else
      if explicit == [] do
        raise ArgumentError,
              "at least one query name=path.rq is required (or use pack/pack_dir)"
      end

      explicit
    end
  end

  defp parse_named_query!(arg) do
    case String.split(arg, "=", parts: 2) do
      [name, path] -> {name, path}
      [_no_name] -> raise ArgumentError, "each query must be name=path.rq, got: #{arg}"
    end
  end

  # -- :admit ---------------------------------------------------------------

  # Inspects the FULL `[%PendingActuation{}]` plan (every real create/
  # replace/eval intent PLUS every real stale-prune `:delete` candidate) --
  # never just a list of output paths -- and enforces real, whole-plan
  # invariants no single-item view could catch:
  #
  #   * no two admitted `:create`/`:replace` items may share the same real
  #     ARTIFACT IDENTITY (`canonical_target`, from
  #     `GgenIgniter.ArtifactIdentity.canonicalize/2` -- NEVER the raw
  #     `target` string) -- a genuine whole-plan conflict. This is the
  #     direct, real fix for the confirmed adversarial finding in
  #     `.ggen_igniter_factory/redteam-concurrency-nondeterminism.md`: two
  #     `target` strings that differ only by a redundant `/./` segment (or
  #     `..`-traversal, or a symlinked alias) used to group into two
  #     separate `Enum.group_by(& &1.target)` buckets and sail past this
  #     guard entirely, letting `:actuate`'s real `Task.async_stream/3`
  #     race unprotected on the shared real file. Grouping by
  #     `canonical_target` instead means the exact alias construction that
  #     report reproduces is refused here, before `:actuate` ever runs --
  #     see `test/ggen_igniter_artifact_identity_test.exs`'s real, re-run
  #     11-iteration reproducer for the empirical proof against this fix.
  #   * no admitted item's `canonical_target` may escape the authorized
  #     project root (`GgenIgniter.ArtifactIdentity.within_root?/2`) -- a
  #     real path-traversal refusal, defense-in-depth alongside the
  #     duplicate check above (both are real artifact-identity invariants,
  #     checked the same way).
  #   * every `operation: :delete` item must carry `ownership: true` -- this
  #     pipeline refuses to ever plan deleting a path it does not itself
  #     own (mirrors `GgenIgniter.Manifest`'s own documented rule for
  #     `--on-stale prune`; real by construction via
  #     `GgenIgniter.PendingActuation.for_delete/5`, asserted here as a
  #     genuine admission-time invariant rather than trusted blindly).
  #   * `--on-stale refuse` (the default): any real stale `:delete`
  #     candidate refuses the ENTIRE run before anything is actuated.
  defp admit_pending(%{pending: pending, recipes: recipes, exec: exec}, opts) do
    on_stale = resolve_on_stale!(opts[:on_stale])
    base_dir = opts[:manifest_dir] || File.cwd!()

    write_pending = Enum.filter(pending, &(&1.operation in [:create, :replace, :inject]))
    delete_pending = Enum.filter(pending, &(&1.operation == :delete))

    duplicates =
      write_pending
      |> Enum.group_by(& &1.canonical_target)
      |> Enum.filter(fn {_identity, group} -> length(group) > 1 end)

    escaping_root =
      Enum.find(write_pending ++ delete_pending, fn item ->
        not ArtifactIdentity.within_root?(base_dir, item.target)
      end)

    unowned_delete = Enum.find(delete_pending, &(&1.ownership != true))
    stale_paths = delete_pending |> Enum.map(& &1.target) |> MapSet.new()

    cond do
      duplicates != [] ->
        collisions =
          Enum.map(duplicates, fn {identity, group} ->
            {identity, Enum.map(group, & &1.logical_id)}
          end)

        {:error, {:refused_duplicate_output_path, collisions}}

      escaping_root != nil ->
        {:error, {:refused_path_escapes_root, escaping_root.canonical_target}}

      unowned_delete != nil ->
        {:error, {:refused_unowned_delete, unowned_delete.target}}

      on_stale == :refuse and MapSet.size(stale_paths) > 0 ->
        {:error, {:refused_stale_outputs, stale_paths}}

      true ->
        {:ok,
         %{
           pending: pending,
           recipes: recipes,
           exec: exec,
           stale_paths: stale_paths,
           on_stale: on_stale
         }}
    end
  end

  # `nil` (flag omitted) resolves to the safest default, `:refuse` -- same
  # convention as `Mix.Tasks.GgenIgniter.Sync`'s own `resolve_on_stale!/1`
  # (silent orphaning must never be the default, silent deletion must never
  # be the default either). This tiny atom-parser is unavoidably duplicated
  # (sync.ex's own version is `defp`), not the real stale-detection logic
  # itself, which comes entirely from `GgenIgniter.Manifest`.
  defp resolve_on_stale!(nil), do: :refuse
  defp resolve_on_stale!("refuse"), do: :refuse
  defp resolve_on_stale!("prune"), do: :prune
  defp resolve_on_stale!("preserve"), do: :preserve

  defp resolve_on_stale!(other),
    do:
      raise(
        ArgumentError,
        "on_stale must be \"refuse\", \"prune\", or \"preserve\", got: #{inspect(other)}"
      )

  # -- :actuate ---------------------------------------------------------------

  # Actuates every admitted create/replace/eval item -- `operation: :delete`
  # items are deliberately excluded here (unchanged from this pipeline's
  # prior behavior): real stale-prune deletion stays at `:commit_manifest`,
  # run only AFTER `:verify` confirms the newly-actuated project compiles
  # (see this module's moduledoc, "Prune timing"). Each item's own real
  # `operation` field (`:create`/`:replace`/`:eval`) tells `actuate_one/2`
  # exactly what to do -- never re-derived from scratch here.
  defp actuate_pending(%{pending: pending, exec: exec}, event_sink) do
    actionable = Enum.filter(pending, &(&1.operation in [:create, :replace, :inject, :eval]))
    file_actionable = Enum.filter(actionable, &(&1.target != nil))
    max_concurrency = max(System.schedulers_online(), 1)

    OcelEmitter.emit(event_sink, "ACTUATION_STARTED", file_objects(file_actionable), %{
      "paths" => Enum.map(file_actionable, & &1.target)
    })

    tagged =
      actionable
      |> Task.async_stream(&actuate_one(&1, Map.fetch!(exec, &1.logical_id)),
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, tagged_result} -> tagged_result end)

    {oks, errors} = Enum.split_with(tagged, &match?({:ok, _}, &1))
    entries = Enum.map(oks, fn {:ok, entry} -> entry end)
    tracked = for e <- entries, e.tracked != nil, into: %{}, do: {e.tracked.path, e.tracked}

    if errors == [] do
      OcelEmitter.emit(event_sink, "FILES_CHANGED", file_objects_for_paths(Map.keys(tracked)), %{
        "paths" => Map.keys(tracked)
      })

      {:ok, %{results: entries, tracked: tracked}}
    else
      # Self-heal: this SAME `run/3` invocation already partially succeeded
      # before one target failed -- revert those real writes right here,
      # before ever returning `{:error, ...}`, so `:actuate`'s own failure
      # never leaves a half-migrated project on disk (independent of, and in
      # addition to, the real `undo/3` path for a LATER step's failure).
      # Emits the same real OCEL events `undo/3` would, for the same real
      # reason: a consequential actuation genuinely happened here too.
      paths = Map.keys(tracked)
      pre_hash = Receipt.hash_entries(prior_entries(tracked))

      OcelEmitter.emit(event_sink, "FILES_CHANGED", file_objects_for_paths(paths), %{
        "paths" => paths
      })

      OcelEmitter.emit(event_sink, "COMPENSATION_STARTED", file_objects_for_paths(paths), %{
        "paths" => paths
      })

      reasons = Enum.map(errors, fn {:error, reason} -> reason end)

      case revert_all(tracked) do
        {:ok, _restored} ->
          post_hash = Receipt.hash_files(paths)

          OcelEmitter.emit(event_sink, "FILES_RESTORED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "pre_run_hash" => pre_hash,
            "post_run_hash" => post_hash,
            "matches_pre_run_hash" => post_hash == pre_hash
          })

          OcelEmitter.emit(event_sink, "COMPENSATION_COMPLETED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "matches_pre_run_hash" => post_hash == pre_hash
          })

          {:error, {:actuate_failed, reasons}}

        {:error, %{restored: restored, failed: failed} = details} ->
          # Same real, non-raising `:compensation_failed` contract as
          # `:actuate`'s own `undo/3` above -- see moduledoc "Compensation
          # failure". This is `:actuate`'s OWN `run/3` returning
          # `{:error, ...}` (self-heal, not a later step's undo), so it
          # surfaces via Reactor as a `RunStepError` for `:actuate` itself
          # rather than an `UndoStepError` -- `find_compensation_failure/1`
          # in `run/1` handles both shapes identically.
          OcelEmitter.emit(event_sink, "COMPENSATION_FAILED", file_objects_for_paths(paths), %{
            "paths" => paths,
            "restored" => restored,
            "failed" =>
              Enum.map(failed, fn {path, reason} ->
                %{"path" => path, "reason" => inspect(reason)}
              end),
            "pre_run_hash" => pre_hash,
            "actuate_reasons" => inspect(reasons)
          })

          {:error, {:compensation_failed, details}}
      end
    end
  end

  defp actuate_one(%PendingActuation{operation: :eval} = pa, exec) do
    bindings = Map.get(pa.semantic_source, :bindings, [])
    {:ok, value} = Actuate.eval_code!(pa.desired_content, bindings)

    {:ok,
     %{
       index: exec.index,
       mode: :eval,
       out_path: nil,
       canonical_target: nil,
       outcome: nil,
       value: value,
       tracked: nil
     }}
  rescue
    e -> {:error, %{index: exec.index, mode: :eval, reason: {e.__struct__, Exception.message(e)}}}
  end

  defp actuate_one(%PendingActuation{operation: op} = pa, exec) when op in [:create, :replace] do
    probe_mark(exec, :start)
    if exec.test_delay_ms && exec.test_delay_ms > 0, do: Process.sleep(exec.test_delay_ms)

    prior = if File.exists?(pa.target), do: {:existed, File.read!(pa.target)}, else: :new
    {:ok, outcome} = Actuate.write_file!(pa.target, pa.desired_content, exec.write_opts)
    maybe_test_chmod!(pa.target, exec, outcome)
    probe_mark(exec, :stop)

    # A `:dry_run` write never touched the filesystem; `:skipped_exists`/
    # `:skipped_match` mean this run deliberately left the target alone --
    # neither actually mutated `pa.target`, so neither is tracked for
    # reversion (mirrors `GgenIgniter.Manifest`'s own "only a path this run
    # actually wrote/reconfirmed is manifest-owned" rule). Note this real
    # outcome is intentionally independent of `pa.operation`: an unchanged
    # re-run still carries `operation: :replace` (derived from real
    # existence at plan time) while the real outcome here comes back
    # `:unchanged` (derived from a real byte-for-byte content compare) --
    # two different, both-real facts, never conflated.
    tracked =
      if exec.write_opts[:dry_run] or outcome in [:skipped_exists, :skipped_match] do
        nil
      else
        %{path: pa.target, prior: prior}
      end

    {:ok,
     %{
       index: exec.index,
       mode: :file,
       out_path: pa.target,
       canonical_target: pa.canonical_target,
       outcome: outcome,
       tracked: tracked
     }}
  rescue
    e ->
      {:error,
       %{
         index: exec.index,
         mode: :file,
         out_path: pa.target,
         reason: {e.__struct__, Exception.message(e)}
       }}
  end

  # `operation: :inject` dispatch -- calls `Actuate.inject_content!/5`
  # directly (never `write_file!/3`), reusing the SAME real
  # `marker`/`insert_mode`/`insert_opts` `render_inject_target/8` already
  # resolved via `GgenIgniter.Injection.resolve_injection!/1` and stashed on
  # `pa.semantic_source` -- never re-derived here. `Actuate.inject_content!/5`
  # itself is the real fail-closed gate this clause relies on: a missing
  # target file, a missing anchor (marker matches zero lines), or an
  # ambiguous anchor (marker matches more than one line) all raise a real
  # `ArgumentError` from inside `inject_content!/5` -- rescued below into the
  # same `{:error, %{index:, mode:, out_path:, reason:}}` shape the
  # `:create`/`:replace` clause already produces, so a bad anchor on one
  # target self-heals (reverts any OTHER targets this same `:actuate`
  # invocation already wrote) exactly like any other actuation failure,
  # never leaving a half-migrated project on disk.
  defp actuate_one(%PendingActuation{operation: :inject} = pa, exec) do
    probe_mark(exec, :start)
    if exec.test_delay_ms && exec.test_delay_ms > 0, do: Process.sleep(exec.test_delay_ms)

    prior = if File.exists?(pa.target), do: {:existed, File.read!(pa.target)}, else: :new
    marker = pa.semantic_source[:marker]
    insert_mode = pa.semantic_source[:insert_mode]
    dry_run = exec.write_opts[:dry_run] || false

    inject_opts =
      (pa.semantic_source[:insert_opts] || [])
      |> Keyword.put(:dry_run, dry_run)

    {:ok, outcome} =
      Actuate.inject_content!(
        pa.target,
        marker,
        Injection.strip_single_trailing_newline(pa.desired_content),
        insert_mode,
        inject_opts
      )

    maybe_test_chmod!(pa.target, exec, outcome)
    probe_mark(exec, :stop)

    # `:injected` -- a real splice happened, this run's own responsibility
    # to revert on a later failure. `:unchanged` -- the body was already
    # present exactly where this exact injection would place it (idempotent
    # re-run); a `:dry_run` inject never touches the filesystem either.
    # Neither is tracked for reversion, mirroring the `:create`/`:replace`
    # clause's own `:unchanged`/`:dry_run` exclusion.
    tracked =
      if dry_run or outcome == :unchanged do
        nil
      else
        %{path: pa.target, prior: prior}
      end

    {:ok,
     %{
       index: exec.index,
       mode: :inject,
       out_path: pa.target,
       canonical_target: pa.canonical_target,
       outcome: outcome,
       tracked: tracked
     }}
  rescue
    e ->
      {:error,
       %{
         index: exec.index,
         mode: :inject,
         out_path: pa.target,
         reason: {e.__struct__, Exception.message(e)}
       }}
  end

  # Test-only instrumentation -- see moduledoc "Testing hooks". Inert unless
  # a caller explicitly sets `:test_probe` on a target.
  defp probe_mark(%{test_probe: table} = exec, event) when is_atom(table) and not is_nil(table) do
    :ets.insert(table, {{exec.index, event}, System.monotonic_time(:millisecond)})
  end

  defp probe_mark(_exec, _event), do: :ok

  # Test-only instrumentation -- see moduledoc "Testing hooks". Inert unless
  # a caller explicitly sets `:test_chmod_after_write` on a target. Only
  # applied when the write actually, really mutated the target
  # (`:written`) -- a `:skipped_exists`/`:skipped_match`/`:dry_run` outcome
  # never touched the file, so there is nothing meaningful to lock down.
  defp maybe_test_chmod!(target, %{test_chmod_after_write: mode}, :written)
       when is_integer(mode) do
    File.chmod!(target, mode)
  end

  defp maybe_test_chmod!(_target, _exec, _outcome), do: :ok

  # REAL, best-effort, NEVER-RAISING revert of every `{path, prior}` in
  # `tracked` -- see moduledoc "Compensation failure: `:compensation_failed`".
  # One path's own revert failure does not stop attempts on the others
  # (`Enum.map/2`, not `Enum.each/2` with early-raise): a partial
  # compensation that restores everything IT CAN is strictly more useful,
  # and more honest, than one that aborts on the first failure and leaves
  # every OTHER path un-attempted too.
  #
  # Returns `{:ok, restored_paths}` when every path restored cleanly, or
  # `{:error, %{paths:, restored:, failed:}}` (`failed` :: `[{path,
  # {module, message}}]`) when one or more paths could NOT be restored --
  # this is the real signal `:compensation_failed` exists to surface, never
  # swallowed and never left to raise uncaught into Reactor's own
  # undo-callback boundary (which has no rescue of its own -- see moduledoc).
  @spec revert_all(map()) ::
          {:ok, [String.t()]}
          | {:error,
             %{paths: [String.t()], restored: [String.t()], failed: [{String.t(), term()}]}}
  defp revert_all(tracked) when is_map(tracked) do
    paths = Map.keys(tracked)

    {restored, failed} =
      tracked
      |> Enum.map(fn {path, %{prior: prior}} -> {path, revert_one_safe(path, prior)} end)
      |> Enum.split_with(fn {_path, result} -> result == :ok end)

    restored_paths = Enum.map(restored, fn {path, _ok} -> path end)

    if failed == [] do
      {:ok, restored_paths}
    else
      failed_reasons = Enum.map(failed, fn {path, {:error, reason}} -> {path, reason} end)
      {:error, %{paths: paths, restored: restored_paths, failed: failed_reasons}}
    end
  end

  # Rescues ANY raise from the real revert attempt (`File.Error`,
  # `RuntimeError` from `revert_one/2`'s own :new-branch guard, or any other
  # exception a real filesystem operation can throw) into a plain, inspectable
  # `{:error, {module, message}}` -- this function must NEVER let an
  # exception escape, since both its call sites feed a Reactor
  # run/undo-callback boundary that has no rescue of its own.
  defp revert_one_safe(path, prior) do
    revert_one(path, prior)
    :ok
  rescue
    e -> {:error, {e.__struct__, Exception.message(e)}}
  end

  defp revert_one(path, {:existed, prior_content}), do: File.write!(path, prior_content)

  defp revert_one(path, :new) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, "failed to revert (delete) #{path}: #{inspect(reason)}"
    end
  end

  # `tracked` (`%{path => %{path:, prior: {:existed, content} | :new}}`) ->
  # `[{path, content_or_nil}]`, the shape `GgenIgniter.Receipt.hash_entries/1`
  # needs to hash a PRE-image without re-reading disk (the pre-image is
  # exactly what this run is about to overwrite/has already overwritten).
  defp prior_entries(tracked) do
    Enum.map(tracked, fn
      {path, %{prior: {:existed, content}}} -> {path, content}
      {path, %{prior: :new}} -> {path, nil}
    end)
  end

  defp file_objects(pending), do: Enum.map(pending, &OcelEmitter.file_object(&1.target))
  defp file_objects_for_paths(paths), do: Enum.map(paths, &OcelEmitter.file_object/1)

  # -- :finalize_evidence (correction B) --------------------------------------

  defp finalize_evidence(%{
         admitted: admitted,
         actuated: %{results: results, tracked: tracked},
         observed: observed,
         pack: %{pack_dir: pack_dir},
         ontology: %{ontology_path: ontology_path},
         reconcile_opts: opts
       }) do
    event_sink = opts[:event_sink]
    manifest_dir = observed.manifest_dir

    # -- 1. Prepare BOTH the next manifest content and the new receipt
    # payload, in memory -- nothing durable written yet.
    {new_manifest, manifest_changed?} =
      Enum.reduce(admitted.recipes, {observed.manifest, false}, fn recipe,
                                                                   {manifest_acc, changed_acc} ->
        commit_recipe(recipe, results, manifest_acc, changed_acc, pack_dir)
      end)

    # Keyed by real canonical identity (`GgenIgniter.ArtifactIdentity`),
    # never the raw `out_path` string -- this is what makes `GgenIgniter.
    # Receipt`'s `files` field (below, via `Map.keys(outputs)`) a real
    # artifact-identity list rather than a raw-path list (ticket item 4:
    # "Receipt's output identity"). `File.read!/1` still reads the real,
    # literal `path` -- canonical identity is an identity/comparison value
    # only, never substituted for the actual I/O path.
    outputs =
      for %{mode: :file, out_path: path, canonical_target: canonical, outcome: outcome} <-
            results,
          outcome in [:written, :unchanged],
          into: %{},
          do: {canonical, Manifest.hash_content(File.read!(path))}

    graph_hash =
      "sha256:" <>
        (:crypto.hash(:sha256, File.read!(ontology_path)) |> Base.encode16(case: :lower))

    single_recipe = if length(admitted.recipes) == 1, do: List.first(admitted.recipes), else: nil
    single_result = List.first(results)

    pre_run_hash = Receipt.hash_entries(prior_entries(tracked))
    post_run_hash = Receipt.hash_files(Map.keys(tracked))

    OcelEmitter.emit(event_sink, "ADMITTED", file_objects_for_paths(Map.keys(outputs)), %{
      "paths" => Map.keys(outputs)
    })

    OcelEmitter.emit(
      event_sink,
      "EVIDENCE_FINALIZED",
      file_objects_for_paths(Map.keys(outputs)),
      %{
        "paths" => Map.keys(outputs),
        "pre_run_hash" => pre_run_hash,
        "post_run_hash" => post_run_hash
      }
    )

    OcelEmitter.emit(event_sink, "RECONCILIATION_ALIVE", [], %{
      "standing" => "alive",
      "target_count" => length(results)
    })

    events = OcelEmitter.peek_sink(event_sink)

    receipt =
      Receipt.new(%{
        standing: :alive,
        recipe_key: single_recipe && single_recipe.recipe_key,
        pre_run_hash: pre_run_hash,
        post_run_hash: post_run_hash,
        files: Map.keys(outputs),
        events: events,
        reason: nil,
        metadata: %{
          "graph_hash" => graph_hash,
          "target_count" => length(results),
          # Best-effort single-target compatibility fields (populated
          # whenever this run had exactly one target, i.e. the
          # `Reconcile.run/1`-parity shape).
          "out_path" => single_result && single_result[:out_path],
          "outcome" =>
            single_result && single_result[:outcome] && Atom.to_string(single_result[:outcome]),
          "mode" => single_result && single_result[:mode] && Atom.to_string(single_result[:mode]),
          "notice" => "ggen_igniter reactor: #{length(results)} target(s) actuated"
        }
      })

    # -- 2. Persist the receipt FIRST (real append-only write). If this
    # itself raises, this step fails like any other -- Reactor's own undo
    # then rolls back `:actuate`'s real writes (a real, if unusual,
    # `:compensated` outcome via `run/1`'s failure path, since this step
    # never gets to build a receipt of its own in that case).
    :ok = Receipt.append!(manifest_dir, receipt)

    # -- 3. Only now attempt to promote the manifest, atomically
    # (`Manifest.persist!/2`'s own temp-file-then-`File.rename!/2` protocol,
    # unchanged). A failure HERE is caught locally, NOT re-raised: the files
    # were genuinely written and verified, so rolling them back because the
    # manifest CACHE could not be updated would be wrong -- the already-
    # durable receipt above is the real recovery anchor for a retry.
    manifest_promotion =
      if manifest_changed? do
        try do
          Manifest.persist!(new_manifest, manifest_dir)
          :promoted
        rescue
          exception -> {:pending, Exception.message(exception)}
        end
      else
        :unchanged
      end

    # Real, deliberate hardening (Reactor step-decomposition audit,
    # 2026-08-27): this call runs AFTER the receipt above is already
    # DURABLE on disk (`Receipt.append!/2` at step 2 succeeded). Before this
    # fix, `Manifest.prune!/1` ran unguarded here -- if it raised (a real,
    # documented `RuntimeError` path in `Manifest.prune!/1` for any
    # unexpected `File.rm/1` failure, e.g. a permissions error), THIS WHOLE
    # step would fail, and since `:finalize_evidence` is a LATER step than
    # `:actuate`, Reactor's real `undo/4` would then revert `:actuate`'s
    # writes (see moduledoc, "`compensate/4` vs `undo/4`") -- even though
    # the receipt ALREADY durably recorded `standing: :alive` for those same
    # files one line above. Worse, `run/1`'s own `{:error, _}` branch would
    # then persist a SECOND, contradictory `:compensated` receipt line for
    # the same physical attempt (`standing_for_failure/2` maps
    # `:finalize_evidence` to `:compensated`). Caught locally instead,
    # exactly like `manifest_promotion` above and for the identical reason:
    # a prune failure is real evidence, but not a reason to contradict an
    # already-durable, correct `:alive` receipt or roll back files that were
    # genuinely written and verified. `metadata["prune_outcome"]` records
    # the real outcome either way.
    prune_outcome =
      if admitted.on_stale == :prune and MapSet.size(admitted.stale_paths) > 0 do
        try do
          {:pruned, Manifest.prune!(MapSet.to_list(admitted.stale_paths))}
        rescue
          exception -> {:prune_failed, Exception.message(exception)}
        end
      else
        :not_applicable
      end

    OcelEmitter.emit(event_sink, "STANDING_SET", [], %{
      "standing" => "alive",
      "manifest_promotion" => inspect(manifest_promotion),
      "prune_outcome" => inspect(prune_outcome)
    })

    final_receipt = %{
      receipt
      | metadata:
          receipt.metadata
          |> Map.put("manifest_promotion", inspect(manifest_promotion))
          |> Map.put("prune_outcome", inspect(prune_outcome))
    }

    {:ok, final_receipt}
  end

  defp commit_recipe(recipe, results, manifest_acc, changed_acc, pack_dir) do
    result = Enum.find(results, &(&1.index == recipe.index))

    if result && result.outcome in [:written, :unchanged] do
      # `GgenIgniter.Manifest`'s `outputs` map is keyed by real canonical
      # identity (`recipe.canonical_out_path`, from `GgenIgniter.
      # ArtifactIdentity`), never the raw `recipe.out_path` string (ticket
      # item 3: "Manifest's keys"). `File.read!/1` still reads the real,
      # literal `out_path`.
      outputs = %{
        recipe.canonical_out_path => Manifest.hash_content(File.read!(recipe.out_path))
      }

      if Manifest.same_outputs?(recipe.old_entry, outputs) do
        {manifest_acc, changed_acc}
      else
        entry = Manifest.build_entry(recipe.template_path, recipe.out_template, pack_dir, outputs)
        {Manifest.put(manifest_acc, recipe.recipe_key, entry), true}
      end
    else
      {manifest_acc, changed_acc}
    end
  end
end
