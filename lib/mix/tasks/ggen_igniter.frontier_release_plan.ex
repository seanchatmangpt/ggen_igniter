defmodule Mix.Tasks.GgenIgniter.FrontierReleasePlan do
  @moduledoc """
  Read-only Frontier Release response-plan preview: `mix
  ggen_igniter.frontier_release_plan --opportunity-id ID --project-name NAME
  --project-dir DIR --target-repository OWNER/REPO --pack-dir DIR
  --response-mode reuse|compose|extend|invent --repository-mode reuse|create
  --visibility public|private [--json]`.

  Wires `GgenIgniter.FrontierReleasePlan.new/2` (previously dead code with no
  production call site) to a real CLI surface. Builds a minimal admitted
  source `GgenIgniter.RuntimeShape` from the given `--opportunity-id`, then
  calls `GgenIgniter.FrontierReleasePlan.new/2` to produce a content-addressed
  response-plan projection, and reports its ordered steps.

  This task performs NO filesystem mutation and invokes no external tool
  (`gh`, `mix igniter.new`, `mix ggen_igniter.sync`) -- it only describes,
  as structured data, which intents a later authority-aware runtime would
  need to broker/execute. Per `GgenIgniter.FrontierReleasePlan`'s own
  moduledoc, this task never actuates.

  ## Output

  Human-readable (default) or `--json`: the ordered `steps`, split into
  `construct_intents` (reversible, no broker) and `do_intents` (consequential,
  broker-required).

  ## Exit codes

    * `0` -- plan computed successfully.
    * `2` -- invalid invocation (missing/invalid required attrs).

  ## Example

      mix ggen_igniter.frontier_release_plan \\
        --opportunity-id frontier-release-example \\
        --project-name frontier_response \\
        --project-dir /tmp/frontier_response \\
        --target-repository seanchatmangpt/frontier-response \\
        --pack-dir /packs/frontier-release-factory-pack \\
        --response-mode compose --repository-mode create --visibility public
  """
  use Mix.Task

  alias GgenIgniter.{FrontierReleasePlan, RuntimeShape}

  @shortdoc "Read-only preview of a Frontier Release response plan (no actuation)"

  @switches [
    opportunity_id: :string,
    project_name: :string,
    project_dir: :string,
    target_repository: :string,
    pack_dir: :string,
    response_mode: :string,
    repository_mode: :string,
    visibility: :string,
    json: :boolean,
    help: :boolean
  ]

  @required ~w(opportunity_id project_name project_dir target_repository pack_dir response_mode repository_mode visibility)a

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)

    if opts[:help] do
      print_help()
    else
      run_plan(opts)
    end
  end

  defp run_plan(opts) do
    with :ok <- validate_required!(opts),
         {:ok, source_shape} <- build_source_shape(opts),
         {:ok, plan} <- FrontierReleasePlan.new(source_shape, plan_attrs(opts)),
         {:ok, steps} <- FrontierReleasePlan.steps(plan),
         {:ok, construct_intents} <- FrontierReleasePlan.construct_intents(plan),
         {:ok, do_intents} <- FrontierReleasePlan.do_intents(plan) do
      report(opts, steps, construct_intents, do_intents)
    else
      {:error, reason} ->
        report_error(opts, reason)
        exit_or_halt(2)
    end
  end

  defp validate_required!(opts) do
    missing = Enum.filter(@required, fn key -> opts[key] in [nil, ""] end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  defp build_source_shape(opts) do
    {:ok,
     RuntimeShape.new!(%{
       subject_id: "opportunity:#{opts[:opportunity_id]}",
       source_digest: "sha256:cli-source",
       graph_digest: "sha256:cli-graph",
       ontology_versions: %{"frontier-release-factory" => "0.1.0"},
       admission: %{"standing" => "CANDIDATE", "authority" => "NONE"}
     })}
  rescue
    error -> {:error, {:invalid_source_shape, Exception.message(error)}}
  end

  defp plan_attrs(opts) do
    %{
      opportunity_id: opts[:opportunity_id],
      project_name: opts[:project_name],
      project_dir: opts[:project_dir],
      target_repository: opts[:target_repository],
      pack_dir: opts[:pack_dir],
      response_mode: opts[:response_mode],
      repository_mode: opts[:repository_mode],
      visibility: opts[:visibility]
    }
  end

  defp report(opts, steps, construct_intents, do_intents) do
    if opts[:json] do
      Mix.shell().info(
        Jason.encode!(
          %{
            "steps" => steps,
            "construct_intents" => construct_intents,
            "do_intents" => do_intents
          },
          pretty: true
        )
      )
    else
      Mix.shell().info("ggen_igniter.frontier_release_plan")
      Mix.shell().info("  steps (#{length(steps)}):")

      for step <- steps do
        Mix.shell().info("    - [#{step["class"]}] #{step["id"]} (#{step["executable"]})")
      end

      Mix.shell().info("  construct_intents: #{length(construct_intents)}")
      Mix.shell().info("  do_intents (broker-required): #{length(do_intents)}")
    end
  end

  defp report_error(opts, reason) do
    message = "ggen_igniter.frontier_release_plan: #{inspect(reason)}"

    if opts[:json] do
      Mix.shell().info(Jason.encode!(%{"error" => message}, pretty: true))
    else
      Mix.shell().error(message)
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix ggen_igniter.frontier_release_plan -- read-only Frontier Release response-plan preview

    USAGE
        mix ggen_igniter.frontier_release_plan --opportunity-id ID --project-name NAME \\
          --project-dir DIR --target-repository OWNER/REPO --pack-dir DIR \\
          --response-mode reuse|compose|extend|invent --repository-mode reuse|create \\
          --visibility public|private [--json]

    This task never mutates the filesystem and never invokes gh/mix igniter.new/
    mix ggen_igniter.sync -- it only describes the intents a later authority-aware
    runtime would need to broker/execute.

    EXIT CODES
        0  plan computed successfully
        2  invalid invocation
    """)
  end

  # Mix.Task in a real Mix run should exit non-zero via System.halt; tests
  # invoke run/1 directly and must not have the test process halted.
  defp exit_or_halt(code) do
    if Code.ensure_loaded?(Mix) and Mix.env() == :test do
      :ok
    else
      System.halt(code)
    end
  end
end
