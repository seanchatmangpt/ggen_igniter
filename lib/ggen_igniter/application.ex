defmodule GgenIgniter.Application do
  @moduledoc """
  Starts the real Finch HTTP pool `GgenIgniter.Finch` (used by `Tesla.Adapter.Finch`,
  configured in `config/config.exs`, for real HTTP calls made by
  `GgenIgniter.Query.Qlever` and `gno`'s `SPARQL.Client`) as part of the OTP
  application boot -- so any real `mix ggen_igniter.sync --engine qlever`
  invocation (a fresh process, not the test suite's own) has it available too.

  Optionally also starts `GgenIgniter.Controller` (a persistent, BEAM-native
  reconciliation `GenServer` -- see its own moduledoc) as a supervised, named
  singleton (registered as `GgenIgniter.Controller`) -- OPT-IN ONLY, gated
  behind `Application.get_env(:ggen_igniter, :start_controller, false)`,
  which DEFAULTS TO `false`. A library must never impose a persistent
  process on every consumer by default; a consuming application that wants
  the controller sets `config :ggen_igniter, start_controller: true`
  explicitly. With the default `false`, existing consumers who only want the
  CLI (`mix ggen_igniter.sync`) see zero behavior change from this child.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # `gno` (and its transitive `finch` dep) is only: [:dev, :test] -- guard so a
    # prod build (which never uses the qlever engine) doesn't require it compiled.
    finch_children =
      if Code.ensure_loaded?(Finch) do
        [{Finch, name: GgenIgniter.Finch}]
      else
        []
      end

    controller_children =
      if Application.get_env(:ggen_igniter, :start_controller, false) do
        [{GgenIgniter.Controller, name: GgenIgniter.Controller}]
      else
        []
      end

    children = finch_children ++ controller_children

    Supervisor.start_link(children, strategy: :one_for_one, name: GgenIgniter.Supervisor)
  end
end
