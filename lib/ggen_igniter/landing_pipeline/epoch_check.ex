defmodule GgenIgniter.LandingPipeline.Stage.EpochCheck do
  @moduledoc """
  Stage 1 (`:epoch_check`) — epoch provenance gate. Thin adapter over
  `GgenIgniter.EpochFreshness.check/3` (the `mix ggen_igniter.epoch.check`
  engine), embedded in the landing pipeline before any other gate so an
  implementation plane that is not fresh-epoch-admitted never reaches build
  or review stages.

  `run/1`:

    * no `opts[:epoch]` → `{:refused, {:no_epoch, ...}}` — the stage cannot
      judge without an epoch id, and judging nothing is not a pass.
    * `EpochFreshness.check/3` `{:error, ...}` (unreadable/missing watermark)
      → `{:refused, ...}` — cannot judge at all.
    * `{:ok, report}` with any refused file count > 0 → `{:block, ...}` with
      the report's refused counts embedded.
    * otherwise `{:pass, ...}` with the report's subject tree embedded.

  Every `:pass`/`:block` embeds a real `Stage.capture/3` of
  `git rev-parse HEAD` (the subject identity the judgement is bound to) — a
  vacuous pass blocks by design (`GgenIgniter.LandingPipeline`'s realness
  law).
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :epoch_check

  @impl true
  def order, do: 1

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    epoch = ctx.opts[:epoch]

    if is_binary(epoch) and epoch != "" do
      head = Stage.capture("git", ["rev-parse", "HEAD"])
      epoch_outcome(GgenIgniter.EpochFreshness.check(File.cwd!(), epoch), head)
    else
      {:refused, {:no_epoch, "opts[:epoch] must be a non-empty binary epoch id"}}
    end
  end

  defp epoch_outcome({:ok, report}, head) do
    refused = get_in(report, ["planes", "summary", "refused"]) || count_refused(report)
    output = %{"output" => %{"commands" => [head]}, "epoch_report" => epoch_summary(report)}

    if is_integer(refused) and refused > 0 do
      {:block, {:epoch_refusals, refused}, output}
    else
      {:pass, output}
    end
  end

  defp epoch_outcome({:error, reason}, _head), do: {:refused, {:epoch_check_error, reason}}

  # The freshness report's refused count lives under a plane summary whose
  # exact shape is owned by EpochFreshness; read it defensively so a shape
  # evolution upstream is a typed fallback, not a KeyError crash.
  defp count_refused(report) do
    report
    |> Enum.flat_map(fn
      {"planes", v} when is_map(v) -> Map.values(v)
      _ -> []
    end)
    |> Enum.flat_map(fn
      %{"refused" => n} when is_integer(n) -> [n]
      _ -> []
    end)
    |> Enum.sum()
  end

  defp epoch_summary(report),
    do: %{
      "epoch" => report["epoch"],
      "subject_tree" => report["subject_tree"],
      "watermark_tree" => report["watermark_tree"]
    }
end
