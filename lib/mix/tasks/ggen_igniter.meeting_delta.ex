defmodule Mix.Tasks.GgenIgniter.MeetingDelta do
  @moduledoc """
  Project an authority-free ZOE meeting semantic delta into canonical Semantic
  Jira WorkOrder candidates.

      mix ggen_igniter.meeting_delta \
        --delta /secure/zoe-youth.delta.json \
        --binding /secure/zoe-youth.binding.json \
        --out /secure/zoe-youth.work-orders.json

  The task performs representation and kernel admission only. It does not
  perform SHACL admission, frontier selection, dispatch, DO, merge, publish,
  deployment, or standing promotion.
  """

  use Mix.Task

  alias GgenIgniter.SemanticJira

  @shortdoc "Project a typed meeting delta into authority-free Semantic Jira WorkOrders"

  @switches [delta: :string, binding: :string, out: :string, help: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches, aliases: [h: :help])

    cond do
      opts[:help] ->
        help()

      missing = Enum.find([:delta, :binding, :out], &(opts[&1] in [nil, ""])) ->
        Mix.raise("--#{String.replace(to_string(missing), "_", "-")} is required")

      true ->
        delta = read_json!(opts[:delta])
        binding = read_json!(opts[:binding])

        case SemanticJira.meeting_delta_work_orders(delta, binding) do
          {:ok, work_orders} ->
            result = %{
              "schema" => "semantic-jira.meeting-delta-work-orders.v1",
              "source_episode_id" => delta["episode_id"],
              "source_delta_digest" => delta["digest"],
              "authority" => "NONE",
              "do_authority" => false,
              "dispatch" => "NOT_EXECUTED",
              "work_orders" => work_orders
            }

            encoded = Jason.encode!(result, pretty: true) <> "\n"
            File.write!(opts[:out], encoded)
            Mix.shell().info(encoded)

          {:error, reason} ->
            Mix.raise("meeting delta refused: #{inspect(reason)}")
        end
    end
  end

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp help do
    Mix.shell().info("""
    USAGE
        mix ggen_igniter.meeting_delta --delta PATH --binding PATH --out PATH

    BOUNDARY
        Representation + kernel admission only.
        No SHACL admission, dispatch, DO, merge, publication, deployment, or standing promotion.
    """)
  end
end
