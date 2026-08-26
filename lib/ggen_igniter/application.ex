defmodule GgenIgniter.Application do
  @moduledoc """
  Starts the real Finch HTTP pool `GgenIgniter.Finch` (used by `Tesla.Adapter.Finch`,
  configured in `config/config.exs`, for real HTTP calls made by
  `GgenIgniter.Query.Qlever` and `gno`'s `SPARQL.Client`) as part of the OTP
  application boot -- so any real `mix ggen_igniter.sync --engine qlever`
  invocation (a fresh process, not the test suite's own) has it available too.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # `gno` (and its transitive `finch` dep) is only: [:dev, :test] -- guard so a
    # prod build (which never uses the qlever engine) doesn't require it compiled.
    children =
      if Code.ensure_loaded?(Finch) do
        [{Finch, name: GgenIgniter.Finch}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: GgenIgniter.Supervisor)
  end
end
