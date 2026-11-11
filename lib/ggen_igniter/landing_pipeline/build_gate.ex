defmodule GgenIgniter.LandingPipeline.Stage.BuildGate do
  @moduledoc """
  Stage 3 (`:build_gate`) — compile gate. A real
  `mix compile --warnings-as-errors` subprocess (`Stage.capture/3`, list
  args, stderr merged), so the embedded output IS the compile verdict: a
  `:pass` with exit 0 is a witnessed clean compile, a `:block` carries the
  failing compiler diagnostics tail. There is no in-process shortcut by
  design — a compile claim without a real run is exactly the vacuous pass
  the pipeline's realness law refuses.

  `MIX_BUILD_ROOT` (and every other env var) is inherited by
  `System.cmd/3`, so per-lane build isolation (`_build-lane-c14`) holds for
  the spawned compile too.
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :build_gate

  @impl true
  def order, do: 3

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{}) do
    capture = Stage.capture("mix", ["compile", "--warnings-as-errors"])

    if capture["exit"] == 0 do
      {:pass, %{"output" => %{"commands" => [capture]}}}
    else
      {:block, {:build_failed, capture["exit"]}, %{"output" => %{"commands" => [capture]}}}
    end
  end
end
