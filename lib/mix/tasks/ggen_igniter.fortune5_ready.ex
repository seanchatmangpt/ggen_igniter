defmodule Mix.Tasks.GgenIgniter.Fortune5Ready do
  @moduledoc """
  GGEN-1807 (`docs/jira/v26.9.1/05-FORTUNE5-READY-MIX-TASK-AND-E2E-TEST.md`):
  assembles tickets 01-04 into one real, runnable
  `mix ggen_igniter.fortune5_ready [--path DIR] [--pack-dir DIR] [--bundle NAME] [--yes]`
  task, modeled directly on `lib/mix/tasks/ggen_igniter.install.ex`'s real
  structure (`use Igniter.Mix.Task`, the `"--help" in argv` early-exit
  precedent, and the defensive-probe-before-acting pattern that
  `install.ex`'s `deps_probe/1` demonstrates).

  ## Pipeline

  1. **`dispatch_probe/1`** -- calls `GgenIgniter.SchemaDispatch.load/1`
     exactly once against the target project's real `ggen.toml`, the same
     shared classifier every other call site in this codebase uses (no
     bespoke schema-guessing is written here -- see `SchemaDispatch`'s own
     `BUG-005` moduledoc). On a `:refused` classification, this task fails
     closed via `Igniter.add_issue/2` and runs nothing further -- no merge,
     no write, no shellout.
  2. **`parse_step/2`** -- stashes the already-typed struct
     (`GgenIgniter.FrontmatterConfig` or `GgenIgniter.ProjectConfig`, ticket
     01/02's real parse) and which schema it is, via `Igniter.assign/3`.
  3. **`merge_bundle_step/2`** -- loads the named bundle
     (`GgenIgniter.Bundle.load_packs!/2`, default `"fortune5_ready"` from
     `priv/bundles/fortune5_ready.json`) and merges it into the parsed
     config. `GgenIgniter.Bundle.merge/2` (ticket 03) already covers the
     Frontmatter schema; `merge_declarative/2` below is this ticket's own
     glue for the DeclarativeRules schema (dedup by pack name against
     `GgenIgniter.PackRef.name`, the array-of-tables analogue), so dispatch
     genuinely branches on ticket 01's classifier rather than assuming the
     Frontmatter default.
  4. **`serialize_step/1`** -- `GgenIgniter.GgenToml.IO.serialize!/1` (ticket
     02) back to TOML text, written to `<path>/ggen.toml` for real. This
     happens *before* the sync shellout because `ggen sync run` reads
     `ggen.toml` off disk -- the newly-merged `[packs]` entries must already
     be there for the real subprocess to see them.
  5. **`sync_step/1`** -- `GgenIgniter.SyncVerify.run/3` (ticket 04) when
     `--pack-dir` is given (real `ggen sync run` shellout, then real
     per-gate SPARQL verification); falls back to
     `GgenIgniter.SyncShellout.run/2` alone (sync-only, no gates) when no
     pack dir was supplied, so the task remains usable without a pack to
     gate-check.
  6. **`report_step/1`** -- fail-loud: any error from step 5 (a sync
     failure, an upstream-gating refusal, or a named `{:gate_failed,
     gate_name}`) is reported via `Igniter.add_issue/2`, naming the failure,
     and the success notice is never emitted. A run where sync succeeds but
     a gate fails is reported as a failed `fortune5_ready` run, full stop --
     "compilation/file-existence alone is not a crown."  Only a genuine
     `{:ok, %{gates: gates}}` (every gate a `:pass`, or no pack dir supplied
     at all) reaches the success `Igniter.add_notice/2`, which names the
     packs newly merged (from the merge step's own real return value, not
     re-derived by diffing files after the fact), the gates that passed,
     the gates that failed (empty on success), and the final `ggen.toml`
     classification the run dispatched against.
  """

  use Igniter.Mix.Task

  alias GgenIgniter.{
    Bundle,
    FrontmatterConfig,
    GgenToml,
    PackRef,
    ProjectConfig,
    SchemaDispatch,
    SyncShellout,
    SyncVerify
  }

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      schema: [path: :string, pack_dir: :string, bundle: :string, bundle_path: :string, yes: :boolean],
      aliases: [y: :yes]
    }
  end

  @impl Mix.Task
  def run(argv) do
    if "--help" in argv do
      print_help_and_halt()
    else
      super(argv)
    end
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    path = igniter.args.options[:path] || File.cwd!()
    pack_dir = igniter.args.options[:pack_dir]
    bundle_name = igniter.args.options[:bundle] || "fortune5_ready"
    bundle_path = igniter.args.options[:bundle_path] || Bundle.default_manifest_path()

    case dispatch_probe(path) do
      {:ok, classification} ->
        igniter
        |> Igniter.assign(:fortune5_ready_project_dir, path)
        |> Igniter.assign(:fortune5_ready_pack_dir, pack_dir)
        |> parse_step(classification)
        |> merge_bundle_step(bundle_name, bundle_path)
        |> serialize_step()
        |> sync_step()
        |> report_step()

      {:error, reason} ->
        Igniter.add_issue(igniter, fortune5_ready_issue_text(reason))
    end
  end

  # Runs ticket 01's shared classifier exactly once against the target
  # project's real ggen.toml -- no local schema-guessing. `{:ok,
  # classification}` on a real `:declarative_rules`/`:frontmatter` result;
  # `{:error, reason}` on a `:refused` classification (missing/unreadable
  # file, malformed TOML, ambiguous, or unsupported).
  defp dispatch_probe(path) do
    case SchemaDispatch.load(path) do
      {:refused, reason} -> {:error, reason}
      classification -> {:ok, classification}
    end
  end

  defp parse_step(igniter, {:frontmatter, config}) do
    igniter
    |> Igniter.assign(:fortune5_ready_schema, :frontmatter)
    |> Igniter.assign(:fortune5_ready_config, config)
  end

  defp parse_step(igniter, {:declarative_rules, config}) do
    igniter
    |> Igniter.assign(:fortune5_ready_schema, :declarative_rules)
    |> Igniter.assign(:fortune5_ready_config, config)
  end

  defp merge_bundle_step(igniter, bundle_name, bundle_path) do
    bundle_packs = Bundle.load_packs!(bundle_name, bundle_path)
    config = igniter.assigns[:fortune5_ready_config]
    schema = igniter.assigns[:fortune5_ready_schema]

    {new_config, added_pack_names} = merge_into(schema, config, bundle_packs)

    igniter
    |> Igniter.assign(:fortune5_ready_config, new_config)
    |> Igniter.assign(:fortune5_ready_added_packs, added_pack_names)
  end

  # Frontmatter schema: dedup + entry-shape delegated entirely to ticket
  # 03's real `GgenIgniter.Bundle.merge/2` -- no re-derivation here.
  defp merge_into(:frontmatter, %FrontmatterConfig{} = config, bundle_packs) do
    to_add = Bundle.merge(config, bundle_packs)

    new_packs =
      Enum.reduce(to_add, config.packs, fn %Bundle.Pack{name: name, path_hint: path_hint}, acc ->
        Map.put(acc, name, {:path, %{path: path_hint, extra_ontologies: [], lock: nil}})
      end)

    {%{config | packs: new_packs}, Enum.map(to_add, & &1.name)}
  end

  # DeclarativeRules schema: this ticket's own glue (ticket 03 scoped only
  # the Frontmatter merge). Same dedup discipline -- by `PackRef.name`, the
  # array-of-tables analogue of the Frontmatter map's key, never by path --
  # so a bundle pack already present under a different path is still
  # correctly treated as already-installed, and idempotent re-merge is a
  # true no-op.
  defp merge_into(:declarative_rules, %ProjectConfig{packs: existing_packs} = config, bundle_packs)
       when is_list(existing_packs) do
    existing_names = existing_packs |> Enum.map(& &1.name) |> MapSet.new()
    to_add = Enum.reject(bundle_packs, &MapSet.member?(existing_names, &1.name))

    new_pack_refs =
      Enum.map(to_add, fn %Bundle.Pack{name: name, path_hint: path_hint} ->
        %PackRef{name: name, registry: "local", path: path_hint, version: nil}
      end)

    {%{config | packs: existing_packs ++ new_pack_refs}, Enum.map(to_add, & &1.name)}
  end

  defp serialize_step(igniter) do
    project_dir = igniter.assigns[:fortune5_ready_project_dir]
    config = igniter.assigns[:fortune5_ready_config]
    content = GgenToml.IO.serialize!(config)
    File.write!(Path.join(project_dir, "ggen.toml"), content)
    igniter
  end

  defp sync_step(igniter) do
    project_dir = igniter.assigns[:fortune5_ready_project_dir]
    pack_dir = igniter.assigns[:fortune5_ready_pack_dir]

    result =
      case pack_dir do
        nil ->
          case SyncShellout.run(project_dir) do
            {:ok, output} -> {:ok, %{sync: output, gates: []}}
            error -> error
          end

        dir ->
          SyncVerify.run(project_dir, dir)
      end

    Igniter.assign(igniter, :fortune5_ready_result, result)
  end

  defp report_step(igniter) do
    case igniter.assigns[:fortune5_ready_result] do
      {:ok, %{gates: gates}} ->
        added = igniter.assigns[:fortune5_ready_added_packs] || []
        schema = igniter.assigns[:fortune5_ready_schema]
        passed = Enum.map(gates, fn {name, :pass} -> name end)

        Igniter.add_notice(igniter, """
        mix ggen_igniter.fortune5_ready: succeeded.

        schema: #{schema}
        packs added: #{format_names(added)}
        gates passed: #{format_names(passed)}
        gates failed: (none)
        """)

      {:error, {:gate_failed, gate_name}} ->
        Igniter.add_issue(
          igniter,
          "mix ggen_igniter.fortune5_ready: FAILED -- gate #{inspect(gate_name)} did not " <>
            "pass. The bundle merge was written to ggen.toml (ggen sync run needs the " <>
            "merged [packs] on disk to run at all), but gate verification failed -- this " <>
            "is reported as a failed run, not a partial success."
        )

      {:error, :upstream_failed} ->
        Igniter.add_issue(
          igniter,
          "mix ggen_igniter.fortune5_ready: FAILED -- upstream_ok?: false gated the sync " <>
            "shellout before it ran."
        )

      {:error, reason} ->
        Igniter.add_issue(igniter, "mix ggen_igniter.fortune5_ready: FAILED -- #{inspect(reason)}")
    end
  end

  defp format_names([]), do: "(none)"
  defp format_names(names), do: Enum.join(names, ", ")

  defp fortune5_ready_issue_text(reason) do
    "mix ggen_igniter.fortune5_ready: could not classify the target project's ggen.toml -- " <>
      inspect(reason)
  end

  defp print_help_and_halt do
    Mix.shell().info("""
    mix ggen_igniter.fortune5_ready [--path DIR] [--pack-dir DIR] [--bundle NAME] [--yes]

    Merges the fortune5-ready pack bundle into the target project's real
    ggen.toml (auto-dispatching Frontmatter vs DeclarativeRules schema via
    GgenIgniter.SchemaDispatch), shells out to a real `ggen sync run`
    against it, and -- when --pack-dir is given -- verifies that pack's own
    gates/*.rq queries against the regenerated ontology.

      --path         target project directory (default: cwd)
      --pack-dir     pack directory whose gates/*.rq are verified post-sync
                     (sync-only, no gate check, when omitted)
      --bundle       bundle name in the manifest (default: fortune5_ready)
      --bundle-path  override the bundle manifest path (default:
                     priv/bundles/fortune5_ready.json inside this app)
      --yes, -y      answer yes to any prompts
    """)

    System.halt(0)
  end
end
