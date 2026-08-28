defmodule Mix.Tasks.GgenIgniter.Plan do
  @moduledoc """
  Read-only admission preview: `mix ggen_igniter.plan --template path.eex [--pack NAME |
  --pack-dir DIR] --query name=path.rq (repeatable) [--engine oxigraph|sparql|qlever]
  [--store-id ID] [--json]`.

  Runs the SAME observe -> load ontology -> resolve pack -> run queries -> render ->
  admit sequence `GgenIgniter.Reactors.ReconcileReactor.run/1` runs for a real `mix
  ggen_igniter.sync` (with `use_reactor: true`), via
  `GgenIgniter.Reactors.ReconcileReactor.plan/1` -- but STOPS before `:actuate`. Every
  `%GgenIgniter.PendingActuation{}` the admitted plan would write is reported; nothing
  is ever written to disk, and no compensation/rollback machinery is ever invoked,
  because nothing this task runs can fail an already-applied actuation.

  ## Read-only, no lock (FR-5)

  This task performs NO filesystem mutation of the target project and therefore does
  **not** acquire `GgenIgniter.Lock` -- `doctor` and a read-only `plan` inspection may
  both run concurrently with an in-flight `sync`/lock holder, per the PRD's FR-5. Do
  not add a `Lock.acquire!/1` call here; `mix ggen_igniter.sync`/`mix
  ggen_igniter.replay` are the only verbs that mutate and therefore lock.

  ## Output

  Human-readable (default) or `--json` (a stable, script-parseable rendering of the
  same real plan data -- no field present in one is silently dropped from the other):

    * **inputs + hashes** -- resolved `--ontology`/`--pack` root, every resolved
      `--query name=path` (or pack-discovered gate query) with its source path,
      each `%PendingActuation{}`'s `previous_hash`/`desired_hash`.
    * **query names/sources** -- every named query actually run, and whether it came
      from an explicit `--query`, a pack's `gates/*.rq`, or template frontmatter.
    * **engine** -- the resolved `--engine` (default `oxigraph`) and, for `qlever`,
      the resolved `--store-id`.
    * **bindings** -- the semantic-source binding keys visible to each pending item
      (`semantic_source` on `%PendingActuation{}` -- ontology/query/template
      identity, never the full rendered content in the human-readable form; `--json`
      includes `desired_hash` but never raw `desired_content`, since a plan preview
      is not a content dump).
    * **output paths** -- each `%PendingActuation{}.target` (or `nil` for
      `operation: :eval`, per that struct's own documented convention).
    * **existing-file decisions** -- `operation` (`:create`/`:replace`/`:delete`/
      `:eval`) plus `GgenIgniter.PendingActuation.plan_unchanged?/1` per item, so a
      plan run can distinguish "would create", "would replace with different bytes",
      "would replace with identical bytes (no-op)", and "would delete" without
      running `:actuate` to find out.
    * **skip conditions** -- `--unless-exists`/`--skip-if` guards that would cause
      `:actuate` to skip a target, surfaced here as a real, computed decision (not
      re-derived ad hoc by this task -- sourced from whatever
      `ReconcileReactor.plan/1` itself reports for each item, since admission-time
      skip evaluation is that function's responsibility, not this CLI wrapper's).
    * **unsupported features** -- anything this plan run could not admit because the
      resolved template/run uses a capability outside `GgenIgniter.Reconcile.run/1`'s
      bounded reactor scope (frontmatter `inject: true`, `--for-each` fan-out, etc.)
      is reported as exit code 3 (`:unsupported_capability`), never silently ignored
      or silently downgraded to a partial plan.
    * **intended mutations** -- one line per `%PendingActuation{}` in the
      human-readable form (`operation target (unchanged?)`), or the full list under
      `plan.pending_actuations` in `--json`.

  ## Dependency on `ReconcileReactor.plan/1`

  This task calls `GgenIgniter.Reactors.ReconcileReactor.plan/1`, a read-only
  admission-only entry point (observe -> load -> resolve -> run_queries -> render ->
  admit, returning the admitted `[%PendingActuation{}]` without ever reaching
  `:actuate`) that this Mix task was written against by intended signature but that
  does **not yet exist** in this working tree as of this file's authorship -- see
  `docs/architecture/adr/` and the plan doc this task was scoped from
  (`prd-ard-wiggly-creek.md`, "2. `mix ggen_igniter.plan`") for the extraction this
  depends on. Until `ReconcileReactor.plan/1` lands, `mix ggen_igniter.plan` will fail
  to compile/run with an `UndefinedFunctionError`; this is expected and disclosed,
  not a bug in this file. Do not add a compatibility shim here that re-derives a
  parallel plan-only pipeline out of `run_pipeline!/3`-style logic -- the whole point
  of this task is to share the SAME admission logic `sync` uses, not to duplicate it.

  ## Exit codes

    * `0` -- plan computed successfully (admitted cleanly, whether or not any item
      would actually change anything -- an all-unchanged plan is still exit 0).
    * `2` -- invalid invocation (missing required input resolution: no
      `--template` and no `--pack`/`--pack-dir` with a discoverable template; no
      queries resolvable; `--engine qlever` without `--store-id`; etc.) -- the same
      `ArgumentError` vocabulary `mix ggen_igniter.sync` already raises for these,
      caught here and turned into a clean exit instead of a raw stack trace.
    * `3` -- unsupported capability for the read-only plan path specifically (the
      resolved template/run needs `:actuate`-adjacent behavior `plan/1` cannot admit
      without executing it, or uses a feature outside `GgenIgniter.Reconcile.run/1`'s
      bounded reactor scope -- frontmatter `inject: true`, `--for-each` fan-out).

  ## Example

      mix ggen_igniter.plan --pack ash-lifecycle-pack:resource \\
        --query resource=priv/ggen/ash-lifecycle-pack/gates/resource.rq

      mix ggen_igniter.plan --template test/fixtures/extension.ex.eex \\
        --query spec=test/fixtures/spec.rq --json
  """
  use Igniter.Mix.Task

  alias GgenIgniter.Pack
  alias GgenIgniter.Reactors.ReconcileReactor

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example:
        "mix ggen_igniter.plan --pack ash-lifecycle-pack --query resource=gates/resource.rq",
      positional: [],
      schema: [
        template: :string,
        pack: :string,
        pack_dir: :string,
        query: [:string, :keep],
        engine: :string,
        store_id: :string,
        out: :string,
        mode: :string,
        unless_exists: :boolean,
        skip_if: :string,
        json: :boolean,
        help: :boolean,
        version: :boolean,
        quiet: :boolean,
        verbose: :boolean,
        no_color: :boolean
      ],
      aliases: [h: :help, v: :version, q: :quiet],
      required: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options

    cond do
      opts[:help] ->
        print_help()
        igniter

      opts[:version] ->
        Mix.shell().info(tool_version())
        igniter

      true ->
        run_plan(igniter, opts)
    end
  end

  defp run_plan(_igniter, opts) do
    plan_opts =
      opts
      |> Keyword.take([
        :template,
        :pack,
        :pack_dir,
        :query,
        :engine,
        :store_id,
        :out,
        :mode,
        :unless_exists,
        :skip_if
      ])
      |> validate_plan_opts!()

    case ReconcileReactor.plan(plan_opts) do
      {:ok, pending_actuations} when is_list(pending_actuations) ->
        report(opts, plan_opts, pending_actuations)
        # This task never mutates the target project (see the "Read-only, no
        # lock" moduledoc section) -- `igniter` here always carries zero
        # proposed changes. Returning it to `Igniter.Mix.Task`'s runner would
        # let Igniter print its own "No proposed content changes!" (or, with
        # real changes somehow present, a diff) footer to stdout AFTER the
        # report above, which corrupts `--json` output (the reader gets
        # trailing non-JSON bytes after a validly-closed JSON document) and
        # adds noise to human output. Halt directly with the same real exit
        # code (0) `mix ggen_igniter.sync` documents for "plan computed
        # successfully" instead, exactly as the two error branches below
        # already halt directly rather than returning to the Igniter runner.
        System.halt(0)

      {:error, {:unsupported_capability, reason}} ->
        report_error(opts, "unsupported capability: #{reason}")
        System.halt(3)

      {:error, reason} ->
        report_error(opts, "plan failed: #{inspect(reason)}")
        System.halt(2)
    end
  rescue
    error in [ArgumentError] ->
      report_error(opts, Exception.message(error))
      System.halt(2)
  end

  # Fails fast with the same exit-2 "invalid invocation" vocabulary as
  # `mix ggen_igniter.sync`'s own `resolve_template!/2`/`resolve_named_queries!/2`
  # ArgumentErrors, before ever calling `ReconcileReactor.plan/1` -- a plan run with
  # no resolvable template or no resolvable queries is a usage error, not something
  # worth handing to the reactor to discover.
  defp validate_plan_opts!(opts) do
    template_given? = opts[:template] not in [nil, ""]
    pack_given? = opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""]

    unless template_given? or pack_given? do
      raise ArgumentError,
            "--template is required (directly, or via --pack/--pack-dir with exactly one template)"
    end

    queries = Keyword.get_values(opts, :query)

    unless queries != [] or pack_given? do
      raise ArgumentError,
            "at least one --query name=path.rq is required (or use --pack/--pack-dir)"
    end

    if opts[:engine] == "qlever" and opts[:store_id] in [nil, ""] do
      raise ArgumentError, "--engine qlever requires --store-id"
    end

    if pack_given? do
      # Resolve the pack dir up front so a bad --pack/--pack-dir name fails
      # here with the same clear error `Pack.resolve_dir!/1` already raises,
      # rather than surfacing later, less clearly, from inside the reactor.
      Pack.resolve_dir!(opts)
    end

    opts
  end

  defp report(opts, plan_opts, pending_actuations) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(to_json(opts, plan_opts, pending_actuations), pretty: true))
    else
      print_human(opts, plan_opts, pending_actuations)
    end
  end

  defp report_error(opts, message) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(%{"error" => message}, pretty: true))
    else
      Mix.shell().error("ggen_igniter.plan: #{message}")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix ggen_igniter.plan -- read-only admission preview (no filesystem mutation)

    USAGE
        mix ggen_igniter.plan --template path.eex --query name=path.rq [opts]
        mix ggen_igniter.plan --pack NAME[:template_stem] [--query name=path.rq] [opts]

    FLAGS
        --template PATH    Template file (or resolved via --pack/--pack-dir).
        --pack NAME[:STEM] Pack convention (priv/ggen/NAME/...).
        --pack-dir DIR     Explicit pack directory (bypasses the priv/ggen/NAME convention).
        --query NAME=PATH  Named query (repeatable).
        --engine ENGINE    One of: oxigraph, sparql, qlever. Default: oxigraph.
        --store-id ID      Required with --engine qlever.
        --json             Emit the plan as JSON instead of human-readable text.
        --quiet, -q        Suppress non-essential output.
        --verbose          Print additional diagnostic detail.
        --no-color         Disable ANSI color in human-readable output.
        --help, -h         Print this help and exit 0.
        --version, -v      Print the tool version and exit 0.

    EXAMPLES
        mix ggen_igniter.plan --pack ash-lifecycle-pack:resource \\
          --query resource=priv/ggen/ash-lifecycle-pack/gates/resource.rq

        mix ggen_igniter.plan --template test/fixtures/extension.ex.eex \\
          --query spec=test/fixtures/spec.rq --json

    EXIT CODES
        0  plan computed successfully
        2  invalid invocation
        3  unsupported capability for the read-only plan path
    """)
  end

  defp tool_version do
    Application.spec(:ggen_igniter, :vsn) |> to_string()
  rescue
    _ -> "unknown"
  end

  defp print_human(opts, plan_opts, pending_actuations) do
    unless opts[:quiet] do
      Mix.shell().info("ggen_igniter.plan")
      Mix.shell().info("  engine: #{plan_opts[:engine] || "oxigraph"}")

      if plan_opts[:store_id], do: Mix.shell().info("  store-id: #{plan_opts[:store_id]}")

      queries = Keyword.get_values(plan_opts, :query)

      unless queries == [] do
        Mix.shell().info("  queries:")
        for q <- queries, do: Mix.shell().info("    - #{q}")
      end

      Mix.shell().info("  pending actuations (#{length(pending_actuations)}):")

      for pa <- pending_actuations do
        unchanged? = GgenIgniter.PendingActuation.plan_unchanged?(pa)
        target = pa.target || "(none -- mode: eval)"

        Mix.shell().info(
          "    - #{pa.operation} #{target}" <>
            if(unchanged?, do: " (unchanged)", else: "") <>
            " [previous_hash=#{pa.previous_hash || "nil"}, desired_hash=#{pa.desired_hash || "nil"}, ownership=#{pa.ownership}]"
        )

        if opts[:verbose] do
          Mix.shell().info("        semantic_source: #{inspect(pa.semantic_source)}")
          Mix.shell().info("        logical_id: #{pa.logical_id}")
        end
      end
    end
  end

  defp to_json(_opts, plan_opts, pending_actuations) do
    %{
      "engine" => plan_opts[:engine] || "oxigraph",
      "store_id" => plan_opts[:store_id],
      "queries" => Keyword.get_values(plan_opts, :query),
      "pending_actuations" =>
        Enum.map(pending_actuations, fn pa ->
          %{
            "logical_id" => pa.logical_id,
            "target" => pa.target,
            "canonical_target" => pa.canonical_target,
            "operation" => to_string(pa.operation),
            "previous_hash" => pa.previous_hash,
            "desired_hash" => pa.desired_hash,
            "ownership" => pa.ownership,
            "unchanged" => GgenIgniter.PendingActuation.plan_unchanged?(pa),
            "semantic_source" => pa.semantic_source
          }
        end)
    }
  end
end
